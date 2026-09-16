const std = @import("std");
const build_options = @import("build_options");
const posix = std.posix;
const Terminal = @import("tui/terminal.zig").Terminal;
const Renderer = @import("tui/renderer.zig").Renderer;
const Layout = @import("tui/layout.zig").Layout;
const invalidation = @import("tui/invalidation.zig");
const input = @import("tui/input.zig");
const ActivityBar = @import("tui/widgets/activity_bar.zig").ActivityBar;
const Explorer = @import("tui/widgets/explorer.zig").Explorer;
const GitPanel = @import("tui/widgets/git_panel.zig").GitPanel;
const SettingsWidget = @import("tui/widgets/settings.zig").SettingsWidget;

test "settings configuration and command shortcuts" {
    _ = @import("tui/widgets/settings.zig");
}
const MasonWidget = @import("tui/widgets/mason.zig").MasonWidget;
const LazyWidget = @import("tui/widgets/lazy.zig").LazyWidget;
const GitDetailedWidget = @import("tui/widgets/git_detailed.zig").GitDetailedWidget;
const SearchPanel = @import("tui/widgets/search_panel.zig").SearchPanel;
const OutputPanel = @import("tui/widgets/output_panel.zig").OutputPanel;
const DebugConsole = @import("tui/widgets/debug_console.zig").DebugConsole;
const ExtensionShop = @import("tui/widgets/extension_shop.zig").ExtensionShop;
const BugReportWidget = @import("tui/widgets/bug_report.zig").BugReportWidget;

const NvimProcess = @import("nvim/process.zig").NvimProcess;
const RpcClient = @import("nvim/rpc.zig").RpcClient;
const ui_protocol = @import("nvim/ui_protocol.zig");
const UiState = ui_protocol.UiState;
const msgpack = @import("nvim/msgpack.zig");
const Value = msgpack.Value;
const App = @import("tui/app.zig").App;
const RpcContext = @import("tui/app.zig").RpcContext;
const nvim_helpers = @import("nvim/helpers.zig");
const views = @import("tui/views.zig");
const events = @import("tui/events.zig");
const Capabilities = @import("tui/capabilities.zig").Capabilities;
const metrics = @import("metrics.zig");
const reactor_mod = @import("reactor.zig");
const git_snapshot = @import("git_snapshot.zig");
const task_runner = @import("task_runner.zig");
const Completion = @import("nvim/async_transport.zig").Completion;
const async_effects = @import("nvim/call_sites_05c.zig");

var global_term: ?*Terminal = null;
var log_path: ?[]const u8 = null;
var quit_signal_received = std.atomic.Value(bool).init(false);

// SIGTERM/SIGHUP only set a flag and wake the reactor so the event loop
// returns normally and deferred terminal restoration runs.
fn handleQuitSignal(sig: posix.SIG) callconv(.c) void {
    _ = sig;
    quit_signal_received.store(true, .monotonic);
    if (input.sigwinch_pipe_write_fd) |fd| {
        _ = posix.system.write(fd, "Q", 1);
    }
}

fn zenSessionSaved(context: ?*anyopaque, completion: *Completion) anyerror!void {
    const app: *App = @ptrCast(@alignCast(context.?));
    if (!async_effects.applyDeferredExit(&app.deferred_exit, .zen_handoff, completion)) app.notify(.failure, "Unable to save the Zen handoff session.", .{});
}

fn reloadSessionSaved(context: ?*anyopaque, completion: *Completion) anyerror!void {
    const app: *App = @ptrCast(@alignCast(context.?));
    if (!async_effects.applyDeferredExit(&app.deferred_exit, .reload, completion)) app.notify(.failure, "Unable to save the reload session.", .{});
}

fn queueSessionSave(allocator: std.mem.Allocator, rpc: *RpcClient, app: *App, session_path: []const u8, callback: RpcClient.AsyncHandler) !void {
    const script = try std.fmt.allocPrint(allocator, "vim.cmd('silent! wa'); vim.cmd('mksession! {s}')", .{session_path});
    defer allocator.free(script);
    var params = [_]Value{ .{ .string = script }, .{ .array = &.{} } };
    _ = try rpc.requestAsyncWithHandler("nvim_exec_lua", &params, app, callback);
}

const ReactorReadiness = struct {
    terminal_input: bool = false,
    resize_signal: bool = false,
    editor_transport: bool = false,
    terminal_transport: bool = false,
    editor_write: bool = false,
    terminal_write: bool = false,
    editor_failed: bool = false,
    terminal_failed: bool = false,
    task_completion: bool = false,

    fn accept(self: *ReactorReadiness, ready: reactor_mod.Ready) !void {
        const read_or_closed = ready.readable or ready.hung_up or ready.failed;
        switch (ready.source) {
            .terminal_input => self.terminal_input = ready.readable,
            .resize_signal => self.resize_signal = ready.readable,
            .nvim_editor_read => {
                self.editor_transport = read_or_closed;
                self.editor_failed = ready.failed;
            },
            .nvim_terminal_read => {
                self.terminal_transport = read_or_closed;
                self.terminal_failed = ready.failed;
            },
            .nvim_editor_write => self.editor_write = ready.writable,
            .nvim_terminal_write => self.terminal_write = ready.writable,
            .task_completion => self.task_completion = ready.readable,
        }
    }
};

fn submitGitRefresh(allocator: std.mem.Allocator, runner: *task_runner.Runner, owners: *task_runner.OwnerRegistry, owner: task_runner.OwnerId, invalidate: bool) !void {
    const generation = if (invalidate) try owners.invalidate(owner) else owners.generation(owner) orelse return error.UnknownOwner;
    const task_id = try owners.nextTask(owner);
    errdefer std.debug.assert(owners.rollbackTask(owner, task_id));
    var command = try task_runner.Command.init(allocator, .refresh_latest, owner, generation, null, ".");
    command.task_id = task_id;
    var caller_owns = true;
    defer if (caller_owns) command.deinit(allocator);
    try runner.submit(command);
    caller_owns = false;
}

fn drainGitRefreshes(allocator: std.mem.Allocator, runner: *task_runner.Runner, owners: *task_runner.OwnerRegistry, panel: *GitPanel) bool {
    var changed = false;
    while (runner.takeCompletion()) |completion_value| {
        var completion = completion_value;
        var accepted = owners.validate(allocator, &completion) orelse continue;
        defer accepted.deinit(allocator);
        switch (accepted.outcome) {
            .success => |*result| switch (result.*) {
                .refresh_latest => |*snapshot| {
                    panel.applySnapshot(snapshot) catch |err| {
                        std.log.warn("Git snapshot apply failed: {}", .{err});
                        continue;
                    };
                    changed = true;
                },
                else => {},
            },
            else => {},
        }
    }
    return changed;
}

pub const std_options: std.Options = .{ .logFn = log };

fn createNonblockingPipe() ![2]posix.fd_t {
    var fds: [2]posix.fd_t = undefined;
    if (@TypeOf(posix.system.pipe2) != void) {
        const rc = posix.system.pipe2(&fds, .{ .NONBLOCK = true });
        if (posix.errno(rc) != .SUCCESS) return error.PipeFailed;
        return fds;
    }

    const rc = posix.system.pipe(&fds);
    if (posix.errno(rc) != .SUCCESS) return error.PipeFailed;
    errdefer {
        _ = posix.system.close(fds[0]);
        _ = posix.system.close(fds[1]);
    }
    for (fds) |fd| {
        const current = posix.system.fcntl(fd, posix.F.GETFL, @as(usize, 0));
        if (current < 0) return error.PipeFailed;
        const nonblocking: usize = @as(u32, @bitCast(posix.O{ .NONBLOCK = true }));
        if (posix.system.fcntl(fd, posix.F.SETFL, @as(usize, @intCast(current)) | nonblocking) < 0)
            return error.PipeFailed;
    }
    return fds;
}

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.default),
    comptime format: []const u8,
    args: anytype,
) void {
    const path = log_path orelse return;
    var log_timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.blocking_io_log);
    defer log_timer.stop();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const path_z = alloc.dupeSentinel(u8, path, 0) catch return;
    const fd = std.posix.openatZ(std.posix.AT.FDCWD, path_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .APPEND = true }, 0o644) catch return;
    defer _ = std.posix.system.close(fd);

    var storage: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&storage);

    const level_str = switch (message_level) {
        .err => "ERROR",
        .warn => "WARN",
        .info => "INFO",
        .debug => "DEBUG",
    };

    if (scope == .default) {
        writer.print("[{s}] ", .{level_str}) catch return;
    } else {
        writer.print("[{s}] ({s}) ", .{ level_str, @tagName(scope) }) catch return;
    }
    writer.print(format, args) catch return;
    writer.print("\n", .{}) catch return;

    const items = writer.buffered();
    var written: usize = 0;
    while (written < items.len) {
        const sub = items[written..];
        const rc = std.posix.system.write(fd, sub.ptr, sub.len);
        switch (std.posix.errno(rc)) {
            .SUCCESS => written += @as(usize, @intCast(rc)),
            .INTR => continue,
            else => return,
        }
    }
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = error_return_trace;
    if (global_term) |term| {
        term.deinit();
    } else {
        const esc = "\x1b[?2004l\x1b[?1003l\x1b[?1002l\x1b[?1006l\x1b[?25h\x1b[?1049l\x1b[0m\r\n";
        _ = posix.system.write(2, esc, esc.len);
    }
    std.debug.defaultPanic(msg, ret_addr);
}

pub fn main(init: std.process.Init) !void {
    innerMain(init) catch |err| switch (err) {
        error.EndOfStream, error.QuitApplication => return,
        error.NvimNotFound => {
            std.debug.print("Tuim could not start: Neovim (nvim) not found on PATH\n", .{});
            std.process.exit(1);
        },
        error.TerminalUnavailable => {
            std.debug.print("Tuim could not start: no interactive terminal available\n", .{});
            std.process.exit(1);
        },
        else => {
            std.debug.print("Tuim could not start: {}. Verify Neovim is installed and check Tuim's log.\n", .{err});
            return err;
        },
    };
}

const usage =
    \\Usage: tuim [options] [file ...]
    \\
    \\Options:
    \\  -h, --help       Show this help and exit
    \\  -V, --version    Print the version and exit
    \\  --diagnostics    Write diagnostics.json on exit
    \\  --               Treat all following arguments as files
    \\
;

const ArgKind = enum { help, version, diagnostics, end_of_options, unknown_option, file };

fn classifyArg(arg: []const u8) ArgKind {
    if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) return .help;
    if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-V")) return .version;
    if (std.mem.eql(u8, arg, "--diagnostics")) return .diagnostics;
    if (std.mem.eql(u8, arg, "--")) return .end_of_options;
    if (arg.len > 1 and arg[0] == '-') return .unknown_option;
    return .file;
}

fn usableSize(size: [2]u16) [2]u16 {
    if (size[0] == 0 or size[1] == 0) return .{ 80, 24 };
    return size;
}

fn spawnNvim(io: std.Io, environ_map: *const std.process.Environ.Map) !NvimProcess {
    return NvimProcess.spawn(io, environ_map) catch |err| if (err == error.FileNotFound) error.NvimNotFound else err;
}

fn hasUsableTerminal(io: std.Io) bool {
    if (posix.openat(posix.AT.FDCWD, "/dev/tty", .{ .ACCMODE = .RDWR }, 0)) |fd| {
        _ = posix.system.close(fd);
        return true;
    } else |_| {}
    return std.Io.File.stdin().isTty(io) catch false;
}

fn diagnosticsRequested(init: std.process.Init) bool {
    if (init.environ_map.get("TUIM_DIAGNOSTICS")) |value| {
        if (value.len > 0 and !std.mem.eql(u8, value, "0") and !std.ascii.eqlIgnoreCase(value, "false")) return true;
    }
    var args = init.minimal.args.iterate();
    _ = args.skip();
    while (args.next()) |arg| switch (classifyArg(arg)) {
        .diagnostics => return true,
        .end_of_options => return false,
        else => {},
    };
    return false;
}

fn printVersion(init: std.process.Init) !void {
    var buffer: [128]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    try stdout.interface.print("tuim {s}\n", .{build_options.version});
    try stdout.interface.flush();
}

fn innerMain(init: std.process.Init) !void {
    const alloc = init.gpa;
    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(alloc);
    {
        var args = init.minimal.args.iterate();
        _ = args.skip(); // skip executable name
        var options_ended = false;
        while (args.next()) |arg| {
            const kind: ArgKind = if (options_ended) .file else classifyArg(arg);
            switch (kind) {
                .help => {
                    var buffer: [512]u8 = undefined;
                    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
                    try stdout.interface.writeAll(usage);
                    try stdout.interface.flush();
                    return;
                },
                .version => {
                    try printVersion(init);
                    return;
                },
                .unknown_option => {
                    std.debug.print("tuim: unknown option '{s}'\n{s}", .{ arg, usage });
                    std.process.exit(2);
                },
                .end_of_options => options_ended = true,
                .diagnostics => {},
                .file => try files.append(alloc, arg),
            }
        }
    }

    const capabilities = Capabilities.detect(init.environ_map);
    const home = init.environ_map.get("HOME") orelse "";
    const fallback_data_home = try std.fs.path.join(alloc, &.{ home, ".local", "share" });
    defer alloc.free(fallback_data_home);
    const data_home = init.environ_map.get("XDG_DATA_HOME") orelse fallback_data_home;
    const app_data_dir = try std.fs.path.join(alloc, &.{ data_home, "tuim" });
    defer alloc.free(app_data_dir);
    metrics.global.enabled = diagnosticsRequested(init);
    defer if (metrics.global.enabled) {
        const diagnostics_path = std.fs.path.join(alloc, &.{ app_data_dir, "diagnostics.json" }) catch null;
        if (diagnostics_path) |path| {
            defer alloc.free(path);
            var json = std.Io.Writer.Allocating.init(alloc);
            defer json.deinit();
            if (metrics.global.exportJson(&json.writer)) {
                if (std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o600)) |fd| {
                    defer _ = std.posix.system.close(fd);
                    const bytes = json.written();
                    var written: usize = 0;
                    while (written < bytes.len) {
                        const rc = std.posix.system.write(fd, bytes[written..].ptr, bytes.len - written);
                        switch (std.posix.errno(rc)) {
                            .SUCCESS => written += @intCast(rc),
                            .INTR => continue,
                            else => break,
                        }
                    }
                } else |_| {}
            } else |_| {}
        }
    };

    // Isolate all Neovim config, data, state, cache, undo and plugins from the
    // user's own Neovim. `--clean` also prevents sourcing their init.lua.
    var nvim_environ = try init.environ_map.clone(alloc);
    defer nvim_environ.deinit();
    try nvim_environ.put("NVIM_APPNAME", "tuim");

    // Set up logging
    var data_dir = try std.Io.Dir.cwd().createDirPathOpen(init.io, app_data_dir, .{});
    data_dir.close(init.io);
    log_path = try std.fs.path.join(alloc, &[_][]const u8{ app_data_dir, "tuim.log" });
    defer {
        if (log_path) |p| {
            alloc.free(p);
            log_path = null;
        }
    }

    // Write store search helper script
    {
        const script_path = try std.fs.path.join(alloc, &[_][]const u8{ app_data_dir, "store_search.py" });
        defer alloc.free(script_path);
        const script_content = @embedFile("nvim/store_search.py");
        if (std.posix.openat(std.posix.AT.FDCWD, script_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o755)) |fd| {
            defer _ = std.posix.system.close(fd);
            var written: usize = 0;
            while (written < script_content.len) {
                const sub = script_content[written..];
                const rc = std.posix.system.write(fd, sub.ptr, sub.len);
                switch (std.posix.errno(rc)) {
                    .SUCCESS => written += @as(usize, @intCast(rc)),
                    .INTR => continue,
                    else => break,
                }
            }
        } else |_| {}
    }

    const session_path = try std.fs.path.join(alloc, &[_][]const u8{ app_data_dir, "tuim_session.vim" });
    defer alloc.free(session_path);
    const handoff_path = try std.fs.path.join(alloc, &[_][]const u8{ app_data_dir, "tuim_handoff_init.lua" });
    defer alloc.free(handoff_path);

    if (!hasUsableTerminal(init.io)) return error.TerminalUnavailable;

    // Publish the wake pipe before installing handlers so no signal can set
    // its flag without also waking the reactor, and install both before the
    // terminal enters raw mode so a signal can never skip restoration.
    const sigwinch_pipe = try createNonblockingPipe();
    defer {
        input.sigwinch_pipe_write_fd = null;
        _ = std.posix.system.close(sigwinch_pipe[0]);
        _ = std.posix.system.close(sigwinch_pipe[1]);
    }
    input.sigwinch_pipe_write_fd = sigwinch_pipe[1];

    var sa = std.posix.Sigaction{
        .handler = .{ .handler = input.handleSigwinch },
        .mask = std.mem.zeroes(std.posix.sigset_t),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.WINCH, &sa, null);
    sa.handler = .{ .handler = handleQuitSignal };
    std.posix.sigaction(std.posix.SIG.TERM, &sa, null);
    std.posix.sigaction(std.posix.SIG.HUP, &sa, null);

    var term = try Terminal.init(capabilities);
    defer term.deinit();
    global_term = &term;

    const size = usableSize(term.getSize() catch .{ 0, 0 });
    var renderer = try Renderer.init(alloc, size[0], size[1], term.writer());
    renderer.true_color = capabilities.true_color;
    defer renderer.deinit(alloc);

    var is_resuming = false;
    app_loop: while (true) {
        var nvim = try spawnNvim(init.io, &nvim_environ);
        defer nvim.deinit(init.io);
        var rpc = RpcClient.init(nvim, alloc, init.io);
        defer rpc.deinit();
        var ui_state = UiState.init(alloc);
        defer ui_state.deinit();

        var nvim_term = try spawnNvim(init.io, &nvim_environ);
        defer nvim_term.deinit(init.io);
        var rpc_term = RpcClient.init(nvim_term, alloc, init.io);
        defer rpc_term.deinit();
        var ui_term = UiState.init(alloc);
        defer ui_term.deinit();

        if (is_resuming) {
            const src_cmd_str = try std.fmt.allocPrint(alloc, "silent! source {s}", .{session_path});
            defer alloc.free(src_cmd_str);
            var src_cmd = [_]Value{.{ .string = src_cmd_str }};
            rpc.notify("nvim_command", &src_cmd) catch |err| {
                std.log.err("Failed to restore session: {}", .{err});
            };
            // Optional: wait a moment for the session to load
        }

        runNvimSession(if (is_resuming) &.{} else files.items, init, alloc, app_data_dir, &term, &renderer, &rpc, &ui_state, &rpc_term, &ui_term, sigwinch_pipe[0], session_path, handoff_path) catch |err| {
            if (err == error.EndOfStream) continue :app_loop;
            if (err == error.QuitApplication) break :app_loop;
            if (err == error.ReloadApplication) {
                renderer.forceFullRedraw();
                is_resuming = true;
                continue :app_loop;
            }
            if (err == error.ZenModeHandoff) {
                term.deinit();
                // Launch nvim with --clean + our handoff init (same plugins as tuim)
                // and restore the saved session
                const cmd_arg = try std.fmt.allocPrint(alloc, "luafile {s}", .{handoff_path});
                defer alloc.free(cmd_arg);
                const argv = [_][]const u8{
                    "nvim",
                    "--clean",
                    "--cmd",
                    cmd_arg,
                    "-S",
                    session_path,
                };
                if (std.process.spawn(init.io, .{ .argv = &argv, .environ_map = &nvim_environ, .stdin = .inherit, .stdout = .inherit, .stderr = .inherit })) |c| {
                    var child = c;
                    _ = child.wait(init.io) catch |wait_err| {
                        std.log.err("Failed to wait for zen mode nvim process: {}", .{wait_err});
                    };
                } else |spawn_err| {
                    std.log.err("Failed to spawn zen mode nvim: {}", .{spawn_err});
                }

                term = try Terminal.init(capabilities);
                renderer.writer = term.writer();
                renderer.forceFullRedraw();
                is_resuming = true;
                continue :app_loop;
            }
            return err;
        };
    }
}

test "command line arguments are classified" {
    try std.testing.expectEqual(ArgKind.version, classifyArg("--version"));
    try std.testing.expectEqual(ArgKind.version, classifyArg("-V"));
    try std.testing.expectEqual(ArgKind.help, classifyArg("--help"));
    try std.testing.expectEqual(ArgKind.help, classifyArg("-h"));
    try std.testing.expectEqual(ArgKind.diagnostics, classifyArg("--diagnostics"));
    try std.testing.expectEqual(ArgKind.end_of_options, classifyArg("--"));
    try std.testing.expectEqual(ArgKind.unknown_option, classifyArg("--bogus"));
    try std.testing.expectEqual(ArgKind.file, classifyArg("-"));
    try std.testing.expectEqual(ArgKind.file, classifyArg("a.txt"));
}

test "zero terminal size falls back to 80x24" {
    try std.testing.expectEqual([2]u16{ 80, 24 }, usableSize(.{ 0, 0 }));
    try std.testing.expectEqual([2]u16{ 80, 24 }, usableSize(.{ 120, 0 }));
    try std.testing.expectEqual([2]u16{ 100, 30 }, usableSize(.{ 100, 30 }));
}

fn runNvimSession(
    files: []const []const u8,
    init: std.process.Init,
    alloc: std.mem.Allocator,
    app_data_dir: []const u8,
    term: *Terminal,
    ren: *Renderer,
    rpc: *RpcClient,
    ui_state: *UiState,
    rpc_term: *RpcClient,
    ui_term: *UiState,
    sigwinch_read_fd: std.posix.fd_t,
    session_path: []const u8,
    handoff_path: []const u8,
) !void {
    const capabilities = Capabilities.detect(init.environ_map);
    var app = App.init(alloc, term, ren, rpc, rpc_term, ui_state, ui_term);
    defer {
        for (app.tabs.items) |t| {
            alloc.free(t.name);
            if (t.path) |p| alloc.free(p);
        }
        app.tabs.deinit();
        app.deinit();
    }

    var rpc_ctx_main = RpcContext{ .app = &app, .ui_state = ui_state };
    var rpc_ctx_term = RpcContext{ .app = &app, .ui_state = ui_term };

    rpc.on_notification = nvim_helpers.handleNotification;
    rpc.on_notification_ctx = &rpc_ctx_main;

    rpc_term.on_notification = nvim_helpers.handleNotification;
    rpc_term.on_notification_ctx = &rpc_ctx_term;

    var explorer = Explorer.init(alloc, init.io);
    defer explorer.deinit();
    explorer.refresh() catch |err| {
        std.log.err("Explorer initial refresh failed: {}", .{err});
    };
    app.explorer = &explorer;

    var git_panel = GitPanel.init(alloc, init.io);
    defer git_panel.deinit();
    app.git_panel = &git_panel;
    var git_owners = task_runner.OwnerRegistry{};
    var git_owner: ?task_runner.OwnerId = null;
    var background: ?*task_runner.Runner = null;
    defer {
        if (background) |runner| {
            if (git_owner) |owner| {
                runner.cancelOwner(owner);
                _ = git_owners.close(owner);
            }
            runner.deinit();
        }
    }
    if (git_snapshot.compatibility.periodic_synchronous_refresh) {
        git_panel.refresh() catch |err| std.log.warn("Initial Git refresh failed: {}", .{err});
    } else {
        git_owner = try git_owners.create();
        background = try task_runner.Runner.init(alloc, .{});
        submitGitRefresh(alloc, background.?, &git_owners, git_owner.?, false) catch |err| std.log.warn("Initial Git refresh admission failed: {}", .{err});
    }

    var search_panel = SearchPanel.init(alloc);
    defer search_panel.deinit();
    app.search_panel = &search_panel;

    var extension_shop = ExtensionShop.init(alloc, init.io, app_data_dir);
    defer extension_shop.deinit();
    app.extension_shop = &extension_shop;

    var ai_panel = @import("tui/widgets/ai_panel.zig").AiPanel.init(alloc, init.io, init.environ_map);
    defer ai_panel.deinit();
    app.ai_panel = &ai_panel;

    var output_panel = OutputPanel.init(alloc);
    defer output_panel.deinit();
    app.output_panel = &output_panel;

    var debug_console = DebugConsole.init(alloc);
    defer debug_console.deinit();
    app.debug_console = &debug_console;

    const report_endpoint = init.environ_map.get("TUIM_BUG_REPORT_ENDPOINT") orelse build_options.bug_report_endpoint;
    var bug_report = try BugReportWidget.init(alloc, init.io, app_data_dir, init.environ_map.get("HOME") orelse "", report_endpoint, build_options.version, init.environ_map);
    defer bug_report.deinit();
    app.bug_report = &bug_report;

    const settings_path = try std.fs.path.join(alloc, &[_][]const u8{ app_data_dir, "settings.json" });
    const preview_path = try std.fs.path.join(alloc, &[_][]const u8{ app_data_dir, "preview.json" });
    defer alloc.free(settings_path);
    defer alloc.free(preview_path);
    var settings_io_timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.blocking_io_settings);
    var settings_widget = SettingsWidget.init(alloc, settings_path, init.io, app_data_dir);
    settings_io_timer.stop();
    const term_env = init.environ_map.get("TERM") orelse "";
    const is_linux_console = std.mem.eql(u8, term_env, "linux");
    if (is_linux_console) {
        settings_widget.config.nerd_fonts = false;
    }
    settings_widget.refreshThemes(rpc);
    defer settings_widget.deinit();
    app.settings_widget = &settings_widget;
    if (settings_widget.load_failed) {
        app.notify(.warning, "Settings could not be parsed; safe defaults were loaded.", .{});
        std.log.err("Unable to parse settings at {s}; using defaults", .{settings_path});
    }
    if (!capabilities.true_color) {
        app.notify(.warning, "True color was not detected; using the terminal 256-color palette.", .{});
        std.log.warn("Terminal capability fallback: indexed colors", .{});
    }
    if (!capabilities.mouse) {
        app.notify(.warning, "Mouse reporting is unavailable; all controls remain keyboard accessible.", .{});
        std.log.warn("Terminal capability fallback: mouse disabled", .{});
    }
    if (!capabilities.distinct_modifiers) {
        std.log.warn("Terminal may not distinguish all modified key sequences", .{});
    }

    if (std.mem.eql(u8, settings_widget.config.mode, "zen")) {
        app.mode = .zen;
    } else if (std.mem.eql(u8, settings_widget.config.mode, "ide")) {
        app.mode = .ide;
    } else {
        app.mode = .normal;
    }
    app.prev_mode = if (app.mode == .zen) .normal else app.mode;
    if (init.environ_map.get("TUIM_START_VIEW")) |view| {
        const index: ?usize = if (std.mem.eql(u8, view, "explorer")) 0 else if (std.mem.eql(u8, view, "search")) 1 else if (std.mem.eql(u8, view, "git")) 2 else if (std.mem.eql(u8, view, "ai")) 3 else if (std.mem.eql(u8, view, "extensions")) 4 else null;
        if (index) |active| {
            app.activity_bar.active_idx = active;
            app.show_file_tree = true;
            app.sidebar_focus = true;
            if (active == 4) app.extension_shop.open() catch |err| {
                std.log.err("Unable to populate startup Extension view: {}", .{err});
            };
        }
    }

    var mason_widget = MasonWidget.init(alloc);
    defer mason_widget.deinit();
    app.mason_widget = &mason_widget;
    var lazy_widget = LazyWidget.init(alloc);
    defer lazy_widget.deinit();
    app.lazy_widget = &lazy_widget;
    var git_detailed_widget = GitDetailedWidget.init(alloc, init.io);
    defer git_detailed_widget.deinit();
    app.git_detailed_widget = &git_detailed_widget;

    const initial_layout = app.layout(ren.width, ren.height);

    var opt_kvs = try alloc.alloc(Value.KV, 4);
    defer alloc.free(opt_kvs);
    opt_kvs[0] = .{ .key = .{ .string = "rgb" }, .value = .{ .bool = capabilities.true_color } };
    opt_kvs[1] = .{ .key = .{ .string = "ext_linegrid" }, .value = .{ .bool = true } };
    opt_kvs[2] = .{ .key = .{ .string = "ext_multigrid" }, .value = .{ .bool = true } };
    opt_kvs[3] = .{ .key = .{ .string = "ext_hlstate" }, .value = .{ .bool = true } };

    var attach_params = try alloc.alloc(Value, 3);
    defer alloc.free(attach_params);
    attach_params[0] = .{ .integer = initial_layout.editor.w };
    attach_params[1] = .{ .integer = initial_layout.editor.h };
    attach_params[2] = .{ .map = opt_kvs };

    std.log.info("Attaching editor Neovim UI ({d}x{d})", .{ initial_layout.editor.w, initial_layout.editor.h });
    const attach_result = try rpc.call("nvim_ui_attach", attach_params);
    msgpack.freeValue(attach_result, alloc);
    std.log.info("Editor Neovim UI attached", .{});

    var term_opt_kvs = try alloc.alloc(Value.KV, 3);
    defer alloc.free(term_opt_kvs);
    term_opt_kvs[0] = .{ .key = .{ .string = "rgb" }, .value = .{ .bool = capabilities.true_color } };
    term_opt_kvs[1] = .{ .key = .{ .string = "ext_linegrid" }, .value = .{ .bool = true } };
    term_opt_kvs[2] = .{ .key = .{ .string = "ext_multigrid" }, .value = .{ .bool = false } };

    var term_attach_params = try alloc.alloc(Value, 3);
    defer alloc.free(term_attach_params);
    term_attach_params[0] = .{ .integer = if (initial_layout.panel) |p| p.w else 80 };
    term_attach_params[1] = .{ .integer = if (initial_layout.panel) |p| (if (p.h > 0) @max(1, p.h - 1) else 1) else 7 };
    term_attach_params[2] = .{ .map = term_opt_kvs };
    std.log.info("Attaching terminal Neovim UI", .{});
    const term_attach_result = try rpc_term.call("nvim_ui_attach", term_attach_params);
    msgpack.freeValue(term_attach_result, alloc);
    std.log.info("Terminal Neovim UI attached", .{});

    {
        std.log.info("Configuring Neovim sessions", .{});
        var cp = try alloc.alloc(Value, 1);
        defer alloc.free(cp);

        cp[0] = .{ .string = "set laststatus=0" };
        const r1 = try rpc_term.call("nvim_command", cp);
        msgpack.freeValue(r1, alloc);

        // Tuim owns the one workspace status row in every presentation mode.
        cp[0] = .{ .string = "set laststatus=0" };
        const r_ls = try rpc.call("nvim_command", cp);
        msgpack.freeValue(r_ls, alloc);

        cp[0] = .{ .string = "autocmd BufWritePost * let b:tuim_session_saved = 1" };
        const r_au2 = try rpc.call("nvim_command", cp);
        msgpack.freeValue(r_au2, alloc);
    }

    var seq_buf: [4096]u8 = undefined;

    {
        var params = [_]Value{
            .{ .string = "local v=vim.version(); return string.format('%d.%d.%d', v.major, v.minor, v.patch)" },
            .{ .array = &[_]Value{} },
        };
        if (rpc.call("nvim_exec_lua", &params)) |res| {
            if (res == .string) {
                const len = @min(res.string.len, app.settings_widget.nvim_version.len);
                @memcpy(app.settings_widget.nvim_version[0..len], res.string[0..len]);
                app.settings_widget.nvim_version_len = len;
            }
            msgpack.freeValue(res, alloc);
        } else |err| {
            std.log.warn("Unable to query Neovim version: {}", .{err});
        }
    }
    // Query setup-only information before loading runtimes that can emit
    // asynchronous notifications on the same RPC channel.
    {
        std.log.info("Loading embedded editor runtime", .{});
        var params = try alloc.alloc(Value, 2);
        params[0] = .{ .string = @embedFile("nvim/tuim_init.lua") };
        params[1] = .{ .array = &[_]Value{} };
        if (rpc.call("nvim_exec_lua", params)) |res| {
            msgpack.freeValue(res, alloc);
        } else |_| {}
        alloc.free(params);
        std.log.info("Embedded editor runtime loaded", .{});
    }
    {
        std.log.info("Loading minimal terminal runtime", .{});
        var params = try alloc.alloc(Value, 2);
        params[0] = .{ .string = @embedFile("nvim/terminal_init.lua") };
        params[1] = .{ .array = &[_]Value{} };
        if (rpc_term.call("nvim_exec_lua", params)) |res| {
            msgpack.freeValue(res, alloc);
        } else |_| {}
        alloc.free(params);
        std.log.info("Minimal terminal runtime loaded", .{});
    }

    if (files.len > 0) {
        nvim_helpers.openFile(rpc, alloc, files[0]) catch |err| {
            app.notify(.failure, "Unable to open {s}: {}", .{ files[0], err });
        };
        // Remaining files become listed buffers; the first stays current.
        for (files[1..]) |f| {
            var badd_args = [_]Value{.{ .string = f }};
            var badd_params = [_]Value{ .{ .string = "vim.cmd('badd ' .. vim.fn.fnameescape(select(1, ...)))" }, .{ .array = &badd_args } };
            rpc.notify("nvim_exec_lua", &badd_params) catch |err| {
                app.notify(.failure, "Unable to open {s}: {}", .{ f, err });
            };
        }
    }

    std.log.info("Entering application event loop", .{});
    var reactor = reactor_mod.Reactor{};
    _ = try reactor.add(term.tty_fd, .terminal_input, .{ .read = true });
    _ = try reactor.add(sigwinch_read_fd, .resize_signal, .{ .read = true });
    _ = try reactor.add(rpc.process.stdout.handle, .nvim_editor_read, .{ .read = true });
    _ = try reactor.add(rpc_term.process.stdout.handle, .nvim_terminal_read, .{ .read = true });
    var editor_write_token: ?reactor_mod.Token = null;
    var terminal_write_token: ?reactor_mod.Token = null;
    if (@import("nvim/rpc.zig").compatibility.async_transport_enabled) {
        rpc.enableAsyncTransport();
        rpc_term.enableAsyncTransport();
        editor_write_token = try reactor.add(rpc.process.stdin.handle, .nvim_editor_write, .{});
        terminal_write_token = try reactor.add(rpc_term.process.stdin.handle, .nvim_terminal_write, .{});
    }
    defer if (rpc.isAsyncEnabled()) rpc.shutdownAsync() catch |err| std.log.warn("Editor RPC shutdown callback failed: {}", .{err});
    defer if (rpc_term.isAsyncEnabled()) rpc_term.shutdownAsync() catch |err| std.log.warn("Terminal RPC shutdown callback failed: {}", .{err});
    var task_token: ?reactor_mod.Token = null;
    if (background) |runner| task_token = try reactor.add(runner.notifierFd(), .task_completion, .{ .read = true });
    defer {
        if (task_token) |token| _ = reactor.remove(token);
        if (editor_write_token) |token| _ = reactor.remove(token);
        if (terminal_write_token) |token| _ = reactor.remove(token);
    }
    var phases = reactor_mod.PhaseTracker{};
    defer phases.enter(.shutdown) catch @panic("invalid reactor shutdown transition");
    var tracked_cycle = false;
    var first_frame = true;
    var last_layout: ?Layout = null;
    var last_editor_dimensions: ?invalidation.Dimensions = null;
    var last_terminal_dimensions: ?invalidation.Dimensions = null;
    while (true) {
        if (quit_signal_received.load(.monotonic)) return error.QuitApplication;
        var ts: std.posix.timespec = undefined;
        _ = std.posix.system.clock_gettime(std.posix.CLOCK.MONOTONIC, &ts);
        const now = ts.sec;

        // SIGWINCH wakes the reactor immediately; checking the actual size
        // also recovers from coalesced/missed signals without requiring input.
        const physical_size = try term.getSize();
        if (physical_size[0] > 0 and physical_size[1] > 0 and
            (physical_size[0] != ren.width or physical_size[1] != ren.height))
        {
            try ren.resize(alloc, physical_size[0], physical_size[1]);
            app.invalidations.forceFull(.terminal_resize);
        }

        if (now - app.last_explorer_refresh >= 2) {
            app.last_explorer_refresh = now;
            if (app.activity_bar.active_idx == 2) {
                if (git_snapshot.compatibility.periodic_synchronous_refresh) {
                    app.git_panel.refresh() catch |err| std.log.warn("Git panel refresh failed: {}", .{err});
                    app.invalidations.damageAll();
                } else submitGitRefresh(alloc, background.?, &git_owners, git_owner.?, true) catch |err| switch (err) {
                    error.RunnerBusy => {},
                    else => std.log.warn("Git refresh admission failed: {}", .{err}),
                };
            }
        }

        if (settings_widget.pollSoftwareUpdate()) |status| {
            switch (status) {
                .success => app.notify(.info, "Tuim was updated successfully. Restart Tuim to use the new version.", .{}),
                .failure => app.notify(.failure, "Software update failed. See {s}/software-update.log", .{app_data_dir}),
                else => {},
            }
        }

        if (bug_report.poll()) app.invalidations.damageAll();

        const cols = ren.width;
        const rows = ren.height;
        var layout_timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.layout);
        const layout = app.layout(cols, rows);
        layout_timer.stop();
        if (last_layout == null or !std.meta.eql(last_layout.?, layout)) {
            app.invalidations.invalidateLayout();
            last_layout = layout;
        }

        const editor_dimensions = invalidation.Dimensions{
            .cols = @max(1, layout.editor.w),
            .rows = @max(1, layout.editor.h),
        };
        if (invalidation.dimensionsChanged(last_editor_dimensions, editor_dimensions)) {
            var rp = try alloc.alloc(Value, 2);
            defer alloc.free(rp);
            rp[0] = .{ .integer = editor_dimensions.cols };
            rp[1] = .{ .integer = editor_dimensions.rows };
            const queued = queue: {
                rpc.notify("nvim_ui_try_resize", rp) catch |err| {
                    std.log.warn("Failed to queue editor resize: {}", .{err});
                    break :queue false;
                };
                break :queue true;
            };
            if (queued) {
                last_editor_dimensions = editor_dimensions;
                if (metrics.global.enabled) metrics.global.editor_resize_requests +|= 1;
            }
        }
        if (layout.panel) |panel| {
            const terminal_dimensions = invalidation.Dimensions{
                .cols = @max(1, panel.w),
                .rows = if (panel.h > 0) @max(1, panel.h - 1) else 1,
            };
            if (invalidation.dimensionsChanged(last_terminal_dimensions, terminal_dimensions)) {
                var tp = try alloc.alloc(Value, 2);
                defer alloc.free(tp);
                tp[0] = .{ .integer = terminal_dimensions.cols };
                tp[1] = .{ .integer = terminal_dimensions.rows };
                const queued = queue: {
                    rpc_term.notify("nvim_ui_try_resize", tp) catch |err| {
                        std.log.warn("Failed to queue terminal resize: {}", .{err});
                        break :queue false;
                    };
                    break :queue true;
                };
                if (queued) {
                    last_terminal_dimensions = terminal_dimensions;
                    if (metrics.global.enabled) metrics.global.terminal_resize_requests +|= 1;
                }
            }
        }
        app.invalidations.layout = false;
        app.invalidations.physical_terminal_size = false;
        app.invalidations.editor_nvim_size = false;
        app.invalidations.terminal_nvim_size = false;

        // Bootstrap transport progress precedes the first tracked cycle. Once
        // polling starts, transport progress happens only in the reactor phase.
        if (first_frame) {
            std.log.info("Processing initial editor events", .{});
            const nvim_alive = try nvim_helpers.processNvimEvents(rpc);
            if (!nvim_alive) return error.QuitApplication;
            std.log.info("Processing initial terminal events", .{});
            _ = try nvim_helpers.processNvimEvents(rpc_term);
        }

        if (first_frame) std.log.info("Drawing first frame", .{});
        if (tracked_cycle) try phases.enter(.composition);
        var composition_timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.composition);
        const composition_damage = app.invalidations.composition;
        const cursor_damage = app.invalidations.cursor;
        const force_full_redraw = app.invalidations.forced_full_redraw != null;
        _ = app.invalidations.consumePaint();
        views.drawWorkspace(&app, layout, composition_damage, cursor_damage);
        if (force_full_redraw) ren.forceFullRedraw();

        if (!app.settings_widget.is_open and app.was_settings_open) {
            if (alloc.dupeSentinel(u8, preview_path, 0)) |p| {
                std.Io.Dir.cwd().deleteFile(init.io, p) catch {};
                alloc.free(p);
            } else |_| {}
        }
        app.was_settings_open = app.settings_widget.is_open;

        const cursor_pos = ui_state.cursorScreenPos();
        const final_cursor_x = if (app.terminal_focus and app.active_terminal_panel_idx == 0 and layout.panel != null) panel_info: {
            const panel = layout.panel.?;
            break :panel_info panel.x + ui_term.cursor_x;
        } else @as(u16, @intCast(@max(0, @as(i32, @intCast(layout.editor.x)) + cursor_pos.x)));
        const final_cursor_y = if (app.terminal_focus and app.active_terminal_panel_idx == 0 and layout.panel != null) panel_info: {
            const panel = layout.panel.?;
            break :panel_info panel.y + 1 + ui_term.cursor_y;
        } else @as(u16, @intCast(@max(0, @as(i32, @intCast(layout.editor.y)) + cursor_pos.y)));
        const cursor_region_damaged = cursor_damage or composition_damage.overlay or
            (if (app.terminal_focus and app.active_terminal_panel_idx == 0)
                composition_damage.drawer
            else
                composition_damage.editor);
        if (cursor_region_damaged) ren.drawCursor(final_cursor_x, final_cursor_y);
        composition_timer.stop();
        if (tracked_cycle) try phases.enter(.flush);
        try ren.flush();
        if (first_frame) {
            std.log.info("First frame flushed", .{});
            first_frame = false;
        }

        const buffered_rpc_work = rpc.wantsAsyncReadProgress() or rpc_term.wantsAsyncReadProgress();
        const pending_state = app.settings_widget.needs_apply or ui_state.theme_changed;
        const timeout: i32 = if (input.sigwinch_received.load(.monotonic) or buffered_rpc_work or pending_state) 0 else 1000;
        if (editor_write_token) |token| try reactor.update(token, .{ .write = rpc.wantsAsyncWrite() });
        if (terminal_write_token) |token| try reactor.update(token, .{ .write = rpc_term.wantsAsyncWrite() });
        try phases.enter(.readiness_collection);
        var poll_timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.poll_wakeup);
        const ready = reactor.collect(timeout) catch |err| {
            poll_timer.stop();
            if (err == error.BlockedBySignal) {
                try phases.enter(.transport_progress);
                try phases.enter(.normalized_event_dispatch);
                try phases.enter(.state_update);
                if (input.sigwinch_received.swap(false, .monotonic)) {
                    var ws: posix.winsize = undefined;
                    const rc = posix.system.ioctl(term.tty_fd, posix.T.IOCGWINSZ, @intFromPtr(&ws));
                    if (posix.errno(rc) == .SUCCESS and ws.col > 0 and ws.row > 0) {
                        try ren.resize(alloc, ws.col, ws.row);
                        app.invalidations.forceFull(.terminal_resize);
                    }
                }
                tracked_cycle = true;
                continue;
            }
            return err;
        };
        poll_timer.stop();

        var readiness = ReactorReadiness{};
        try ready.dispatch(&readiness, ReactorReadiness.accept);
        try phases.enter(.transport_progress);
        if (readiness.editor_transport or rpc.wantsAsyncReadProgress()) {
            const alive = nvim_helpers.processNvimEvents(rpc) catch |err| {
                if (!readiness.editor_failed) return err;
                try rpc.finishAsync(.child_failed);
                return error.QuitApplication;
            };
            if (!alive) return error.QuitApplication;
            if (readiness.editor_failed) {
                try rpc.finishAsync(.child_failed);
                return error.QuitApplication;
            }
        }
        if (readiness.terminal_transport or rpc_term.wantsAsyncReadProgress()) {
            const alive_term = nvim_helpers.processNvimEvents(rpc_term) catch |err| {
                if (!readiness.terminal_failed) return err;
                try rpc_term.finishAsync(.child_failed);
                return;
            };
            if (!alive_term) {
                if (app.quit_requested) return error.QuitApplication;
                return;
            }
            if (readiness.terminal_failed) {
                try rpc_term.finishAsync(.child_failed);
                return;
            }
        }
        if (readiness.editor_write) try rpc.progressAsyncWrite();
        if (readiness.terminal_write) try rpc_term.progressAsyncWrite();
        try rpc.progressAsyncDeadlinesNow();
        try rpc_term.progressAsyncDeadlinesNow();
        if (app.deferred_exit == .zen_handoff) return error.ZenModeHandoff;
        if (app.deferred_exit == .reload) return error.ReloadApplication;
        try phases.enter(.normalized_event_dispatch);
        if (readiness.task_completion and drainGitRefreshes(alloc, background.?, &git_owners, &git_panel)) app.invalidations.damageAll();
        var normalized_input: ?input.Event = null;
        if (readiness.terminal_input) {
            var input_timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.input_decode);
            normalized_input = try input.readEvent(term.tty_fd, &seq_buf, alloc);
            input_timer.stop();
        }
        defer if (normalized_input) |event| switch (event) {
            .paste => |paste| alloc.free(paste),
            else => {},
        };
        try phases.enter(.state_update);
        // From here, every loop continuation must enter composition next.
        tracked_cycle = true;

        // Input handlers and buffered RPC messages can queue state changes
        // without another descriptor becoming ready. Apply them while idle too.
        {
            if (readiness.resize_signal) {
                var discard: [32]u8 = undefined;
                _ = std.posix.read(sigwinch_read_fd, &discard) catch 0;
                if (input.sigwinch_received.swap(false, .monotonic)) {
                    const resized = usableSize(try term.getSize());
                    try ren.resize(alloc, resized[0], resized[1]);
                    app.invalidations.forceFull(.terminal_resize);
                }
            }

            if (ui_state.toggle_zen_requested) {
                ui_state.toggle_zen_requested = false;
                if (app.settings_widget.config.zen_handoff) {
                    // Write handoff init with same plugins + retoggle keybind
                    const zen_key = app.settings_widget.config.keybindings.toggle_zen;
                    const tuim_init_lua = @embedFile("nvim/tuim_init.lua");
                    const handoff_buf = try alloc.alloc(u8, tuim_init_lua.len + session_path.len + 512);
                    defer alloc.free(handoff_buf);
                    const handoff_script = std.fmt.bufPrint(handoff_buf, "-- tuim handoff\n{s}\nvim.schedule(function()\n" ++
                        "  local function back() vim.cmd('silent! wa') vim.cmd('mksession! {s}') vim.cmd('qa') end\n" ++
                        "  vim.keymap.set({{'n','v','i','t'}}, '{s}', back, {{silent=true}})\nend)\n", .{ tuim_init_lua, session_path, zen_key }) catch tuim_init_lua;
                    const path = handoff_path;
                    if (std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o600)) |fd| {
                        defer _ = std.posix.system.close(fd);

                        var written: usize = 0;
                        while (written < handoff_script.len) {
                            const sub = handoff_script[written..];
                            const rc = std.posix.system.write(fd, sub.ptr, sub.len);
                            switch (std.posix.errno(rc)) {
                                .SUCCESS => written += @as(usize, @intCast(rc)),
                                .INTR => continue,
                                else => break,
                            }
                        }
                    } else |_| {}

                    const save_script = try std.fmt.allocPrint(alloc, "vim.cmd('silent! wa'); vim.cmd('mksession! {s}')", .{session_path});
                    defer alloc.free(save_script);
                    var save_params = [_]Value{ .{ .string = save_script }, .{ .array = &.{} } };
                    _ = try rpc.requestAsyncWithHandler("nvim_exec_lua", &save_params, &app, zenSessionSaved);
                } else {
                    if (app.mode != .zen) {
                        app.prev_mode = app.mode;
                        app.zen_sidebar_focus = app.sidebar_focus;
                        app.zen_terminal_focus = app.terminal_focus;
                    }
                    app.sidebar_focus = false;
                    app.terminal_focus = false;
                    app.mode = .zen;
                    app.settings_widget.config.zen = true;
                    app.settings_widget.config.ide = false;
                    const new_mode = try app.settings_widget.allocator.dupe(u8, "zen");
                    app.settings_widget.allocator.free(app.settings_widget.config.mode);
                    app.settings_widget.config.mode = new_mode;

                    var cmd_p = [_]Value{.{ .string = "set laststatus=0" }};
                    _ = rpc.call("nvim_command", &cmd_p) catch {};
                    cmd_p[0] = .{ .string = "lua vim.g.tuim_zen_mode = true; vim.g.tuim_ide_mode = false; _G.tuim_disable_ide_mode(); if _G.tuim_update_dashboard_keys then _G.tuim_update_dashboard_keys() end; pcall(function() require('alpha').redraw() end)" };
                    _ = rpc.call("nvim_command", &cmd_p) catch {};
                }
            }
            if (ui_state.toggle_ide_requested) {
                ui_state.toggle_ide_requested = false;
                app.mode = .ide;
                app.prev_mode = .ide;
                app.settings_widget.config.zen = false;
                app.settings_widget.config.ide = true;
                const new_mode = try app.settings_widget.allocator.dupe(u8, "ide");
                app.settings_widget.allocator.free(app.settings_widget.config.mode);
                app.settings_widget.config.mode = new_mode;
                // Hide Neovim statusline in IDE mode
                {
                    var ls_p = try alloc.alloc(Value, 1);
                    ls_p[0] = .{ .string = "set laststatus=0" };
                    rpc.notify("nvim_command", ls_p) catch {};
                    alloc.free(ls_p);
                }
                app.invalidations.invalidateLayout();
            }
            if (ui_state.theme_changed) {
                ui_state.theme_changed = false;
                app.invalidations.forceFull(.theme_change);
            }

            if (app.settings_widget.needs_apply) {
                app.settings_widget.needs_apply = false;
                var settings_save_timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.blocking_io_settings);
                app.settings_widget.config.save(preview_path) catch |err| {
                    app.notify(.failure, "Unable to save settings preview: {}", .{err});
                    std.log.err("Unable to save settings preview at {s}: {}", .{ preview_path, err });
                };
                settings_save_timer.stop();

                app.invalidations.forceFull(.recovery);

                const previous_mode = app.mode;
                if (std.mem.eql(u8, app.settings_widget.config.mode, "zen")) {
                    app.mode = .zen;
                } else if (std.mem.eql(u8, app.settings_widget.config.mode, "ide")) {
                    app.mode = .ide;
                } else {
                    app.mode = .normal;
                }
                if (app.mode != .zen) {
                    app.prev_mode = app.mode;
                }
                if (previous_mode != .zen and app.mode == .zen) {
                    app.zen_sidebar_focus = app.sidebar_focus;
                    app.zen_terminal_focus = app.terminal_focus;
                    app.sidebar_focus = false;
                    app.terminal_focus = false;
                } else if (previous_mode == .zen and app.mode != .zen) {
                    app.sidebar_focus = app.zen_sidebar_focus and app.show_file_tree;
                    app.terminal_focus = app.zen_terminal_focus and app.show_terminal_panel;
                }

                var cmd_p = try alloc.alloc(Value, 1);

                if (app.mode == .zen) {
                    cmd_p[0] = .{ .string = "lua vim.g.tuim_zen_mode = true; vim.g.tuim_ide_mode = false; _G.tuim_disable_ide_mode(); if _G.tuim_update_dashboard_keys then _G.tuim_update_dashboard_keys() end; pcall(function() require('alpha').redraw() end)" };
                } else if (app.mode == .ide) {
                    cmd_p[0] = .{ .string = "lua vim.g.tuim_zen_mode = false; vim.g.tuim_ide_mode = true; _G.tuim_enable_ide_mode(); if _G.tuim_update_dashboard_keys then _G.tuim_update_dashboard_keys() end; pcall(function() require('alpha').redraw() end)" };
                } else {
                    cmd_p[0] = .{ .string = "lua vim.g.tuim_zen_mode = false; vim.g.tuim_ide_mode = false; _G.tuim_disable_ide_mode(); if _G.tuim_update_dashboard_keys then _G.tuim_update_dashboard_keys() end; pcall(function() require('alpha').redraw() end)" };
                }
                rpc.notify("nvim_command", cmd_p) catch {};

                var cmd_buf: [256]u8 = undefined;
                if (std.fmt.bufPrint(&cmd_buf, "lua _G.tuim_apply_colorcolumn('{s}')", .{app.settings_widget.config.colorcolumn})) |cmd_str| {
                    cmd_p[0] = .{ .string = cmd_str };
                    rpc.notify("nvim_command", cmd_p) catch {};
                } else |_| {}

                cmd_p[0] = .{ .string = "set laststatus=0" };
                rpc.notify("nvim_command", cmd_p) catch {};

                var theme_args = [_]Value{.{ .string = app.settings_widget.config.theme }};
                const theme_params = [_]Value{ .{ .string = "_G.tuim_apply_theme(...)" }, .{ .array = &theme_args } };
                rpc.notify("nvim_exec_lua", &theme_params) catch {};

                if (std.mem.eql(u8, app.settings_widget.config.line_numbers, "relative")) {
                    cmd_p[0] = .{ .string = "setglobal relativenumber number" };
                } else if (std.mem.eql(u8, app.settings_widget.config.line_numbers, "normal")) {
                    cmd_p[0] = .{ .string = "setglobal norelativenumber number" };
                } else {
                    cmd_p[0] = .{ .string = "setglobal norelativenumber nonumber" };
                }
                rpc.notify("nvim_command", cmd_p) catch {};

                if (std.fmt.bufPrint(&cmd_buf, "set shiftwidth={d} tabstop={d} {s} {s}", .{
                    app.settings_widget.config.indent_size,
                    app.settings_widget.config.indent_size,
                    if (app.settings_widget.config.use_tabs) @as([]const u8, "noexpandtab") else @as([]const u8, "expandtab"),
                    if (app.settings_widget.config.wrap) @as([]const u8, "wrap") else @as([]const u8, "nowrap"),
                })) |cmd_str| {
                    cmd_p[0] = .{ .string = cmd_str };
                    rpc.notify("nvim_command", cmd_p) catch {};
                } else |_| {}

                if (app.settings_widget.config.clip) {
                    cmd_p[0] = .{ .string = "set clipboard=unnamedplus" };
                } else {
                    cmd_p[0] = .{ .string = "set clipboard=" };
                }
                rpc.notify("nvim_command", cmd_p) catch {};

                if (std.fmt.bufPrint(&cmd_buf, "lua vim.g.tuim_autocomplete_enabled = {s}", .{if (app.settings_widget.config.autocomplete) @as([]const u8, "true") else @as([]const u8, "false")})) |cmd_str| {
                    cmd_p[0] = .{ .string = cmd_str };
                    rpc.notify("nvim_command", cmd_p) catch {};
                } else |_| {}

                if (std.fmt.bufPrint(&cmd_buf, "lua vim.g.tuim_nerd_fonts = {s}", .{if (app.settings_widget.config.nerd_fonts) @as([]const u8, "true") else @as([]const u8, "false")})) |cmd_str| {
                    cmd_p[0] = .{ .string = cmd_str };
                    rpc.notify("nvim_command", cmd_p) catch {};
                } else |_| {}

                if (app.settings_widget.config.autoindent) {
                    cmd_p[0] = .{ .string = "setglobal autoindent" };
                } else {
                    cmd_p[0] = .{ .string = "setglobal noautoindent" };
                }
                rpc.notify("nvim_command", cmd_p) catch {};

                alloc.free(cmd_p);
            }

            if (normalized_input) |event| {
                switch (event) {
                    .key => |k| {
                        _ = events.handleKey(&app, k, layout) catch |err| switch (err) {
                            error.ReloadApplication => blk: {
                                try queueSessionSave(alloc, rpc, &app, session_path, reloadSessionSaved);
                                break :blk true;
                            },
                            else => return err,
                        };
                        if (app.quit_requested) return error.QuitApplication;
                    },
                    .paste => |p| {
                        if (app.workspace.palette) {
                            @import("tui/workspace.zig").appendQuery(&app, p);
                            continue;
                        }
                        if (app.bug_report.handlePaste(p)) {
                            app.invalidations.damageAll();
                            continue;
                        }
                        var params = try alloc.alloc(Value, 3);
                        defer alloc.free(params);
                        params[0] = .{ .string = p };
                        params[1] = .{ .bool = true };
                        params[2] = .{ .integer = -1 };
                        if ((if (app.terminal_focus) rpc_term else rpc).call("nvim_paste", params) catch null) |res| {
                            msgpack.freeValue(res, alloc);
                        }
                    },
                    .mouse => |m| {
                        events.handleMouse(&app, m, layout) catch |err| switch (err) {
                            error.ReloadApplication => try queueSessionSave(alloc, rpc, &app, session_path, reloadSessionSaved),
                            else => return err,
                        };
                    },
                    .resize => |r| {
                        try ren.resize(alloc, r.cols, r.rows);
                        app.invalidations.forceFull(.terminal_resize);
                    },
                    .quit => return error.QuitApplication,
                    .none => {},
                }
            }
        }
    }
}
