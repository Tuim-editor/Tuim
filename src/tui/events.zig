const std = @import("std");
const app = @import("app.zig");
const App = app.App;
const input = @import("input.zig");
const nvim_helpers = @import("../nvim/helpers.zig");
const Value = @import("../nvim/msgpack.zig").Value;
const Completion = @import("../nvim/async_transport.zig").Completion;
const async_effects = @import("../nvim/call_sites_05c.zig");

fn terminalAdded(context: ?*anyopaque, completion: *Completion) anyerror!void {
    const application: *App = @ptrCast(@alignCast(context.?));
    _ = async_effects.applyTerminalDelta(&application.terminal_win_count, 1, completion);
}

fn terminalRemoved(context: ?*anyopaque, completion: *Completion) anyerror!void {
    const application: *App = @ptrCast(@alignCast(context.?));
    _ = async_effects.applyTerminalDelta(&application.terminal_win_count, -1, completion);
}

fn zenSessionSaved(context: ?*anyopaque, completion: *Completion) anyerror!void {
    const application: *App = @ptrCast(@alignCast(context.?));
    if (!async_effects.applyDeferredExit(&application.deferred_exit, .zen_handoff, completion)) application.notify(.failure, "Unable to save the Zen handoff session.", .{});
}
const layout_mod = @import("layout.zig");
const Layout = layout_mod.Layout;
const settings = @import("widgets/settings.zig");

fn aiCommandMovesFocus(command: []const u8) bool {
    return std.mem.indexOf(u8, command, "OpenAITerminal") != null or
        std.mem.indexOf(u8, command, "FocusAITerminal") != null or
        std.mem.indexOf(u8, command, "RestartAITerminal") != null or
        std.mem.indexOf(u8, command, "RunAIAction") != null;
}

fn editorActionCode(action: []const u8, code_buf: []u8) ?[]const u8 {
    return if (std.mem.eql(u8, action, "ai_explain_selection"))
        "_G.RunAIAction('explain_selection')"
    else if (std.mem.eql(u8, action, "ai_fix_selection"))
        "_G.RunAIAction('fix_selection')"
    else if (std.mem.eql(u8, action, "ai_add_context"))
        "_G.SendSelectionToAI()"
    else
        std.fmt.bufPrint(code_buf, "_G.tuim_ide_action('{s}')", .{action}) catch null;
}

fn executeEditorAction(a: *App, action: []const u8) void {
    var code_buf: [96]u8 = undefined;
    const code = editorActionCode(action, &code_buf) orelse {
        a.notify(.failure, "Editor action could not be prepared.", .{});
        return;
    };
    const params = [_]Value{ .{ .string = code }, .{ .array = &[_]Value{} } };
    a.rpc.notify("nvim_exec_lua", &params) catch |err| {
        a.notify(.failure, "Editor action failed: {}", .{err});
    };
}

test "editor context AI actions route to the AI bridge" {
    var buf: [96]u8 = undefined;
    try std.testing.expectEqualStrings("_G.RunAIAction('explain_selection')", editorActionCode("ai_explain_selection", &buf).?);
    try std.testing.expectEqualStrings("_G.RunAIAction('fix_selection')", editorActionCode("ai_fix_selection", &buf).?);
    try std.testing.expectEqualStrings("_G.SendSelectionToAI()", editorActionCode("ai_add_context", &buf).?);
    try std.testing.expectEqualStrings("_G.tuim_ide_action('copy')", editorActionCode("copy", &buf).?);
}

test "AI context commands keep sidebar focus" {
    try std.testing.expect(!aiCommandMovesFocus("lua _G.SendDiagnosticsToAI()"));
    try std.testing.expect(aiCommandMovesFocus("lua _G.OpenAITerminal('codex')"));
    try std.testing.expect(aiCommandMovesFocus("lua _G.RunAIAction('write_tests')"));
}

fn writeHandoffInit(path: []const u8, content: []const u8) void {
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o600) catch return;
    defer _ = std.posix.system.close(fd);

    var written: usize = 0;
    while (written < content.len) {
        const sub = content[written..];
        const rc = std.posix.system.write(fd, sub.ptr, sub.len);
        switch (std.posix.errno(rc)) {
            .SUCCESS => written += @as(usize, @intCast(rc)),
            .INTR => continue,
            else => return,
        }
    }
}

fn ensureTerminalStarted(a: *App) !void {
    const params = [_]Value{.{ .string = "lua _G.tuim_ensure_terminal()" }};
    try a.rpc_term.notify("nvim_command", &params);
}

fn startRequestedSoftwareUpdate(a: *App) void {
    if (!a.settings_widget.software_update_requested) return;
    a.settings_widget.software_update_requested = false;
    a.settings_widget.startSoftwareUpdate() catch |err| {
        a.settings_widget.software_update_status = .failure;
        a.notify(.failure, "Unable to start software update: {}", .{err});
        std.log.err("Unable to start Tuim software update: {}", .{err});
        return;
    };
    a.notify(.info, "Downloading the latest Tuim release in the background...", .{});
}

const workspace = @import("workspace.zig");

fn openSettings(a: *App, keybindings: bool) void {
    var old_cfg = a.settings_widget.config;
    if (settings.SettingsConfig.load(a.settings_widget.allocator, a.settings_widget.settings_path)) |new_cfg| {
        a.settings_widget.config = new_cfg;
        old_cfg.deinit(a.settings_widget.allocator);
    } else |_| {}
    a.settings_widget.refreshThemes(a.rpc);
    a.settings_widget.refreshPlugins();
    a.settings_widget.active_tab = if (keybindings) 4 else 0;
    a.settings_widget.hover_row = 0;
    a.settings_widget.is_open = true;
    a.invalidations.damageAll();
}

fn workspaceAction(a: *App, action: workspace.Action, layout: Layout) anyerror!void {
    a.workspace.palette = false;
    a.extension_shop.is_open = false;
    const kb = a.settings_widget.config.keybindings;
    const key: ?[]const u8 = switch (action) {
        .terminal => kb.toggle_terminal,
        .new_file => kb.new_file,
        .zen => kb.toggle_zen,
        .next_region => kb.focus_next,
        .sidebar => kb.toggle_explorer,
        else => null,
    };
    if (key) |raw| {
        // Palette actions are explicit workspace commands, even when the live
        // terminal had focus. Direct Ctrl+N still falls through to Neovim.
        if (action == .new_file) a.terminal_focus = false;
        _ = try handleKey(a, .{ .char = 0, .raw = raw }, layout);
    } else switch (action) {
        .find_file => {
            a.sidebar_focus = false;
            a.terminal_focus = false;
            workspace.command(a, "_G.tuim_close_floating_windows(); local ok = pcall(vim.cmd, 'Telescope find_files'); if not ok then vim.ui.input({prompt='Open file: ', completion='file'}, function(p) if p and p ~= '' then vim.cmd.edit(vim.fn.fnameescape(p)) end end) end");
        },
        .search_project => {
            a.sidebar_focus = false;
            a.terminal_focus = false;
            workspace.command(a, "_G.tuim_close_floating_windows(); local ok, err = pcall(vim.cmd, 'Telescope live_grep'); if not ok then _G.tuim_native_notice('error', 'Project search is unavailable: ' .. tostring(err)) end");
        },
        .explorer, .git, .ai, .extensions => {
            if (a.mode == .zen) _ = try handleKey(a, .{ .char = 0, .raw = kb.toggle_zen }, layout);
            a.workspace.overview = false;
            a.show_file_tree = true;
            a.sidebar_focus = true;
            a.terminal_focus = false;
            a.activity_bar.active_idx = switch (action) {
                .explorer => 0,
                .git => 2,
                .ai => 3,
                .extensions => 4,
                else => unreachable,
            };
            if (action == .extensions) a.extension_shop.open() catch {};
        },
        .language_tools => {
            a.mason_widget.is_open = true;
            a.mason_widget.selected_tab = .lsp;
            a.mason_widget.search_len = 0;
            a.mason_widget.is_searching = false;
            a.mason_widget.selected_idx = 0;
            a.mason_widget.scroll_offset = 0;
            a.mason_widget.refresh(a.rpc);
        },
        .settings => openSettings(a, false),
        .keys => openSettings(a, true),
        .help => {
            a.sidebar_focus = false;
            a.terminal_focus = false;
            workspace.command(a, "vim.cmd('HelpMenu')");
        },
        .save => {
            a.sidebar_focus = false;
            a.terminal_focus = false;
            workspace.command(a, "_G.tuim_save_file()");
        },
        .problems => {
            a.sidebar_focus = false;
            a.terminal_focus = false;
            workspace.command(a, "vim.diagnostic.setqflist({open=true})");
        },
        .split_right => {
            a.sidebar_focus = false;
            a.terminal_focus = false;
            workspace.command(a, "vim.cmd('vsplit')");
        },
        .terminal_right => {
            a.sidebar_focus = false;
            a.terminal_focus = false;
            workspace.command(a, "_G.OpenTerminalRight()");
        },
        .split_down => {
            a.sidebar_focus = false;
            a.terminal_focus = false;
            workspace.command(a, "vim.cmd('split')");
        },
        .close_file => {
            a.sidebar_focus = false;
            a.terminal_focus = false;
            workspace.command(a, "_G.tuim_close_buffer(vim.api.nvim_get_current_buf())");
        },
        .buffers => workspace.openBuffers(a),
        .commands => workspace.openPalette(a),
        .report => a.bug_report.open(),
        else => {},
    }
    a.invalidations.damageAll();
}

fn workspaceItem(a: *App, index: usize, layout: Layout) !void {
    if (index < a.tabs.items.len) workspace.selectBuffer(a, index) else if (index - a.tabs.items.len < workspace.overview_action_count) try workspaceAction(a, workspace.actions[index - a.tabs.items.len], layout);
}

pub fn handleKey(a: *App, k: input.KeyEvent, layout: Layout) !bool {
    if (a.terminal_focus and !a.workspace.palette and !a.settings_widget.is_open) {
        if (terminalPanelShortcut(k.raw)) |shortcut| {
            var cmd_p = try a.allocator.alloc(Value, 1);
            defer a.allocator.free(cmd_p);
            cmd_p[0] = .{ .string = switch (shortcut) {
                .vertical_split => "vnew | terminal | startinsert",
                .horizontal_split => "new | terminal | startinsert",
            } };
            _ = try a.rpc_term.requestAsyncWithHandler("nvim_command", cmd_p, a, terminalAdded);
            a.invalidations.damageAll();
            return true;
        }
        if (std.mem.eql(u8, k.raw, "\x1bc")) { // Alt+c -> Close Split
            if (a.terminal_win_count > 1) {
                var cmd_p = try a.allocator.alloc(Value, 1);
                defer a.allocator.free(cmd_p);
                cmd_p[0] = .{ .string = "close" };
                _ = try a.rpc_term.requestAsyncWithHandler("nvim_command", cmd_p, a, terminalRemoved);
            } else {
                a.show_terminal_panel = false;
                a.terminal_focus = false;
                a.terminal_win_count = 1;
                a.updateLayoutTree();
                a.invalidations.damageAll();
            }
            return true;
        }
        if (std.mem.eql(u8, k.raw, "\x1bo")) { // Alt+o -> Cycle Focus
            var cmd_p = try a.allocator.alloc(Value, 1);
            defer a.allocator.free(cmd_p);
            cmd_p[0] = .{ .string = "wincmd w" };
            var res = try a.rpc_term.call("nvim_command", cmd_p);
            @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
            cmd_p[0] = .{ .string = "startinsert" };
            res = try a.rpc_term.call("nvim_command", cmd_p);
            @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
            return true;
        }
        if (std.mem.eql(u8, k.raw, "\x1bk")) { // Alt+k -> Focus Up (to Editor)
            if (a.panel_position == .bottom) {
                a.terminal_focus = false;
                a.invalidations.damageAll();
                return true;
            }
        }
        if (std.mem.eql(u8, k.raw, "\x1bh")) { // Alt+h -> Focus Left (to Editor if on right)
            if (a.panel_position == .right) {
                a.terminal_focus = false;
                a.invalidations.damageAll();
                return true;
            } else {
                var cmd_p = try a.allocator.alloc(Value, 1);
                defer a.allocator.free(cmd_p);
                cmd_p[0] = .{ .string = "wincmd h" };
                var res = try a.rpc_term.call("nvim_command", cmd_p);
                @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                cmd_p[0] = .{ .string = "startinsert" };
                res = try a.rpc_term.call("nvim_command", cmd_p);
                @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                return true;
            }
        }
        if (std.mem.eql(u8, k.raw, "\x1bl")) { // Alt+l -> Focus Right
            if (a.panel_position != .right) {
                var cmd_p = try a.allocator.alloc(Value, 1);
                defer a.allocator.free(cmd_p);
                cmd_p[0] = .{ .string = "wincmd l" };
                var res = try a.rpc_term.call("nvim_command", cmd_p);
                @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                cmd_p[0] = .{ .string = "startinsert" };
                res = try a.rpc_term.call("nvim_command", cmd_p);
                @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                return true;
            }
        }
        if (std.mem.eql(u8, k.raw, "\x1bj")) { // Alt+j -> Focus Down
            if (a.panel_position != .bottom) {
                var cmd_p = try a.allocator.alloc(Value, 1);
                defer a.allocator.free(cmd_p);
                cmd_p[0] = .{ .string = "wincmd j" };
                var res = try a.rpc_term.call("nvim_command", cmd_p);
                @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                cmd_p[0] = .{ .string = "startinsert" };
                res = try a.rpc_term.call("nvim_command", cmd_p);
                @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                return true;
            }
        }
    }

    var alt_buf: [10]u8 = undefined;
    const nk = get_key: {
        if (k.raw.len == 1) {
            const b = k.raw[0];
            if (b == 0x0d or b == 0x0a) break :get_key "<Enter>";
            if (b == 0x1b) break :get_key "<Esc>";
            if (b == 0x7f or b == 0x08) break :get_key "<BS>";
            if (b == 0x09) break :get_key "<Tab>";
            if (b >= 1 and b <= 26) {
                const ctrl_keys = [_][]const u8{
                    "<C-a>", "<C-b>", "<C-c>", "<C-d>", "<C-e>", "<C-f>", "<C-g>", "<C-h>",
                    "<C-i>", "<C-j>", "<C-k>", "<C-l>", "<C-m>", "<C-n>", "<C-o>", "<C-p>",
                    "<C-q>", "<C-r>", "<C-s>", "<C-t>", "<C-u>", "<C-v>", "<C-w>", "<C-x>",
                    "<C-y>", "<C-z>",
                };
                const ctrl_name = ctrl_keys[b - 1];
                const is_editing_keys = (a.settings_widget.is_open and a.settings_widget.active_binding != null) or a.workspace.editing_shortcut != null;
                const kb = &a.settings_widget.config.keybindings;
                if (is_editing_keys or
                    std.mem.eql(u8, ctrl_name, "<C-c>") or
                    kb.conflict(null, ctrl_name))
                {
                    break :get_key ctrl_name;
                }
            }
            break :get_key k.raw;
        }
        if (std.mem.eql(u8, k.raw, "\x1b[A") or std.mem.eql(u8, k.raw, "\x1bOA")) break :get_key "<Up>";
        if (std.mem.eql(u8, k.raw, "\x1b[B") or std.mem.eql(u8, k.raw, "\x1bOB")) break :get_key "<Down>";
        if (std.mem.eql(u8, k.raw, "\x1b[C") or std.mem.eql(u8, k.raw, "\x1bOC")) break :get_key "<Right>";
        if (std.mem.eql(u8, k.raw, "\x1b[D") or std.mem.eql(u8, k.raw, "\x1bOD")) break :get_key "<Left>";
        if (std.mem.eql(u8, k.raw, "\x1b[H") or std.mem.eql(u8, k.raw, "\x1bOH") or std.mem.eql(u8, k.raw, "\x1b[1~") or std.mem.eql(u8, k.raw, "\x1b[7~")) break :get_key "<Home>";
        if (std.mem.eql(u8, k.raw, "\x1b[F") or std.mem.eql(u8, k.raw, "\x1bOF") or std.mem.eql(u8, k.raw, "\x1b[4~") or std.mem.eql(u8, k.raw, "\x1b[8~")) break :get_key "<End>";
        if (std.mem.eql(u8, k.raw, "\x1b[5~")) break :get_key "<PageUp>";
        if (std.mem.eql(u8, k.raw, "\x1b[6~")) break :get_key "<PageDown>";
        if (std.mem.eql(u8, k.raw, "\x1b[3~")) break :get_key "<Del>";
        if (std.mem.eql(u8, k.raw, "\x1b[23~")) break :get_key "<F11>";
        if (std.mem.eql(u8, k.raw, "\x1bOP") or std.mem.eql(u8, k.raw, "\x1b[11~")) break :get_key "<F1>";
        if (std.mem.eql(u8, k.raw, "\x1b[17~")) break :get_key "<F6>";
        if (std.mem.eql(u8, k.raw, "\x1b[17;2~")) break :get_key "<S-F6>";
        const function_sequences = [_][]const u8{ "\x1bOQ", "\x1bOR", "\x1bOS", "\x1b[15~", "\x1b[18~", "\x1b[19~", "\x1b[20~", "\x1b[21~", "\x1b[12~", "\x1b[13~", "\x1b[14~" };
        const function_names = [_][]const u8{ "<F2>", "<F3>", "<F4>", "<F5>", "<F7>", "<F8>", "<F9>", "<F10>", "<F2>", "<F3>", "<F4>" };
        for (function_sequences, function_names) |sequence, name| if (std.mem.eql(u8, k.raw, sequence)) {
            break :get_key name;
        };
        if (std.mem.eql(u8, k.raw, "\x1b[24~")) break :get_key "<F12>";
        if (std.mem.eql(u8, k.raw, "\x1b[Z")) break :get_key "<S-Tab>";
        if (std.mem.eql(u8, k.raw, "\x09")) break :get_key "<Tab>";
        if (k.raw.len == 2 and k.raw[0] == 0x1b) {
            const b = k.raw[1];
            const key_str = switch (b) {
                0x0d, 0x0a => "CR",
                0x7f, 0x08 => "BS",
                0x1b => "Esc",
                0x09 => "Tab",
                else => null,
            };
            if (key_str) |ks| {
                const alt_key = std.fmt.bufPrint(&alt_buf, "<M-{s}>", .{ks}) catch k.raw;
                break :get_key alt_key;
            } else {
                const alt_key = std.fmt.bufPrint(&alt_buf, "<M-{c}>", .{b}) catch k.raw;
                break :get_key alt_key;
            }
        }
        if (a.workspace.palette) break :get_key k.raw;
        if (std.mem.eql(u8, k.raw, "\x1b[1;3A")) { // Alt+Up
            if (a.ui_state.native_picker_chrome) break :get_key k.raw;
            if (layout.panel != null) {
                if (a.panel_position == .bottom) {
                    if (layout.total.h > 4 and a.terminal_panel_height < layout.total.h - 4) {
                        a.terminal_panel_height +|= 1;
                        a.updateLayoutTree();
                        a.invalidations.damageAll();
                    }
                }
            }
            break :get_key "";
        }
        if (std.mem.eql(u8, k.raw, "\x1b[1;3B")) { // Alt+Down
            if (a.ui_state.native_picker_chrome) break :get_key k.raw;
            if (layout.panel != null) {
                if (a.panel_position == .bottom) {
                    if (a.terminal_panel_height > 2) {
                        a.terminal_panel_height -= 1;
                        a.updateLayoutTree();
                        a.invalidations.damageAll();
                    }
                }
            }
            break :get_key "";
        }
        if (std.mem.eql(u8, k.raw, "\x1b[1;3C")) { // Alt+Right
            if (a.ui_state.native_picker_chrome) break :get_key k.raw;
            if (layout.panel != null and a.panel_position == .right) {
                if (layout.total.w > 10 and a.terminal_panel_width > 10) {
                    a.terminal_panel_width -= 1;
                    a.updateLayoutTree();
                    a.invalidations.damageAll();
                }
            } else if (a.show_file_tree) {
                if (layout.total.w > layout.activity_bar.w + 10 and a.file_tree_width < layout.total.w - layout.activity_bar.w - 10) {
                    a.file_tree_width += 1;
                    a.invalidations.damageAll();
                }
            }
            break :get_key "";
        }
        if (std.mem.eql(u8, k.raw, "\x1b[1;3D")) { // Alt+Left
            if (a.ui_state.native_picker_chrome) break :get_key k.raw;
            if (layout.panel != null and a.panel_position == .right) {
                if (layout.total.w > 10 and a.terminal_panel_width < layout.total.w - 10) {
                    a.terminal_panel_width += 1;
                    a.updateLayoutTree();
                    a.invalidations.damageAll();
                }
            } else if (a.show_file_tree) {
                if (a.file_tree_width > 5) {
                    a.file_tree_width -= 1;
                    a.invalidations.damageAll();
                }
            }
            break :get_key "";
        }
        if (std.mem.eql(u8, k.raw, "\x1bp")) { // Alt+P
            a.panel_position = if (a.panel_position == .bottom) .right else .bottom;
            a.updateLayoutTree();
            a.invalidations.damageAll();
            break :get_key "";
        }
        break :get_key k.raw;
    };

    if (nk.len > 0) {
        if (a.mode == .ide and !a.ui_state.native_picker_chrome and !a.settings_widget.is_open and !a.workspace.palette and !a.bug_report.is_open and std.mem.eql(u8, nk, "<F12>")) {
            a.bug_report.open();
            a.invalidations.damageAll();
            return true;
        }
        if (a.bug_report.is_open) {
            _ = a.bug_report.handleKey(nk);
            a.invalidations.damageAll();
            return true;
        }
        switch (a.editor_context_menu.handleKey(nk)) {
            .action => |action| {
                executeEditorAction(a, action);
                a.invalidations.damageAll();
                return true;
            },
            .handled => {
                a.invalidations.damageAll();
                return true;
            },
            .ignored => {},
        }
        if (a.settings_widget.is_open) {
            if (a.settings_widget.handleKey(nk)) {
                a.invalidations.damageAll();
                startRequestedSoftwareUpdate(a);
                if (a.settings_widget.open_mason) {
                    a.settings_widget.open_mason = false;
                    a.settings_widget.is_open = false;
                    a.mason_widget.is_open = true;
                    a.mason_widget.refresh(a.rpc);
                } else if (a.settings_widget.open_installed) {
                    a.settings_widget.open_installed = false;
                    a.settings_widget.is_open = false;
                    a.activity_bar.active_idx = 4;
                    a.workspace.overview = false;
                    a.show_file_tree = true;
                    a.sidebar_focus = true;
                    a.terminal_focus = false;
                    a.extension_shop.selected_category = .installed;
                    a.extension_shop.search_query.clearRetainingCapacity();
                    a.extension_shop.is_open = true;
                    a.extension_shop.is_detail_open = false;
                    a.extension_shop.is_searching = false;
                    try a.extension_shop.triggerSearch();
                } else if (a.settings_widget.open_lazy) {
                    a.settings_widget.open_lazy = false;
                    a.settings_widget.is_open = false;
                    a.lazy_widget.is_open = true;
                    a.lazy_widget.refresh(a.rpc);
                }
            } else if (std.mem.eql(u8, nk, "<Esc>")) {
                a.settings_widget.is_open = false;
                a.invalidations.damageAll();
            }
            if (a.settings_widget.edit_config_path) |path| {
                @import("../nvim/helpers.zig").openFile(a.rpc, a.allocator, path) catch {};
                a.settings_widget.allocator.free(path);
                a.settings_widget.edit_config_path = null;
                a.sidebar_focus = false;
                a.invalidations.damageAll();
            }
            return true;
        }
        if (a.mason_widget.is_open) {
            if (a.mason_widget.handleKey(nk, a.rpc)) {
                a.invalidations.damageAll();
            }
            return true;
        }
        if (a.lazy_widget.is_open) {
            if (a.lazy_widget.handleKey(nk, a.rpc)) {
                a.invalidations.damageAll();
            }
            return true;
        }
        if (a.git_detailed_widget.is_open) {
            if (a.git_detailed_widget.handleKey(nk)) {
                a.invalidations.damageAll();
            }
            return true;
        }
        if (a.extension_shop.is_open and !a.workspace.palette) {
            if (std.mem.eql(u8, nk, "<F1>")) {
                workspace.openPalette(a);
                return true;
            }
            if (try a.extension_shop.handlePanelKey(nk)) {
                a.invalidations.damageAll();
                if (!a.extension_shop.is_open) a.sidebar_focus = false;
                if (a.extension_shop.edit_config_path) |path| {
                    @import("../nvim/helpers.zig").openFile(a.rpc, a.allocator, path) catch {};
                    a.extension_shop.allocator.free(path);
                    a.extension_shop.edit_config_path = null;
                    a.extension_shop.is_open = false;
                    a.extension_shop.is_detail_open = false;
                    a.sidebar_focus = false;
                }
            }
            return true;
        }
    }

    var toggle_zen = false;
    var toggle_explorer = false;
    var toggle_terminal_panel = false;
    var new_file = false;
    var find_file = false;
    var quit = false;

    const kb = &a.settings_widget.config.keybindings;
    if (a.workspace.palette) {
        if (a.workspace.editing_shortcut != null) {
            workspace.recordShortcut(a, nk);
            a.invalidations.damageAll();
            return true;
        }
        var found: [workspace.actions.len]workspace.Action = undefined;
        const items = workspace.filtered(&a.workspace, &found);
        const total = workspace.resultCount(a);
        if (std.mem.eql(u8, nk, "<Esc>")) {
            if (a.workspace.buffer_picker) workspace.openPalette(a) else a.workspace.palette = false;
        } else if (std.mem.eql(u8, nk, "<Down>") or std.mem.eql(u8, nk, "<Tab>")) a.workspace.command_selected = @min(a.workspace.command_selected + 1, total -| 1) else if (std.mem.eql(u8, nk, "<Up>") or std.mem.eql(u8, nk, "<S-Tab>")) a.workspace.command_selected -|= 1 else if (std.mem.eql(u8, nk, "<F2>") and !a.workspace.buffer_picker) {
            if (items.len > 0) workspace.editShortcut(a, items[@min(a.workspace.command_selected, items.len - 1)]);
        } else if (std.mem.eql(u8, nk, "<Enter>")) {
            if (a.workspace.buffer_picker) {
                if (workspace.bufferIndex(a, @min(a.workspace.command_selected, total -| 1))) |index| {
                    a.workspace.palette = false;
                    workspace.selectBuffer(a, index);
                }
            } else if (items.len > 0) try workspaceAction(a, items[@min(a.workspace.command_selected, items.len - 1)], layout);
        } else if (std.mem.eql(u8, nk, "<BS>")) {
            a.workspace.query_len -|= 1;
            a.workspace.command_selected = 0;
            a.workspace.command_scroll = 0;
        } else if (k.raw.len > 0 and k.raw[0] >= 32 and k.raw[0] < 127) {
            workspace.appendQuery(a, k.raw);
        }
        a.invalidations.damageAll();
        return true;
    }
    if (std.mem.eql(u8, nk, kb.commands)) {
        if (a.ui_state.native_picker_chrome) workspace.command(a, "_G.tuim_picker_action('close')");
        workspace.openPalette(a);
        return true;
    }
    if (a.ui_state.native_picker_chrome and !std.mem.eql(u8, nk, kb.toggle_zen)) {
        const text = if (std.mem.eql(u8, nk, "<")) "<lt>" else nk;
        const params = [_]Value{.{ .string = text }};
        a.rpc.notify("nvim_input", &params) catch {};
        return true;
    }
    if (a.ui_state.native_picker_chrome) workspace.command(a, "_G.tuim_picker_action('close')");
    if (std.mem.eql(u8, nk, kb.focus_next) or std.mem.eql(u8, nk, "<S-F6>")) {
        const reverse = std.mem.eql(u8, nk, "<S-F6>");
        if (a.mode != .zen) {
            const region: usize = if (a.sidebar_focus) 1 else if (a.terminal_focus) 2 else 0;
            var next = region;
            for (0..3) |_| {
                next = if (reverse) (next + 2) % 3 else (next + 1) % 3;
                if (next == 0 or (next == 1 and layout.file_tree.w > 0) or (next == 2 and a.show_terminal_panel)) break;
            }
            a.sidebar_focus = next == 1;
            a.terminal_focus = next == 2;
        }
        a.invalidations.damageAll();
        return true;
    }
    if (!a.terminal_focus and std.mem.eql(u8, nk, kb.save_file)) {
        a.sidebar_focus = false;
        workspace.command(a, "_G.tuim_save_file()");
        return true;
    }
    if (std.mem.eql(u8, nk, kb.toggle_terminal) or std.mem.eql(u8, k.raw, kb.toggle_terminal)) toggle_terminal_panel = true;
    if (std.mem.eql(u8, nk, kb.toggle_explorer) or std.mem.eql(u8, k.raw, kb.toggle_explorer)) toggle_explorer = true;
    if (std.mem.eql(u8, nk, kb.toggle_zen) or std.mem.eql(u8, k.raw, kb.toggle_zen)) toggle_zen = true;
    if (std.mem.eql(u8, nk, kb.new_file) or std.mem.eql(u8, k.raw, kb.new_file)) new_file = true;
    if (std.mem.eql(u8, nk, kb.find_file) or std.mem.eql(u8, k.raw, kb.find_file)) find_file = true;
    if (std.mem.eql(u8, nk, kb.quit) or std.mem.eql(u8, k.raw, kb.quit)) quit = true;

    if (toggle_zen) {
        if (a.settings_widget.config.zen_handoff) {
            const dir_path = std.fs.path.dirname(a.settings_widget.settings_path) orelse ".";
            const session_path = try std.fs.path.join(a.allocator, &[_][]const u8{ dir_path, "tuim_session.vim" });
            defer a.allocator.free(session_path);
            const handoff_path = try std.fs.path.join(a.allocator, &[_][]const u8{ dir_path, "tuim_handoff_init.lua" });
            defer a.allocator.free(handoff_path);

            // Write handoff init: same plugins + retoggle keybind
            const zen_key = a.settings_widget.config.keybindings.toggle_zen;
            const tuim_init_lua = @embedFile("../nvim/tuim_init.lua");
            const handoff_buf = try a.allocator.alloc(u8, tuim_init_lua.len + session_path.len + 512);
            defer a.allocator.free(handoff_buf);
            const handoff_script = std.fmt.bufPrint(handoff_buf, "-- tuim handoff\n{s}\nvim.schedule(function()\n" ++
                "  local function back() vim.cmd('silent! wa') vim.cmd('mksession! {s}') vim.cmd('qa') end\n" ++
                "  vim.keymap.set({{'n','v','i','t'}}, '{s}', back, {{silent=true, desc='Return to tuim'}})\nend)\n", .{ tuim_init_lua, session_path, zen_key }) catch tuim_init_lua;

            writeHandoffInit(handoff_path, handoff_script);
            const save_script = try std.fmt.allocPrint(a.allocator, "vim.cmd('silent! wa'); vim.cmd('mksession! {s}')", .{session_path});
            defer a.allocator.free(save_script);
            var save_params = [_]Value{ .{ .string = save_script }, .{ .array = &.{} } };
            _ = try a.rpc.requestAsyncWithHandler("nvim_exec_lua", &save_params, a, zenSessionSaved);
            return true;
        } else {
            if (a.mode != .zen) {
                a.zen_sidebar_focus = a.sidebar_focus;
                a.zen_terminal_focus = a.terminal_focus;
                a.sidebar_focus = false;
                a.terminal_focus = false;
                a.prev_mode = a.mode;
                a.mode = .zen;
                a.settings_widget.config.zen = true;
                a.settings_widget.config.ide = false;
                const new_mode = try a.settings_widget.allocator.dupe(u8, "zen");
                a.settings_widget.allocator.free(a.settings_widget.config.mode);
                a.settings_widget.config.mode = new_mode;

                var cmd_p = [_]Value{.{ .string = "set laststatus=0" }};
                _ = a.rpc.call("nvim_command", &cmd_p) catch {};
                cmd_p[0] = .{ .string = "lua vim.g.tuim_zen_mode = true; vim.g.tuim_ide_mode = false; _G.tuim_disable_ide_mode(); if _G.tuim_update_dashboard_keys then _G.tuim_update_dashboard_keys() end; pcall(function() require('alpha').redraw() end)" };
                _ = a.rpc.call("nvim_command", &cmd_p) catch {};
            } else {
                a.mode = a.prev_mode;
                a.sidebar_focus = a.zen_sidebar_focus and a.show_file_tree;
                a.terminal_focus = a.zen_terminal_focus and a.show_terminal_panel;
                a.settings_widget.config.zen = false;
                a.settings_widget.config.ide = a.mode == .ide;
                const new_mode = try a.settings_widget.allocator.dupe(u8, @tagName(a.mode));
                a.settings_widget.allocator.free(a.settings_widget.config.mode);
                a.settings_widget.config.mode = new_mode;

                var cmd_p = [_]Value{.{ .string = "set laststatus=0" }};
                _ = a.rpc.call("nvim_command", &cmd_p) catch {};
                cmd_p[0] = .{ .string = if (a.mode == .ide)
                    "lua vim.g.tuim_zen_mode = false; vim.g.tuim_ide_mode = true; _G.tuim_enable_ide_mode(); if _G.tuim_update_dashboard_keys then _G.tuim_update_dashboard_keys() end; pcall(function() require('alpha').redraw() end)"
                else
                    "lua vim.g.tuim_zen_mode = false; vim.g.tuim_ide_mode = false; _G.tuim_disable_ide_mode(); if _G.tuim_update_dashboard_keys then _G.tuim_update_dashboard_keys() end; pcall(function() require('alpha').redraw() end)" };
                _ = a.rpc.call("nvim_command", &cmd_p) catch {};
            }
            a.invalidations.damageAll();
            return true;
        }
    } else if (toggle_explorer) {
        if (a.mode == .zen) _ = try handleKey(a, .{ .char = 0, .raw = kb.toggle_zen }, layout);
        a.show_file_tree = !a.show_file_tree;
        if (a.show_file_tree) {
            a.sidebar_focus = true;
            a.terminal_focus = false;
        } else {
            a.sidebar_focus = false;
        }
        a.invalidations.damageAll();
        return true;
    } else if (toggle_terminal_panel) {
        if (a.mode == .zen) _ = try handleKey(a, .{ .char = 0, .raw = kb.toggle_zen }, layout);
        a.show_terminal_panel = !a.show_terminal_panel;
        if (a.show_terminal_panel) {
            ensureTerminalStarted(a) catch |err| {
                a.show_terminal_panel = false;
                a.terminal_focus = false;
                a.notify(.failure, "Unable to start terminal: {}", .{err});
                a.updateLayoutTree();
                return true;
            };
            a.terminal_focus = true;
            a.sidebar_focus = false;
        } else {
            a.terminal_focus = false;
        }
        a.updateLayoutTree();
        a.invalidations.damageAll();
        return true;
    } else if (new_file and !a.terminal_focus) {
        a.sidebar_focus = false;
        a.terminal_focus = false;
        const cmd_p = [1]Value{.{ .string = "_G.tuim_close_floating_windows(); vim.cmd('enew')" }};
        const params = [2]Value{ cmd_p[0], .{ .array = &[_]Value{} } };
        if (a.rpc.call("nvim_exec_lua", &params) catch null) |res| {
            @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
        }
        return true;
    } else if (find_file) {
        try workspaceAction(a, .find_file, layout);
        return true;
    } else if (quit) {
        a.quit_requested = true;
        const cmd_p = [1]Value{.{ .string = "vim.cmd('qa!')" }};
        const params = [2]Value{ cmd_p[0], .{ .array = &[_]Value{} } };
        a.rpc.notify("nvim_exec_lua", &params) catch {};
        a.rpc_term.notify("nvim_exec_lua", &params) catch {};
        return true;
    }

    // Core actions above keep their established terminal and focus behavior.
    // Additional command-menu bindings use the same action as clicking a row.
    for (workspace.actions) |action| {
        switch (action) {
            .terminal, .new_file, .zen, .next_region, .sidebar, .find_file, .save, .commands => continue,
            else => {},
        }
        const binding = workspace.shortcut(a, action);
        if (binding.len > 0 and (std.mem.eql(u8, nk, binding) or std.mem.eql(u8, k.raw, binding))) {
            try workspaceAction(a, action, layout);
            return true;
        }
    }

    if (nk.len > 0) {
        if (a.mode != .zen and a.sidebar_focus and a.workspace.overview) {
            if (k.raw.len > 1 and k.raw[0] >= 32 and k.raw[0] < 127) {
                for (k.raw) |c| {
                    const raw = [_]u8{c};
                    _ = try handleKey(a, .{ .char = c, .raw = &raw }, layout);
                }
                return true;
            }
            if (std.mem.eql(u8, nk, "j") or std.mem.eql(u8, nk, "<Down>")) a.workspace.selected = @min(a.workspace.selected + 1, a.tabs.items.len + workspace.overview_action_count - 1) else if (std.mem.eql(u8, nk, "k") or std.mem.eql(u8, nk, "<Up>")) a.workspace.selected -|= 1 else if (std.mem.eql(u8, nk, "<Home>")) a.workspace.selected = 0 else if (std.mem.eql(u8, nk, "<End>")) a.workspace.selected = a.tabs.items.len + workspace.overview_action_count - 1 else if (std.mem.eql(u8, nk, "<Enter>") or std.mem.eql(u8, nk, "l")) try workspaceItem(a, a.workspace.selected, layout) else if (std.mem.eql(u8, nk, "<Esc>") or std.mem.eql(u8, nk, "<Tab>")) a.sidebar_focus = false;
            a.invalidations.damageAll();
            return true;
        }
        // The assistant chooser owns Escape before the workspace back action.
        if (a.sidebar_focus and !a.workspace.overview and a.show_file_tree and a.activity_bar.active_idx == 3 and a.ai_panel.choosing and std.mem.eql(u8, nk, "<Esc>")) {
            _ = a.ai_panel.handleKey(nk);
            a.invalidations.damageAll();
            return true;
        }
        if (a.mode != .zen and a.sidebar_focus and !a.workspace.overview and std.mem.eql(u8, nk, "<Esc>") and a.explorer.action_state == .none and !a.git_panel.is_focus_commit) {
            a.workspace.overview = true;
            a.invalidations.damageAll();
            return true;
        }
        if (a.sidebar_focus) {
            // Commit text owns Escape and printable keys before sidebar shortcuts.
            if (a.show_file_tree and a.activity_bar.active_idx == 2 and a.git_panel.is_focus_commit) {
                _ = a.git_panel.handleKey(nk, layout.file_tree.h) catch |err| {
                    a.notify(.failure, "Git action failed: {}", .{err});
                };
                a.invalidations.damageAll();
                return true;
            }
            if (std.mem.eql(u8, nk, "<Tab>") and a.activity_bar.active_idx != 3) {
                a.activity_bar.active_idx = (a.activity_bar.active_idx + 1) % 5;
                if (a.activity_bar.active_idx == 4) {
                    a.extension_shop.open() catch {};
                }
                a.invalidations.damageAll();
                return true;
            }
            if (std.mem.eql(u8, nk, "<S-Tab>") and a.activity_bar.active_idx != 3) {
                a.activity_bar.active_idx = if (a.activity_bar.active_idx == 0) 4 else a.activity_bar.active_idx - 1;
                if (a.activity_bar.active_idx == 4) {
                    a.extension_shop.open() catch {};
                }
                a.invalidations.damageAll();
                return true;
            }
            if (std.mem.eql(u8, nk, "<C-s>")) {
                var old_cfg = a.settings_widget.config;
                if (settings.SettingsConfig.load(a.settings_widget.allocator, a.settings_widget.settings_path)) |new_cfg| {
                    a.settings_widget.config = new_cfg;
                    old_cfg.deinit(a.settings_widget.allocator);
                } else |_| {}
                a.settings_widget.refreshThemes(a.rpc);
                a.settings_widget.refreshPlugins();
                a.settings_widget.is_open = true;
                a.invalidations.damageAll();
                return true;
            }
            if (std.mem.eql(u8, nk, "<Esc>") or std.mem.eql(u8, nk, "<M-l>")) {
                a.sidebar_focus = false;
                a.invalidations.damageAll();
                return true;
            }
            if (a.show_file_tree and a.activity_bar.active_idx == 0) {
                const was_dir = if (a.explorer.selected_idx) |idx| (idx < a.explorer.items.items.len and a.explorer.items.items[idx].is_dir) else false;
                const handled = a.explorer.handleKey(nk, a.rpc) catch |err| blk: {
                    a.notify(.failure, "File operation failed: {}", .{err});
                    break :blk false;
                };
                if (handled) {
                    if ((std.mem.eql(u8, nk, "<Enter>") or std.mem.eql(u8, nk, "o")) and !was_dir) {
                        a.sidebar_focus = false;
                    }
                    a.invalidations.damageAll();
                    return true;
                }
            } else if (a.show_file_tree and a.activity_bar.active_idx == 1) {
                if (a.search_panel.handleKey(nk)) |cmd| {
                    if (std.mem.startsWith(u8, cmd, "__CMD__:Telescope")) {
                        var cmd_p = try a.allocator.alloc(Value, 1);
                        defer a.allocator.free(cmd_p);
                        cmd_p[0] = .{ .string = cmd[8..] };
                        a.rpc.notify("nvim_command", cmd_p) catch {};
                        a.sidebar_focus = false;
                    }
                    a.invalidations.damageAll();
                    return true;
                } else if (std.mem.eql(u8, nk, "j") or std.mem.eql(u8, nk, "k") or std.mem.eql(u8, nk, "<Down>") or std.mem.eql(u8, nk, "<Up>")) {
                    a.invalidations.damageAll();
                    return true;
                }
            } else if (a.show_file_tree and a.activity_bar.active_idx == 2) {
                const handled = a.git_panel.handleKey(nk, layout.file_tree.h) catch |err| blk: {
                    a.notify(.failure, "Git action failed: {}", .{err});
                    std.log.err("Git panel key action failed: {}", .{err});
                    break :blk false;
                };
                if (handled and std.mem.eql(u8, nk, "<Enter>")) {
                    if (a.git_panel.selectedPath()) |path| {
                        nvim_helpers.openFile(a.rpc, a.allocator, path) catch |err| {
                            a.notify(.failure, "Unable to open file: {}", .{err});
                            return true;
                        };
                        a.sidebar_focus = false;
                        a.terminal_focus = false;
                    }
                }
                if (handled) {
                    a.invalidations.damageAll();
                    return true;
                }
                return true; // Unbound Git keys must not edit the buffer behind the panel.
            } else if (a.show_file_tree and a.activity_bar.active_idx == 3) {
                if (a.ai_panel.handleKey(nk)) |cmd| {
                    if (std.mem.startsWith(u8, cmd, "__CMD__:lua ")) {
                        var cmd_p = try a.allocator.alloc(Value, 1);
                        defer a.allocator.free(cmd_p);
                        cmd_p[0] = .{ .string = cmd[8..] };
                        a.rpc.notify("nvim_command", cmd_p) catch {};
                        if (aiCommandMovesFocus(cmd)) a.sidebar_focus = false;
                    }
                }
                a.invalidations.damageAll();
                return true; // Panel navigation must never reach the editor or chat.
            } else if (a.show_file_tree and a.activity_bar.active_idx == 4) {
                if (try a.extension_shop.handleKey(nk)) {
                    a.invalidations.damageAll();
                    return true;
                }
            }
        } else {
            if (a.show_file_tree and a.activity_bar.active_idx == 0 and a.explorer.action_state != .none) {
                if (a.explorer.handleKey(nk, a.rpc) catch false) {
                    a.invalidations.damageAll();
                    return true;
                }
            }
            if (a.show_file_tree and a.activity_bar.active_idx == 2 and a.git_panel.is_focus_commit) {
                const handled = a.git_panel.handleKey(nk, layout.file_tree.h) catch |err| blk: {
                    a.notify(.failure, "Git action failed: {}", .{err});
                    std.log.err("Git commit action failed: {}", .{err});
                    break :blk false;
                };
                if (handled) {
                    a.invalidations.damageAll();
                    return true;
                }
            }
        }

        const sent_key = if (std.mem.eql(u8, nk, "<")) @as([]const u8, "<lt>") else nk;
        var ip = try a.allocator.alloc(Value, 1);
        defer a.allocator.free(ip);
        ip[0] = .{ .string = sent_key };
        (if (a.terminal_focus) a.rpc_term else a.rpc).notify("nvim_input", ip) catch {};
    }
    return true;
}

pub fn handleMouse(a: *App, m: input.MouseEvent, layout: Layout) !void {
    const point = a.ren.pointer_position;
    if (point == null or point.?.x != m.col or point.?.y != m.row) {
        a.ren.pointer_position = .{ .x = m.col, .y = m.row };
        a.invalidations.damageAll();
    }
    // Passive motion must never activate controls or reach editor drag handling.
    if (m.action == .move and m.button == .none and !a.editor_context_menu.is_open) return;
    a.last_click_x = m.col;
    a.last_click_y = m.row;

    // A command menu owns mouse input, including clicks above live terminals.
    if (a.workspace.palette) {
        if (a.workspace.editing_shortcut != null) return;
        if (m.action == .press) {
            const rect = workspace.paletteRect(layout);
            if (m.col >= rect.x and m.col < rect.x + rect.w and m.row >= rect.y + 2 and m.row < rect.y + rect.h -| 1) {
                var found: [workspace.actions.len]workspace.Action = undefined;
                const items = workspace.filtered(&a.workspace, &found);
                if (m.button == .wheel_down) a.workspace.command_selected = @min(a.workspace.command_selected + 1, workspace.resultCount(a) -| 1) else if (m.button == .wheel_up) a.workspace.command_selected -|= 1 else if (m.button == .left) {
                    const index = a.workspace.command_scroll + m.row - rect.y - 2;
                    if (a.workspace.buffer_picker) {
                        if (workspace.bufferIndex(a, index)) |buffer| {
                            a.workspace.palette = false;
                            workspace.selectBuffer(a, buffer);
                        }
                    } else if (index < items.len) {
                        a.workspace.command_selected = index;
                        if (rect.w >= 44 and m.col >= rect.x + rect.w - 15) workspace.editShortcut(a, items[index]) else try workspaceAction(a, items[index], layout);
                    }
                }
            } else if (m.button == .left and (m.col < rect.x or m.col >= rect.x + rect.w or m.row < rect.y or m.row >= rect.y + rect.h)) a.workspace.palette = false;
            a.invalidations.damageAll();
        }
        return;
    }

    if (a.ui_state.native_picker_chrome) {
        if (m.row == layout.status_bar.y) {
            if (m.action == .press and m.button == .left) {
                if (workspace.pickerFooterAction(layout.status_bar.w, m.col)) |action| {
                    var code: [96]u8 = undefined;
                    workspace.command(a, std.fmt.bufPrint(&code, "_G.tuim_picker_action('{s}')", .{@tagName(action)}) catch return);
                }
            }
            return;
        }
        if (m.col < layout.editor.x or m.col >= layout.editor.x + layout.editor.w or m.row < layout.editor.y or m.row >= layout.editor.y + layout.editor.h) {
            if (m.action == .press and m.button == .left) workspace.command(a, "_G.tuim_picker_action('close')");
            return;
        }
        nvim_helpers.sendMouseEvent(a.rpc, a.allocator, m, m.col - layout.editor.x, m.row - layout.editor.y);
        return;
    }

    if (a.bug_report.is_open) {
        if (m.action == .press or m.button == .wheel_up or m.button == .wheel_down) {
            _ = a.bug_report.handleMouse(m, a.ren.width, a.ren.height);
            a.invalidations.damageAll();
        }
        return;
    }

    if (a.editor_context_menu.is_open) {
        if (m.action == .press and m.button == .right) {
            if (m.col >= layout.editor.x and m.col < layout.editor.x + layout.editor.w and
                m.row >= layout.editor.y and m.row < layout.editor.y + layout.editor.h)
            {
                a.editor_context_menu.open(m.col, m.row, a.ren.width, a.ren.height);
            } else {
                a.editor_context_menu.close();
            }
            a.invalidations.damageAll();
            return;
        }
        if (a.editor_context_menu.handleMouse(m)) |action| executeEditorAction(a, action);
        a.invalidations.damageAll();
        return;
    }

    // Handle split menu click if open
    if (a.show_split_menu and m.action == .press) {
        const mx = a.split_menu_x;
        const my = a.split_menu_y;
        const mw: u16 = 24;
        const mh: u16 = 6;
        if (m.col >= mx and m.col < mx + mw and m.row >= my and m.row < my + mh) {
            const row_offset = m.row - my;
            var cmd_p = try a.allocator.alloc(Value, 1);
            defer a.allocator.free(cmd_p);

            var run_term = false;
            var is_split = false;

            // Map row click to the action
            if (row_offset == 1) { // Terminal (Right/Bottom)
                run_term = true;
                cmd_p[0] = if (a.split_menu_dir == .right)
                    .{ .string = if (a.terminal_focus) "rightb vnew | terminal" else "rightb vsplit | terminal" }
                else
                    .{ .string = if (a.terminal_focus) "belowright new | terminal" else "belowright split | terminal" };
            } else if (row_offset == 2) { // Terminal (Left/Top)
                run_term = true;
                cmd_p[0] = if (a.split_menu_dir == .right)
                    .{ .string = if (a.terminal_focus) "lefta vnew | terminal" else "lefta vsplit | terminal" }
                else
                    .{ .string = if (a.terminal_focus) "aboveleft new | terminal" else "aboveleft split | terminal" };
            } else if (row_offset == 3) { // Editor (Right/Bottom)
                cmd_p[0] = if (a.split_menu_dir == .right)
                    .{ .string = if (a.terminal_focus) "rightb vnew" else "rightb vsplit" }
                else
                    .{ .string = if (a.terminal_focus) "belowright new" else "belowright split" };
            } else if (row_offset == 4) { // Editor (Left/Top)
                cmd_p[0] = if (a.split_menu_dir == .right)
                    .{ .string = if (a.terminal_focus) "lefta vnew" else "lefta vsplit" }
                else
                    .{ .string = if (a.terminal_focus) "aboveleft new" else "aboveleft split" };
            } else {
                is_split = false;
            }

            if (row_offset >= 1 and row_offset <= 4) {
                is_split = true;
            }

            if (is_split) {
                if (a.terminal_focus) {
                    if (run_term) {
                        const base = cmd_p[0].string;
                        const combined = try std.fmt.allocPrint(a.allocator, "{s} | startinsert", .{base});
                        defer a.allocator.free(combined);
                        cmd_p[0] = .{ .string = combined };
                    }
                    _ = try a.rpc_term.requestAsyncWithHandler("nvim_command", cmd_p, a, terminalAdded);
                } else {
                    var res = try a.rpc.call("nvim_command", cmd_p);
                    @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                    if (run_term) {
                        cmd_p[0] = .{ .string = "startinsert" };
                        res = try a.rpc.call("nvim_command", cmd_p);
                        @import("../nvim/msgpack.zig").freeValue(res, a.allocator);
                    }
                }
            }
        }
        a.show_split_menu = false;
        a.invalidations.damageAll();
        return;
    }
    // Handle Telescope close click
    if (m.action == .press and !a.ui_state.native_picker_chrome) {
        for (a.ui_state.telescope_rects) |rect_opt| {
            if (rect_opt) |rect| {
                const t_x = layout.editor.x + rect.x;
                const t_y = layout.editor.y + rect.y;
                const wx = if (t_x > 0) t_x - 1 else 0;
                const wy = if (t_y > 0) t_y - 1 else 0;
                if (m.row == wy and m.col >= wx + rect.w - 3 and m.col <= wx + rect.w + 1) {
                    var cmd_p = try a.allocator.alloc(Value, 1);
                    defer a.allocator.free(cmd_p);
                    cmd_p[0] = .{ .string = "lua for _, winid in ipairs(vim.api.nvim_list_wins()) do local ok, bufnr = pcall(vim.api.nvim_win_get_buf, winid); if ok then if vim.bo[bufnr].filetype == 'TelescopePrompt' then pcall(require('telescope.actions').close, bufnr) elseif vim.bo[bufnr].filetype == 'vimbindings' then pcall(vim.api.nvim_win_close, winid, true) end end end" };
                    a.rpc.notify("nvim_command", cmd_p) catch {};
                    a.ui_state.telescope_rects[0] = null;
                    a.ui_state.telescope_rects[1] = null;
                    a.invalidations.damageAll();
                    return;
                }
            }
        }
    }

    // Handle split window close button click
    if (m.action == .press) {
        if (a.terminal_focus) {
            if (layout.panel != null and a.terminal_wins.items.len > 1) {
                for (a.terminal_wins.items) |win| {
                    if (win.width > 4 and win.height > 1) {
                        const bx = layout.panel.?.x + win.col + win.width - 2;
                        const by = layout.panel.?.y + 1 + win.row;
                        if (m.col >= bx - 1 and m.col <= bx + 1 and m.row == by) {
                            var params = try a.allocator.alloc(Value, 2);
                            defer a.allocator.free(params);
                            params[0] = .{ .integer = win.id };
                            params[1] = .{ .bool = true };
                            _ = try a.rpc_term.requestAsyncWithHandler("nvim_win_close", params, a, terminalRemoved);
                            return;
                        }
                    }
                }
            }
        }
    }

    if (a.explorer.show_menu and m.action == .press) {
        if (try a.explorer.handleMenuClick(m.col, m.row)) {
            a.invalidations.damageAll();
            return;
        }
        a.explorer.show_menu = false;
        a.invalidations.damageAll();
    }

    if (a.mason_widget.is_open) {
        if (a.mason_widget.handleMouse(m, a.ren.width, a.ren.height, a.rpc)) {
            a.invalidations.damageAll();
            return;
        } else if (m.action == .press) {
            a.mason_widget.is_open = false;
            a.invalidations.damageAll();
            return;
        }
    }
    if (a.lazy_widget.is_open) {
        if (a.lazy_widget.handleMouse(m, a.ren.width, a.ren.height)) {
            a.invalidations.damageAll();
            return;
        } else if (m.action == .press) {
            a.lazy_widget.is_open = false;
            a.invalidations.damageAll();
        }
    }
    if (a.git_detailed_widget.is_open) {
        if (a.git_detailed_widget.handleMouse(m, a.ren.width, a.ren.height)) {
            a.invalidations.damageAll();
            return;
        } else if (m.action == .press) {
            a.git_detailed_widget.is_open = false;
            a.invalidations.damageAll();
        }
    }
    if (a.extension_shop.is_open) {
        if (m.action == .press or m.button == .wheel_up or m.button == .wheel_down) {
            if (try a.extension_shop.handlePanelMouse(m)) {
                a.invalidations.damageAll();
                if (!a.extension_shop.is_open) a.sidebar_focus = false;
                if (a.extension_shop.edit_config_path) |path| {
                    @import("../nvim/helpers.zig").openFile(a.rpc, a.allocator, path) catch {};
                    a.extension_shop.allocator.free(path);
                    a.extension_shop.edit_config_path = null;
                    a.extension_shop.is_open = false;
                    a.extension_shop.is_detail_open = false;
                    a.sidebar_focus = false;
                }
            } else if (m.action == .press) {
                a.extension_shop.is_open = false;
                a.sidebar_focus = false;
                a.invalidations.damageAll();
            }
        }
        return;
    }

    if (a.settings_widget.is_open) {
        if (m.action == .press) {
            if (a.settings_widget.handleMouse(m, a.ren.width, a.ren.height)) {
                a.invalidations.damageAll();
                startRequestedSoftwareUpdate(a);
                if (a.settings_widget.save_failed) {
                    a.settings_widget.save_failed = false;
                    a.notify(.failure, "Settings could not be saved; check path permissions and the Tuim log.", .{});
                    std.log.err("Unable to save settings at {s}", .{a.settings_widget.settings_path});
                }
                if (a.settings_widget.open_mason) {
                    a.settings_widget.open_mason = false;
                    a.settings_widget.is_open = false;
                    a.mason_widget.is_open = true;
                    a.mason_widget.refresh(a.rpc);
                } else if (a.settings_widget.open_installed) {
                    a.settings_widget.open_installed = false;
                    a.settings_widget.is_open = false;
                    a.activity_bar.active_idx = 4;
                    a.workspace.overview = false;
                    a.show_file_tree = true;
                    a.sidebar_focus = true;
                    a.terminal_focus = false;
                    a.extension_shop.selected_category = .installed;
                    a.extension_shop.search_query.clearRetainingCapacity();
                    a.extension_shop.is_open = true;
                    a.extension_shop.is_detail_open = false;
                    a.extension_shop.is_searching = false;
                    try a.extension_shop.triggerSearch();
                } else if (a.settings_widget.open_lazy) {
                    a.settings_widget.open_lazy = false;
                    a.settings_widget.is_open = false;
                    a.lazy_widget.is_open = true;
                    a.lazy_widget.refresh(a.rpc);
                }
                if (a.settings_widget.edit_config_path) |path| {
                    @import("../nvim/helpers.zig").openFile(a.rpc, a.allocator, path) catch {};
                    a.settings_widget.allocator.free(path);
                    a.settings_widget.edit_config_path = null;
                    a.sidebar_focus = false;
                    a.invalidations.damageAll();
                }
            } else {
                a.settings_widget.is_open = false;
                a.invalidations.damageAll();
            }
        }
        return;
    }

    if (m.action == .press and m.button == .left and m.row == layout.status_bar.y and layout.status_bar.w >= 50 and m.col >= layout.status_bar.w - 36 and m.col < layout.status_bar.w - 18) {
        workspace.openPalette(a);
        return;
    }
    if (m.action == .press and m.button == .left and m.row == layout.status_bar.y and layout.status_bar.w >= 16 and m.col >= layout.status_bar.w - 16) {
        try workspaceAction(a, .zen, layout);
        return;
    }
    if (a.mode != .zen and m.action == .press) {
        if (m.row == layout.tab_bar.y and m.button == .left) {
            workspace.openPalette(a);
            return;
        }
        if (layout.file_tree.w > 0 and m.col < layout.file_tree.w -| 2) {
            if (m.row == 1 and m.button == .left) {
                a.workspace.overview = true;
                a.sidebar_focus = true;
                a.terminal_focus = false;
                a.invalidations.damageAll();
                return;
            }
            if (a.workspace.overview and m.row >= layout.file_tree.y and m.row < layout.file_tree.y + layout.file_tree.h) {
                a.sidebar_focus = true;
                a.terminal_focus = false;
                if (m.button == .wheel_down) a.workspace.selected = @min(a.workspace.selected + 1, a.tabs.items.len + workspace.overview_action_count - 1) else if (m.button == .wheel_up) a.workspace.selected -|= 1 else if (m.button == .left) {
                    const row = m.row - layout.file_tree.y + a.workspace.scroll;
                    for (0..a.tabs.items.len + workspace.overview_action_count) |i| if (workspace.itemRow(i, a.tabs.items.len) == row) {
                        a.workspace.selected = i;
                        try workspaceItem(a, i, layout);
                        break;
                    };
                }
                a.invalidations.damageAll();
                return;
            }
        }
    }

    if (m.button == .left and m.action == .press and layout.status_bar.h > 0 and
        m.row == layout.status_bar.y and m.col < layout.status_bar.x + @min(layout.status_bar.w, 12))
    {
        var old_cfg = a.settings_widget.config;
        if (settings.SettingsConfig.load(a.settings_widget.allocator, a.settings_widget.settings_path)) |new_cfg| {
            a.settings_widget.config = new_cfg;
            old_cfg.deinit(a.settings_widget.allocator);
        } else |_| {}
        a.settings_widget.refreshThemes(a.rpc);
        a.settings_widget.refreshPlugins();
        a.settings_widget.active_tab = 0;
        a.settings_widget.active_dropdown = .mode;
        a.settings_widget.hover_dropdown_idx = if (a.mode == .zen) 2 else if (a.mode == .ide) 1 else 0;
        a.settings_widget.dropdown_scroll_offset = 0;
        a.settings_widget.is_open = true;
        a.invalidations.damageAll();
        return;
    }

    if (a.mode != .zen) {
        if (m.action == .press) {
            if (a.show_file_tree and m.col >= layout.file_tree.x and m.col < layout.file_tree.x + layout.file_tree.w and a.activity_bar.active_idx == 0 and m.button == .wheel_up) {
                a.explorer.handleScroll(-1);
                a.invalidations.damageAll();
            } else if (a.show_file_tree and m.col >= layout.file_tree.x and m.col < layout.file_tree.x + layout.file_tree.w and a.activity_bar.active_idx == 0 and m.button == .wheel_down) {
                a.explorer.handleScroll(1);
                a.invalidations.damageAll();
            } else if (a.show_file_tree and m.col >= layout.file_tree.x and m.col < layout.file_tree.x + layout.file_tree.w and a.activity_bar.active_idx == 2 and m.button == .wheel_up) {
                a.git_panel.handleScroll(-1);
                a.invalidations.damageAll();
            } else if (a.show_file_tree and m.col >= layout.file_tree.x and m.col < layout.file_tree.x + layout.file_tree.w and a.activity_bar.active_idx == 2 and m.button == .wheel_down) {
                a.git_panel.handleScroll(1);
                a.invalidations.damageAll();
            } else if (a.show_file_tree and m.col >= layout.file_tree.x and m.col < layout.file_tree.x + layout.file_tree.w and a.activity_bar.active_idx == 4 and m.button == .wheel_up) {
                if (a.extension_shop.selected_idx > 0) {
                    a.extension_shop.selected_idx -= 1;
                    if (a.extension_shop.selected_idx < a.extension_shop.scroll_offset) {
                        a.extension_shop.scroll_offset = a.extension_shop.selected_idx;
                    }
                    a.invalidations.damageAll();
                }
            } else if (a.show_file_tree and m.col >= layout.file_tree.x and m.col < layout.file_tree.x + layout.file_tree.w and a.activity_bar.active_idx == 4 and m.button == .wheel_down) {
                if (a.extension_shop.plugins.items.len > 0 and a.extension_shop.selected_idx + 1 < a.extension_shop.plugins.items.len) {
                    a.extension_shop.selected_idx += 1;
                    if (a.extension_shop.selected_idx >= a.extension_shop.scroll_offset + 5) {
                        a.extension_shop.scroll_offset = a.extension_shop.selected_idx - 4;
                    }
                    a.invalidations.damageAll();
                }
            } else if (a.show_file_tree and m.button == .left and
                m.row >= layout.file_tree.y and m.row < layout.file_tree.y + layout.file_tree.h and
                m.col >= layout.file_tree.x + (layout.file_tree.w -| 2) and m.col <= layout.file_tree.x + layout.file_tree.w)
            {
                a.is_resizing_sidebar = true;
            } else if (a.show_file_tree and m.col >= layout.file_tree.x and m.col < layout.file_tree.x + layout.file_tree.w and m.row >= layout.file_tree.y and m.row < layout.file_tree.y + layout.file_tree.h) {
                a.sidebar_focus = true;
                if (a.activity_bar.active_idx == 0) {
                    if (m.button == .right) {
                        a.explorer.show_menu = true;

                        const rel_y = m.row - layout.file_tree.y;
                        var is_dir = false;
                        if (rel_y > 0) {
                            const item_idx = rel_y - 1 + a.explorer.scroll_y;
                            if (item_idx < a.explorer.items.items.len) {
                                a.explorer.selected_idx = item_idx;
                                is_dir = a.explorer.items.items[item_idx].is_dir;
                            } else {
                                a.explorer.selected_idx = null;
                            }
                        } else {
                            a.explorer.selected_idx = null;
                        }

                        const menu_h: u16 = if (a.explorer.selected_idx != null)
                            (if (is_dir) @as(u16, 5) else @as(u16, 3))
                        else
                            @as(u16, 3);

                        a.explorer.menu_x = m.col;
                        var my = m.row;
                        if (layout.file_tree.h > 0 and my + menu_h >= layout.file_tree.y + layout.file_tree.h) {
                            const limit = layout.file_tree.y + layout.file_tree.h;
                            if (limit > menu_h + 1) {
                                my = limit - menu_h - 1;
                            } else {
                                my = layout.file_tree.y;
                            }
                        }
                        a.explorer.menu_y = my;

                        a.invalidations.damageAll();
                    } else if (m.button == .left) {
                        const selected_path = a.explorer.handleMouse(m.col, m.row, layout.file_tree) catch |err| blk: {
                            a.notify(.failure, "Explorer action failed: {}", .{err});
                            break :blk null;
                        };
                        if (selected_path) |path| {
                            nvim_helpers.openFile(a.rpc, a.allocator, path) catch |err| {
                                a.notify(.failure, "Unable to open file: {}", .{err});
                            };
                            a.sidebar_focus = false;
                        }
                    }
                    a.invalidations.damageAll();
                } else if (a.activity_bar.active_idx == 1) {
                    if (a.search_panel.handleMouse(m.col, m.row, layout.file_tree)) |cmd| {
                        if (std.mem.startsWith(u8, cmd, "__CMD__:Telescope")) {
                            const actual_cmd = cmd[8..];
                            var cmd_p = try a.allocator.alloc(Value, 1);
                            defer a.allocator.free(cmd_p);
                            cmd_p[0] = .{ .string = actual_cmd };
                            a.rpc.notify("nvim_command", cmd_p) catch {};
                            a.sidebar_focus = false;
                        }
                    }
                    a.invalidations.damageAll();
                } else if (a.activity_bar.active_idx == 2) {
                    const git_path = a.git_panel.handleMouse(m.col, m.row, layout.file_tree) catch |err| blk: {
                        a.notify(.failure, "Git action failed: {}", .{err});
                        std.log.err("Git panel mouse action failed: {}", .{err});
                        break :blk null;
                    };
                    if (git_path) |path| {
                        if (std.mem.startsWith(u8, path, "__CMD__:GitWidget")) {
                            a.git_detailed_widget.is_open = true;
                            a.git_detailed_widget.refresh();
                            a.invalidations.damageAll();
                        } else {
                            nvim_helpers.openFile(a.rpc, a.allocator, path) catch |err| {
                                a.notify(.failure, "Unable to open file: {}", .{err});
                            };
                            a.sidebar_focus = false;
                        }
                    }
                    a.invalidations.damageAll();
                } else if (a.activity_bar.active_idx == 3) {
                    if (a.ai_panel.handleMouse(m, layout.file_tree)) |cmd| {
                        if (std.mem.startsWith(u8, cmd, "__CMD__:lua ")) {
                            const actual_cmd = cmd[8..];
                            var cmd_p = try a.allocator.alloc(Value, 1);
                            defer a.allocator.free(cmd_p);
                            cmd_p[0] = .{ .string = actual_cmd };
                            a.rpc.notify("nvim_command", cmd_p) catch {};
                            if (aiCommandMovesFocus(actual_cmd)) a.sidebar_focus = false;
                        }
                    }
                    a.invalidations.damageAll();
                } else if (a.activity_bar.active_idx == 4) {
                    if (try a.extension_shop.handleMouse(m.col, m.row, layout.file_tree)) {
                        a.invalidations.damageAll();
                    }
                }
            } else if (layout.panel != null and m.row == layout.panel.?.y) {
                const px = m.col - layout.panel.?.x;
                const panel_w = layout.panel.?.w;
                const terminal_clicked = if (panel_w >= 40) px >= 2 and px <= 12 else if (panel_w >= 23) px >= 1 and px <= 6 else px < panel_w / 3;
                const debug_clicked = if (panel_w >= 40) px >= 13 and px <= 28 else if (panel_w >= 23) px >= 8 and px <= 14 else px >= panel_w / 3 and px < (panel_w * 2) / 3;
                const output_clicked = if (panel_w >= 40) px >= 30 and px <= 38 else if (panel_w >= 23) px >= 17 and px <= 22 else px >= (panel_w * 2) / 3;
                if (terminal_clicked) {
                    a.active_terminal_panel_idx = 0;
                    a.terminal_focus = true;
                } else if (debug_clicked) {
                    a.active_terminal_panel_idx = 1;
                    a.terminal_focus = false;
                    a.debug_console.refresh(a.rpc);
                } else if (output_clicked) {
                    a.active_terminal_panel_idx = 2;
                    a.terminal_focus = false;
                    a.output_panel.refresh(a.rpc);
                } else {
                    a.is_resizing_panel = true;
                }
                a.invalidations.damageAll();
            } else if (layout.panel != null and a.panel_position == .bottom and layout.panel.?.y > 0 and (m.row == layout.panel.?.y - 1 or m.row == layout.panel.?.y + 1)) {
                a.is_resizing_panel = true;
            } else if (layout.panel != null and a.panel_position == .right and layout.panel.?.x > 0 and (m.col == layout.panel.?.x - 1 or m.col == layout.panel.?.x)) {
                a.is_resizing_panel = true;
            } else {
                const prev_idx = a.activity_bar.active_idx;
                if (a.activity_bar.handleMouse(m.col, m.row, layout.activity_bar)) |new_idx| {
                    if (new_idx != 99) {
                        a.sidebar_focus = true;
                    }
                    if (new_idx == 4 and prev_idx != 4) {
                        a.extension_shop.open() catch {};
                    }
                    if (prev_idx != new_idx) a.invalidations.damageAll();
                    if (new_idx == 99) {
                        var old_cfg = a.settings_widget.config;
                        if (settings.SettingsConfig.load(a.settings_widget.allocator, a.settings_widget.settings_path)) |new_cfg| {
                            a.settings_widget.config = new_cfg;
                            old_cfg.deinit(a.settings_widget.allocator);
                        } else |_| {}
                        a.settings_widget.refreshThemes(a.rpc);
                        a.settings_widget.refreshPlugins();
                        a.settings_widget.is_open = true;
                        a.invalidations.damageAll();
                        a.activity_bar.active_idx = prev_idx; // Revert active idx visually
                    } else if (a.show_file_tree and prev_idx == new_idx) {
                        a.show_file_tree = false;
                        a.invalidations.damageAll();
                    } else if (!a.show_file_tree) {
                        a.show_file_tree = true;
                        a.invalidations.damageAll();
                    }
                }
            }
        }

        if (m.action == .move) {
            if (a.is_resizing_sidebar) {
                if (m.col > layout.activity_bar.w + 5) {
                    var new_w = m.col - layout.activity_bar.w;
                    const max_w = if (layout.total.w > layout.activity_bar.w + 10) layout.total.w - layout.activity_bar.w - 10 else 0;
                    if (new_w > max_w) {
                        new_w = max_w;
                    }
                    a.file_tree_width = new_w;
                    a.invalidations.damageAll();
                }
            } else if (a.is_resizing_panel) {
                if (a.panel_position == .bottom) {
                    if (layout.total.h > 2 and m.row < layout.total.h - 2) {
                        const new_h = layout.total.h - 1 - m.row;
                        if (new_h >= 2 and new_h < layout.total.h - 2) {
                            a.terminal_panel_height = new_h;
                            a.updateLayoutTree();
                            a.invalidations.damageAll();
                        }
                    }
                } else {
                    if (layout.total.w > 10 and m.col < layout.total.w - 5) {
                        const new_w = layout.total.w - 1 - m.col;
                        if (new_w >= 10 and new_w < layout.total.w - 10) {
                            a.terminal_panel_width = new_w;
                            a.updateLayoutTree();
                            a.invalidations.damageAll();
                        }
                    }
                }
            }
        }

        const was_resizing = a.is_resizing_sidebar or a.is_resizing_panel;
        if (m.action == .release) {
            a.is_resizing_sidebar = false;
            a.is_resizing_panel = false;
            a.invalidations.damageAll();
        }
        if (was_resizing) return;
    }

    if (a.is_resizing_sidebar or a.is_resizing_panel) return;

    if (layout.panel != null and m.col >= layout.panel.?.x and m.col < layout.panel.?.x + layout.panel.?.w and
        m.row > layout.panel.?.y and m.row < layout.panel.?.y + layout.panel.?.h)
    {
        if (a.active_terminal_panel_idx == 0) {
            if (m.action == .press or m.action == .release) a.terminal_focus = true;
            dispatchTerminalMouse(TerminalMouseTarget{ .rpc = a.rpc_term, .allocator = a.allocator }, m, layout.panel.?, sendTerminalMouse);
        } else if (a.active_terminal_panel_idx == 1) {
            if (m.action == .press and m.button == .wheel_up) a.debug_console.handleScroll(-1);
            if (m.action == .press and m.button == .wheel_down) a.debug_console.handleScroll(1);
            a.invalidations.damageAll();
        } else if (a.active_terminal_panel_idx == 2) {
            if (m.action == .press and m.button == .wheel_up) a.output_panel.handleScroll(-1);
            if (m.action == .press and m.button == .wheel_down) a.output_panel.handleScroll(1);
            a.invalidations.damageAll();
        }
    } else if (m.col >= layout.editor.x and m.col < layout.editor.x + layout.editor.w and
        m.row >= layout.editor.y and m.row < layout.editor.y + layout.editor.h)
    {
        if (m.action == .press) a.terminal_focus = false;
        if (m.action == .press and m.button == .right) {
            a.show_split_menu = false;
            a.editor_context_menu.open(m.col, m.row, a.ren.width, a.ren.height);
            a.invalidations.damageAll();
            return;
        }
        nvim_helpers.sendMouseEvent(a.rpc, a.allocator, m, m.col - layout.editor.x, m.row - layout.editor.y);
    } else {
        if (m.action == .press) a.terminal_focus = false;
    }
}

const TerminalPanelShortcut = enum { vertical_split, horizontal_split };

fn terminalPanelShortcut(raw: []const u8) ?TerminalPanelShortcut {
    if (std.mem.eql(u8, raw, "\x1bv")) return .vertical_split;
    if (std.mem.eql(u8, raw, "\x1bs")) return .horizontal_split;
    if (std.mem.eql(u8, raw, "\x14")) return .vertical_split;
    return null;
}

test "terminal-normal prefix is forwarded instead of becoming a Tuim shortcut" {
    try std.testing.expectEqual(TerminalPanelShortcut.vertical_split, terminalPanelShortcut("\x1bv").?);
    try std.testing.expectEqual(TerminalPanelShortcut.horizontal_split, terminalPanelShortcut("\x1bs").?);
    try std.testing.expect(terminalPanelShortcut("\x1c") == null);
}

const TerminalMouseTarget = struct {
    rpc: *@import("../nvim/rpc.zig").RpcClient,
    allocator: std.mem.Allocator,
};

fn sendTerminalMouse(target: TerminalMouseTarget, m: input.MouseEvent, col: u16, row: u16) void {
    nvim_helpers.sendMouseEvent(target.rpc, target.allocator, m, col, row);
}

fn dispatchTerminalMouse(context: anytype, m: input.MouseEvent, panel: layout_mod.Rect, comptime send: anytype) void {
    if (m.button == .none) return;
    send(context, m, m.col - panel.x, m.row - panel.y - 1);
}

test "terminal panel dispatches press drag and release but ignores passive motion" {
    const Recorder = struct {
        events: [3]input.MouseEvent = undefined,
        cols: [3]u16 = undefined,
        rows: [3]u16 = undefined,
        count: usize = 0,

        fn record(self: *@This(), m: input.MouseEvent, col: u16, row: u16) void {
            self.events[self.count] = m;
            self.cols[self.count] = col;
            self.rows[self.count] = row;
            self.count += 1;
        }
    };
    const panel = layout_mod.Rect{ .x = 10, .y = 5, .w = 20, .h = 8 };
    var recorder = Recorder{};
    dispatchTerminalMouse(&recorder, .{ .col = 11, .row = 6, .button = .left, .action = .press }, panel, Recorder.record);
    dispatchTerminalMouse(&recorder, .{ .col = 14, .row = 7, .button = .left, .action = .move }, panel, Recorder.record);
    dispatchTerminalMouse(&recorder, .{ .col = 14, .row = 7, .button = .left, .action = .release }, panel, Recorder.record);
    dispatchTerminalMouse(&recorder, .{ .col = 15, .row = 8, .button = .none, .action = .move }, panel, Recorder.record);

    try std.testing.expectEqual(@as(usize, 3), recorder.count);
    try std.testing.expectEqual(input.MouseAction.press, recorder.events[0].action);
    try std.testing.expectEqual(input.MouseAction.move, recorder.events[1].action);
    try std.testing.expectEqual(input.MouseAction.release, recorder.events[2].action);
    try std.testing.expectEqual(@as(u16, 4), recorder.cols[2]);
    try std.testing.expectEqual(@as(u16, 1), recorder.rows[2]);
}
