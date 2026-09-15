const std = @import("std");
const build_options = @import("build_options");
const renderer = @import("../renderer.zig");
const Color = renderer.Color;
const input = @import("../input.zig");
const primitives = @import("primitives.zig");

const max_visible_themes: usize = 8;

fn isThemeHeading(theme_name: []const u8) bool {
    return std.mem.startsWith(u8, theme_name, "---");
}

fn themeLabel(name: []const u8) []const u8 {
    return if (std.mem.eql(u8, name, "system")) "System (follow desktop)" else if (std.mem.eql(u8, name, "vscode")) "VS Code Dark Modern" else name;
}

fn scrollThemeList(themes: []const []const u8, hover_idx: *usize, scroll_offset: *usize, down: bool) void {
    if (themes.len <= max_visible_themes) return;

    const max_offset = themes.len - max_visible_themes;
    scroll_offset.* = if (down)
        @min(scroll_offset.* + 1, max_offset)
    else
        scroll_offset.* -| 1;

    const visible_end = @min(themes.len, scroll_offset.* + max_visible_themes);
    if (hover_idx.* < scroll_offset.*) {
        var idx = scroll_offset.*;
        while (idx < visible_end and isThemeHeading(themes[idx])) : (idx += 1) {}
        if (idx < visible_end) hover_idx.* = idx;
    } else if (hover_idx.* >= visible_end) {
        var idx = visible_end;
        while (idx > scroll_offset.*) {
            idx -= 1;
            if (!isThemeHeading(themes[idx])) {
                hover_idx.* = idx;
                break;
            }
        }
    }
}

pub const Keybindings = struct {
    toggle_explorer: []const u8 = "<C-e>", // Ctrl-e
    toggle_terminal: []const u8 = "<C-t>", // Ctrl-t
    toggle_zen: []const u8 = "<F11>",
    new_file: []const u8 = "<C-n>", // Ctrl-n
    find_file: []const u8 = "<C-p>", // Quick Open; Ctrl-F remains Neovim's page motion.
    search_project: []const u8 = "<M-g>", // Portable terminal shortcut for project-wide grep.
    quit: []const u8 = "<C-q>", // Ctrl-q
    save_file: []const u8 = "<C-s>",
    commands: []const u8 = "<F1>",
    focus_next: []const u8 = "<F6>",
    close_buffer: []const u8 = "",
    switch_buffers: []const u8 = "",
    project_files: []const u8 = "",
    changes: []const u8 = "",
    problems: []const u8 = "",
    ai_assistants: []const u8 = "",
    extensions: []const u8 = "",
    language_tools: []const u8 = "",
    settings: []const u8 = "",
    keyboard_shortcuts: []const u8 = "",
    help: []const u8 = "",
    split_right: []const u8 = "",
    terminal_right: []const u8 = "",
    split_down: []const u8 = "",
    report_bug: []const u8 = "",

    pub const Field = std.meta.FieldEnum(Keybindings);

    pub fn get(self: Keybindings, field: Field) []const u8 {
        inline for (std.meta.fields(Keybindings)) |f| {
            if (field == @field(Field, f.name)) return @field(self, f.name);
        }
        unreachable;
    }

    pub fn ptr(self: *Keybindings, field: Field) *[]const u8 {
        inline for (std.meta.fields(Keybindings)) |f| {
            if (field == @field(Field, f.name)) return &@field(self, f.name);
        }
        unreachable;
    }

    pub fn conflict(self: Keybindings, field: ?Field, key: []const u8) bool {
        if (key.len == 0) return false;
        inline for (std.meta.fields(Keybindings)) |f| {
            if (field != @field(Field, f.name) and std.mem.eql(u8, @field(self, f.name), key)) return true;
        }
        return false;
    }

    fn clone(self: Keybindings, allocator: std.mem.Allocator) !Keybindings {
        var result = self;
        var copied: usize = 0;
        errdefer inline for (std.meta.fields(Keybindings), 0..) |f, i| {
            if (i < copied) allocator.free(@field(result, f.name));
        };
        inline for (std.meta.fields(Keybindings)) |f| {
            @field(result, f.name) = try allocator.dupe(u8, @field(self, f.name));
            copied += 1;
        }
        return result;
    }

    fn deinit(self: Keybindings, allocator: std.mem.Allocator) void {
        inline for (std.meta.fields(Keybindings)) |f| allocator.free(@field(self, f.name));
    }
};

const binding_fields = [_][]const u8{ "toggle_terminal", "toggle_explorer", "toggle_zen", "new_file", "find_file", "search_project", "quit", "save_file", "commands", "focus_next" };

pub fn formatKeyName(raw: []const u8, out: []u8) []const u8 {
    if (raw.len == 0) return "None";
    if (raw[0] == '<') return raw;
    if (raw.len == 1) {
        if (raw[0] >= 1 and raw[0] <= 26) {
            return std.fmt.bufPrint(out, "Ctrl+{c}", .{raw[0] - 1 + 'A'}) catch raw;
        } else if (raw[0] == 27) {
            return "Esc";
        }
        out[0] = raw[0];
        return out[0..1];
    }

    if (std.mem.eql(u8, raw, "\x1b[A")) return "Up";
    if (std.mem.eql(u8, raw, "\x1b[B")) return "Down";
    if (std.mem.eql(u8, raw, "\x1b[C")) return "Right";
    if (std.mem.eql(u8, raw, "\x1b[D")) return "Left";
    if (std.mem.eql(u8, raw, "\x1b[23~")) return "F11";

    if (raw.len == 2 and raw[0] == 27) {
        return std.fmt.bufPrint(out, "Alt+{c}", .{raw[1]}) catch raw;
    }
    return "Unknown";
}

pub const SettingsConfig = struct {
    // Persistence contract:
    // - v0 (unversioned) and v1 are the support window; future schemas are
    //   read-refused and therefore remain byte-for-byte available for a newer
    //   Tuim. Downgrade is an explicit export/save from that newer release.
    // - Unknown fields in a supported document are accepted for forward
    //   reading, but only future-version documents promise lossless retention.
    // - Saves are atomic, process-local last-writer-wins transactions. There is
    //   no in-place write window and no advisory lock contract.
    // - One `<path>.bak` last-known-good document is retained. Backup refresh is
    //   best effort and occurs only after the new primary validates and lands.
    // - POSIX save destinations are never followed through symlinks. Existing
    //   symlinks are rejected; a racing symlink is replaced, never followed.
    /// Settings schema supported by this binary. Unversioned files are v0 and
    /// are migrated in memory; future versions are never rewritten.
    pub const current_version: u32 = 1;
    /// Settings are intentionally small. Bounding the document at 64 KiB
    /// prevents an accidental or hostile file from consuming unbounded memory.
    pub const max_document_bytes: usize = 64 * 1024;

    version: u32 = current_version,
    clip: bool = true,
    zen: bool = false,
    zen_handoff: bool = false,
    ide: bool = false,
    autocomplete: bool = true,
    autoindent: bool = true,
    theme: []const u8 = "vscode",
    indent_size: u8 = 4,
    use_tabs: bool = false,
    wrap: bool = false,
    line_numbers: []const u8 = "relative",
    colorcolumn: []const u8 = "",
    split_separator: []const u8 = "│",
    keybindings: Keybindings = .{},
    nerd_fonts: bool = true,
    mode: []const u8 = "normal",

    const VersionHeader = struct { version: ?u32 = null };
    const SaveFailurePoint = enum { none, after_create, after_write, after_sync, before_replace, after_replace };
    var save_nonce: usize = 0;

    fn migrateV0ToV1(config: SettingsConfig) SettingsConfig {
        var migrated = config;
        if (migrated.zen) {
            migrated.mode = "zen";
            migrated.ide = false;
        } else if (migrated.ide) {
            migrated.mode = "ide";
            migrated.zen = false;
        } else if (std.mem.eql(u8, migrated.mode, "zen")) {
            migrated.zen = true;
            migrated.ide = false;
        } else if (std.mem.eql(u8, migrated.mode, "ide")) {
            migrated.zen = false;
            migrated.ide = true;
        } else {
            migrated.mode = "normal";
            migrated.zen = false;
            migrated.ide = false;
        }
        if (std.mem.eql(u8, migrated.keybindings.toggle_zen, "<C-z>"))
            migrated.keybindings.toggle_zen = "<F11>";
        migrated.version = 1;
        return migrated;
    }

    /// Pure, deterministic migrations. Reapplying this function to a current
    /// document is a no-op, which makes migrations idempotent.
    fn migrateToCurrent(config: SettingsConfig, source_version: u32) !SettingsConfig {
        if (source_version > current_version) return error.UnsupportedSettingsVersion;
        var migrated = config;
        var version = source_version;
        while (version < current_version) : (version += 1) {
            migrated = switch (version) {
                0 => migrateV0ToV1(migrated),
                else => return error.UnsupportedSettingsVersion,
            };
        }
        // These normalizations predate the schema marker and are safe to
        // reapply to early v1 writers that emitted the old values.
        if (std.mem.eql(u8, migrated.keybindings.toggle_zen, "<C-z>"))
            migrated.keybindings.toggle_zen = "<F11>";
        migrated.version = current_version;
        return migrated;
    }

    fn ownedDefaults(allocator: std.mem.Allocator) !SettingsConfig {
        return ownStrings(allocator, .{});
    }

    fn ownStrings(allocator: std.mem.Allocator, source: SettingsConfig) !SettingsConfig {
        var result = source;
        result.theme = try allocator.dupe(u8, source.theme);
        errdefer allocator.free(result.theme);
        result.line_numbers = try allocator.dupe(u8, source.line_numbers);
        errdefer allocator.free(result.line_numbers);
        result.colorcolumn = try allocator.dupe(u8, source.colorcolumn);
        errdefer allocator.free(result.colorcolumn);
        result.split_separator = try allocator.dupe(u8, source.split_separator);
        errdefer allocator.free(result.split_separator);
        result.mode = try allocator.dupe(u8, source.mode);
        errdefer allocator.free(result.mode);
        result.keybindings = try source.keybindings.clone(allocator);
        return result;
    }

    pub fn deinit(self: *SettingsConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.theme);
        allocator.free(self.line_numbers);
        allocator.free(self.colorcolumn);
        allocator.free(self.split_separator);
        allocator.free(self.mode);
        self.keybindings.deinit(allocator);
        self.* = undefined;
    }

    pub fn load(allocator: std.mem.Allocator, path: []const u8) !SettingsConfig {
        const path_z = try allocator.dupeSentinel(u8, path, 0);
        defer allocator.free(path_z);

        const fd = std.posix.openatZ(std.posix.AT.FDCWD, path_z, .{ .ACCMODE = .RDONLY, .NOFOLLOW = true }, 0) catch |err| {
            if (err == error.FileNotFound) {
                return ownedDefaults(allocator);
            }
            return err;
        };
        defer _ = std.posix.system.close(fd);

        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(allocator);
        var chunk: [4096]u8 = undefined;
        while (true) {
            const read_rc = std.posix.system.read(fd, &chunk, chunk.len);
            switch (std.posix.errno(read_rc)) {
                .SUCCESS => {},
                .INTR => continue,
                else => return error.ReadFailed,
            }
            const len: usize = @intCast(read_rc);
            if (len == 0) break;
            if (bytes.items.len + len > max_document_bytes) return error.SettingsDocumentTooLarge;
            try bytes.appendSlice(allocator, chunk[0..len]);
        }

        const header = try std.json.parseFromSlice(VersionHeader, allocator, bytes.items, .{ .ignore_unknown_fields = true });
        defer header.deinit();
        const source_version = header.value.version orelse 0;
        if (source_version > current_version) return error.UnsupportedSettingsVersion;

        const parsed = try std.json.parseFromSlice(SettingsConfig, allocator, bytes.items, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        var config = try migrateToCurrent(parsed.value, source_version);
        const valid_colorcolumn = config.colorcolumn.len == 0 or
            std.mem.eql(u8, config.colorcolumn, "80") or
            std.mem.eql(u8, config.colorcolumn, "100") or
            std.mem.eql(u8, config.colorcolumn, "120") or
            std.mem.eql(u8, config.colorcolumn, "80,120");
        if (!valid_colorcolumn) config.colorcolumn = "";
        return ownStrings(allocator, config);
    }

    pub fn save(self: *const SettingsConfig, path: []const u8) !void {
        return self.saveWithFailure(path, .none);
    }

    /// Publish the binding only after its atomic settings save succeeds.
    pub fn saveBinding(self: *SettingsConfig, allocator: std.mem.Allocator, path: []const u8, field: Keybindings.Field, key: []const u8) !void {
        if (self.keybindings.conflict(field, key)) return error.DuplicateShortcut;
        const owned = try allocator.dupe(u8, key);
        errdefer allocator.free(owned);
        var updated = self.*;
        updated.keybindings.ptr(field).* = owned;
        try updated.save(path);
        allocator.free(self.keybindings.get(field));
        self.keybindings.ptr(field).* = owned;
    }

    fn writeAll(fd: std.posix.fd_t, data: []const u8) !void {
        var written: usize = 0;
        while (written < data.len) {
            const write_rc = std.posix.system.write(fd, data.ptr + written, data.len - written);
            switch (std.posix.errno(write_rc)) {
                .SUCCESS => written += @intCast(write_rc),
                .INTR => continue,
                else => return error.WriteFailed,
            }
        }
    }

    fn unlinkBestEffort(path_z: [*:0]const u8) void {
        _ = std.posix.system.unlink(path_z);
    }

    fn renameAtomic(old_z: [*:0]const u8, new_z: [*:0]const u8) !void {
        while (true) switch (std.posix.errno(std.posix.system.rename(old_z, new_z))) {
            .SUCCESS => return,
            .INTR => continue,
            else => return error.AtomicReplaceFailed,
        };
    }

    fn syncDirectory(allocator: std.mem.Allocator, path: []const u8) !void {
        const parent = std.fs.path.dirname(path) orelse ".";
        const parent_z = try allocator.dupeSentinel(u8, parent, 0);
        defer allocator.free(parent_z);
        const dir_fd = try std.posix.openatZ(std.posix.AT.FDCWD, parent_z, .{ .ACCMODE = .RDONLY, .DIRECTORY = true }, 0);
        defer _ = std.posix.system.close(dir_fd);
        switch (std.posix.errno(std.posix.system.fsync(dir_fd))) {
            .SUCCESS, .INVAL, .OPNOTSUPP, .ROFS => {}, // unsupported by this filesystem
            else => return error.DirectorySyncFailed,
        }
    }

    /// POSIX policy: reject symlink destinations, use same-directory O_EXCL
    /// temporaries with mode 0600, validate before rename, fsync data and the
    /// parent directory, and use atomic last-writer-wins replacement. The
    /// resulting file is deliberately private and owned by the saving user.
    fn saveWithFailure(self: *const SettingsConfig, path: []const u8, fail_at: SaveFailurePoint) !void {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        const path_z = try alloc.dupeSentinel(u8, path, 0);

        // Opening with NOFOLLOW rejects a destination symlink. A missing file
        // is expected; any other error must abort before creating a temporary.
        const existing_fd = std.posix.openatZ(std.posix.AT.FDCWD, path_z, .{ .ACCMODE = .RDONLY, .NOFOLLOW = true }, 0) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return err,
        };
        if (existing_fd) |fd| _ = std.posix.system.close(fd);

        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(alloc);

        var canonical = self.*;
        canonical.version = current_version;
        var aw: std.Io.Writer.Allocating = .fromArrayList(alloc, &buf);
        try std.json.Stringify.value(canonical, .{}, &aw.writer);
        var out_buf = aw.toArrayList();
        defer out_buf.deinit(alloc);
        if (out_buf.items.len > max_document_bytes) return error.SettingsDocumentTooLarge;
        const validation = try std.json.parseFromSlice(SettingsConfig, alloc, out_buf.items, .{ .ignore_unknown_fields = false });
        validation.deinit();

        const nonce = @atomicRmw(usize, &save_nonce, .Add, 1, .monotonic);
        const temp_path = try std.fmt.allocPrint(alloc, "{s}.tmp.{d}.{d}", .{ path, std.posix.system.getpid(), nonce });
        const temp_z = try alloc.dupeSentinel(u8, temp_path, 0);
        var temp_exists = false;
        defer {
            if (temp_exists) unlinkBestEffort(temp_z);
        }

        const fd = try std.posix.openatZ(std.posix.AT.FDCWD, temp_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true, .NOFOLLOW = true }, 0o600);
        temp_exists = true;
        var open = true;
        defer {
            if (open) _ = std.posix.system.close(fd);
        }
        if (fail_at == .after_create) return error.InjectedSaveFailure;
        try writeAll(fd, out_buf.items);
        if (fail_at == .after_write) return error.InjectedSaveFailure;
        try std.posix.fdatasync(fd);
        if (fail_at == .after_sync) return error.InjectedSaveFailure;
        _ = std.posix.system.close(fd);
        open = false;
        if (fail_at == .before_replace) return error.InjectedSaveFailure;

        try renameAtomic(temp_z, path_z);
        temp_exists = false;
        if (fail_at == .after_replace) return error.InjectedSaveFailure;
        try syncDirectory(alloc, path);

        // A backup is a separate best-effort transaction after the new primary
        // is known to parse. Failure here can never invalidate the primary.
        const backup_path = try std.fmt.allocPrint(alloc, "{s}.bak", .{path});
        self.writeBackupBestEffort(alloc, backup_path, out_buf.items);
    }

    fn writeBackupBestEffort(self: *const SettingsConfig, allocator: std.mem.Allocator, path: []const u8, data: []const u8) void {
        _ = self;
        const nonce = @atomicRmw(usize, &save_nonce, .Add, 1, .monotonic);
        const temp_path = std.fmt.allocPrint(allocator, "{s}.tmp.{d}.{d}", .{ path, std.posix.system.getpid(), nonce }) catch return;
        const temp_z = allocator.dupeSentinel(u8, temp_path, 0) catch return;
        const path_z = allocator.dupeSentinel(u8, path, 0) catch return;
        const fd = std.posix.openatZ(std.posix.AT.FDCWD, temp_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true, .NOFOLLOW = true }, 0o600) catch return;
        var exists = true;
        defer {
            if (exists) unlinkBestEffort(temp_z);
        }
        defer _ = std.posix.system.close(fd);
        writeAll(fd, data) catch return;
        std.posix.fdatasync(fd) catch return;
        const parsed = std.json.parseFromSlice(SettingsConfig, allocator, data, .{ .ignore_unknown_fields = false }) catch return;
        parsed.deinit();
        renameAtomic(temp_z, path_z) catch return;
        exists = false;
    }
};

pub const SettingsWidget = struct {
    is_open: bool = false,
    active_tab: usize = 0,
    allocator: std.mem.Allocator,
    config: SettingsConfig,
    needs_apply: bool = false,
    load_failed: bool = false,
    save_failed: bool = false,
    settings_path: []const u8,
    themes: std.array_list.Managed([]const u8),
    dropdown_scroll_offset: usize = 0,

    active_dropdown: DropdownType = .none,

    has_unsaved_changes: bool = false,
    popup_active: bool = false,

    active_binding: ?usize = null,
    duplicate_warning: bool = false,

    open_mason: bool = false,
    open_lazy: bool = false,
    open_installed: bool = false,
    software_update_requested: bool = false,
    software_update_status: SoftwareUpdateStatus = .idle,
    software_update_progress: u8 = 0,

    keyboard_focus: FocusMode = .tabs,
    hover_row: usize = 0,
    hover_dropdown_idx: usize = 0,

    io: std.Io,
    data_dir: []const u8,
    installed_plugins: std.array_list.Managed(InstalledPlugin),
    selected_plugin: ?InstalledPlugin = null,
    edit_config_path: ?[]const u8 = null,
    plugin_scroll_offset: usize = 0,
    popup_btn_idx: usize = 0,
    nvim_version: [32]u8 = [_]u8{0} ** 32,
    nvim_version_len: usize = 0,

    pub const InstalledPlugin = struct {
        full_name: []const u8,
        name: []const u8,
        stars: usize = 0,
        description: []const u8 = "",
    };

    pub const FocusMode = enum { tabs, content, dropdown };

    pub const SoftwareUpdateStatus = enum { idle, running, success, failure };

    pub const DropdownType = enum { none, theme, indent_size, indent_type, line_numbers, colorcolumn, split_separator, mode };

    pub const supported_modes = [_][]const u8{ "normal", "ide", "zen" };

    pub const supported_themes = [_][]const u8{ "vscode", "matteblack", "kanagawa", "tokyonight-night", "tokyonight-storm", "tokyonight-day", "catppuccin-latte", "catppuccin-frappe", "catppuccin-macchiato", "catppuccin-mocha", "gruvbox", "rose-pine", "rose-pine-moon", "rose-pine-dawn", "nord", "cyberdream" };

    pub const supported_indents = [_]u8{ 2, 4, 8 };
    pub const supported_indent_types = [_][]const u8{ "spaces", "tabs" };
    pub const supported_line_nums = [_][]const u8{ "relative", "normal", "off" };
    pub const supported_colorcolumns = [_][]const u8{ "", "80", "100", "120", "80,120" };
    pub const supported_split_seps = [_][]const u8{ "│", "▏", "▍", "", "┃", "║", "┊", " " };

    pub const tabs = [_][]const u8{
        "General",
        "Appearance",
        "Editor",
        "Plugins",
        "Keybindings",
        "About",
    };

    const software_updater = @embedFile("../../software_update.sh");

    pub fn init(allocator: std.mem.Allocator, settings_path: []const u8, io: std.Io, data_dir: []const u8) SettingsWidget {
        var load_failed = false;
        const config = SettingsConfig.load(allocator, settings_path) catch blk: {
            load_failed = true;
            var cfg = SettingsConfig{};
            cfg.theme = allocator.dupe(u8, cfg.theme) catch cfg.theme;
            cfg.line_numbers = allocator.dupe(u8, cfg.line_numbers) catch cfg.line_numbers;
            cfg.colorcolumn = allocator.dupe(u8, cfg.colorcolumn) catch cfg.colorcolumn;
            cfg.split_separator = allocator.dupe(u8, cfg.split_separator) catch cfg.split_separator;
            inline for (std.meta.fields(Keybindings)) |field| {
                @field(cfg.keybindings, field.name) = allocator.dupe(u8, @field(cfg.keybindings, field.name)) catch @field(cfg.keybindings, field.name);
            }
            cfg.mode = allocator.dupe(u8, cfg.mode) catch cfg.mode;
            break :blk cfg;
        };
        var widget = SettingsWidget{
            .is_open = false,
            .active_tab = 0,
            .allocator = allocator,
            .config = config,
            .needs_apply = true,
            .load_failed = load_failed,
            .save_failed = false,
            .settings_path = settings_path,
            .themes = std.array_list.Managed([]const u8).init(allocator),
            .dropdown_scroll_offset = 0,
            .io = io,
            .data_dir = data_dir,
            .installed_plugins = std.array_list.Managed(InstalledPlugin).init(allocator),
            .selected_plugin = null,
            .edit_config_path = null,
            .plugin_scroll_offset = 0,
            .popup_btn_idx = 0,
        };
        widget.setThemesAndGroup(&supported_themes) catch {};
        return widget;
    }

    fn updatePath(self: *const SettingsWidget, file_name: []const u8) ![]u8 {
        return std.fs.path.join(self.allocator, &.{ self.data_dir, file_name });
    }

    pub fn startSoftwareUpdate(self: *SettingsWidget) !void {
        if (self.software_update_status == .running) return;
        const script_path = try self.updatePath("software-update.sh");
        defer self.allocator.free(script_path);
        const status_path = try self.updatePath("software-update.status");
        defer self.allocator.free(status_path);
        const log_path = try self.updatePath("software-update.log");
        defer self.allocator.free(log_path);
        const progress_path = try self.updatePath("software-update.progress");
        defer self.allocator.free(progress_path);

        std.Io.Dir.cwd().deleteFile(self.io, status_path) catch {};
        std.Io.Dir.cwd().deleteFile(self.io, progress_path) catch {};
        try std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = script_path, .data = software_updater });

        // The outer shell exits immediately after detaching the updater. Tuim
        // remains responsive and the updater can finish if the app is closed.
        const argv = &[_][]const u8{
            "sh",
            "-c",
            "sh \"$1\" \"$2\" \"$3\" \"$4\" >/dev/null 2>&1 &",
            "tuim-software-update",
            script_path,
            status_path,
            log_path,
            progress_path,
        };
        var child = try std.process.spawn(self.io, .{
            .argv = argv,
            .stdin = .ignore,
            .stdout = .ignore,
            .stderr = .ignore,
        });
        const term = try child.wait(self.io);
        if (term != .exited or term.exited != 0) return error.UpdateLaunchFailed;
        self.software_update_progress = 0;
        self.software_update_status = .running;
    }

    fn pollSoftwareUpdateProgress(self: *SettingsWidget) void {
        const progress_path = self.updatePath("software-update.progress") catch return;
        defer self.allocator.free(progress_path);
        const progress_path_z = self.allocator.dupeSentinel(u8, progress_path, 0) catch return;
        defer self.allocator.free(progress_path_z);
        const fd = std.posix.openatZ(std.posix.AT.FDCWD, progress_path_z, .{ .ACCMODE = .RDONLY }, 0) catch return;
        defer _ = std.posix.system.close(fd);
        var buf: [8]u8 = undefined;
        const rc = std.posix.system.read(fd, &buf, buf.len);
        if (std.posix.errno(rc) != .SUCCESS) return;
        const value = std.fmt.parseInt(u8, std.mem.trim(u8, buf[0..@intCast(rc)], " \r\n\t"), 10) catch return;
        self.software_update_progress = @min(value, 100);
    }

    pub fn pollSoftwareUpdate(self: *SettingsWidget) ?SoftwareUpdateStatus {
        if (self.software_update_status != .running) return null;
        self.pollSoftwareUpdateProgress();
        const status_path = self.updatePath("software-update.status") catch return null;
        defer self.allocator.free(status_path);
        const status_path_z = self.allocator.dupeSentinel(u8, status_path, 0) catch return null;
        defer self.allocator.free(status_path_z);
        const fd = std.posix.openatZ(std.posix.AT.FDCWD, status_path_z, .{ .ACCMODE = .RDONLY }, 0) catch return null;
        defer _ = std.posix.system.close(fd);
        var buf: [16]u8 = undefined;
        const rc = std.posix.system.read(fd, &buf, buf.len);
        if (std.posix.errno(rc) != .SUCCESS) return null;
        const result = std.mem.trim(u8, buf[0..@intCast(rc)], " \r\n\t");
        if (std.mem.eql(u8, result, "success")) {
            self.software_update_progress = 100;
            self.software_update_status = .success;
        } else if (std.mem.eql(u8, result, "failure")) {
            self.software_update_status = .failure;
        } else {
            return null;
        }
        return self.software_update_status;
    }

    pub fn deinit(self: *SettingsWidget) void {
        self.config.deinit(self.allocator);
        for (self.themes.items) |t| {
            self.allocator.free(t);
        }
        self.themes.deinit();

        for (self.installed_plugins.items) |p| {
            self.allocator.free(p.full_name);
            self.allocator.free(p.name);
            self.allocator.free(p.description);
        }
        self.installed_plugins.deinit();
        if (self.edit_config_path) |path| {
            self.allocator.free(path);
        }
    }

    fn setThemesAndGroup(self: *SettingsWidget, raw_list: []const []const u8) !void {
        // Clear old themes
        for (self.themes.items) |t| {
            self.allocator.free(t);
        }
        self.themes.clearRetainingCapacity();

        var tuim_list = std.array_list.Managed([]const u8).init(self.allocator);
        defer tuim_list.deinit();
        var vim_list = std.array_list.Managed([]const u8).init(self.allocator);
        defer vim_list.deinit();
        var user_list = std.array_list.Managed([]const u8).init(self.allocator);
        defer user_list.deinit();

        const vim_defaults = [_][]const u8{ "default", "blue", "darkblue", "desert", "elflord", "habamax", "industry", "koehler", "lunaperche", "minischeme", "morning", "murphy", "peachpuff", "quiet", "randomhue", "retrobox", "ron", "shine", "slate", "sorbet", "torte", "wildcharm", "zaibatsu" };

        for (raw_list) |t| {
            if (std.mem.eql(u8, t, "system")) continue;
            var is_tuim = false;
            for (supported_themes) |st| {
                if (std.mem.eql(u8, t, st)) {
                    is_tuim = true;
                    break;
                }
            }
            if (is_tuim) {
                try tuim_list.append(t);
                continue;
            }

            var is_vim = false;
            for (vim_defaults) |vd| {
                if (std.mem.eql(u8, t, vd)) {
                    is_vim = true;
                    break;
                }
            }
            if (is_vim) {
                try vim_list.append(t);
                continue;
            }

            try user_list.append(t);
        }

        // System is built in, so it remains available without theme plugins.
        try self.themes.append(try self.allocator.dupe(u8, "--- Tuim Themes ---"));
        try self.themes.append(try self.allocator.dupe(u8, "system"));
        if (tuim_list.items.len > 0) {
            for (tuim_list.items) |t| {
                try self.themes.append(try self.allocator.dupe(u8, t));
            }
        }
        if (vim_list.items.len > 0) {
            try self.themes.append(try self.allocator.dupe(u8, "--- Vim Defaults ---"));
            for (vim_list.items) |t| {
                try self.themes.append(try self.allocator.dupe(u8, t));
            }
        }
        if (user_list.items.len > 0) {
            try self.themes.append(try self.allocator.dupe(u8, "--- Installed ---"));
            for (user_list.items) |t| {
                try self.themes.append(try self.allocator.dupe(u8, t));
            }
        }
    }

    fn openThemeDropdown(self: *SettingsWidget) void {
        self.active_dropdown = .theme;
        self.hover_dropdown_idx = 1;
        self.dropdown_scroll_offset = 0;
        for (self.themes.items, 0..) |t, idx| {
            if (std.mem.eql(u8, t, self.config.theme)) {
                self.hover_dropdown_idx = idx;
                if (idx >= max_visible_themes) {
                    self.dropdown_scroll_offset = idx - (max_visible_themes / 2);
                    if (self.dropdown_scroll_offset + max_visible_themes > self.themes.items.len) {
                        self.dropdown_scroll_offset = self.themes.items.len - max_visible_themes;
                    }
                } else {
                    self.dropdown_scroll_offset = 0;
                }
                break;
            }
        }
    }

    pub fn refreshThemes(self: *SettingsWidget, rpc: *@import("../../nvim/rpc.zig").RpcClient) void {
        const Value = @import("../../nvim/msgpack.zig").Value;
        const msgpack = @import("../../nvim/msgpack.zig");

        var params = self.allocator.alloc(Value, 2) catch return;
        defer self.allocator.free(params);
        params[0] = .{ .string = "return vim.fn.getcompletion('', 'color')" };
        params[1] = .{ .array = &[_]Value{} };

        if (rpc.isAsyncEnabled()) {
            _ = rpc.requestAsyncWithHandler("nvim_exec_lua", params, self, asyncThemesComplete) catch return;
            return;
        }

        if (rpc.call("nvim_exec_lua", params) catch null) |res| {
            defer msgpack.freeValue(res, self.allocator);
            self.applyThemesResult(res);
        }
    }

    fn asyncThemesComplete(context: ?*anyopaque, completion: *@import("../../nvim/async_transport.zig").Completion) anyerror!void {
        const self: *SettingsWidget = @ptrCast(@alignCast(context.?));
        switch (completion.outcome) {
            .response => |response| if (response.error_value == .nil) self.applyThemesResult(response.result),
            .failed => {},
        }
    }

    fn applyThemesResult(self: *SettingsWidget, res: @import("../../nvim/msgpack.zig").Value) void {
        if (res != .array or res.array.len == 0) return;
        var raw_list = std.array_list.Managed([]const u8).init(self.allocator);
        defer raw_list.deinit();
        for (res.array) |item| if (item == .string) raw_list.append(item.string) catch {};
        self.setThemesAndGroup(raw_list.items) catch {};
    }

    fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        const path_z = try allocator.dupeSentinel(u8, path, 0);
        defer allocator.free(path_z);

        const fd = try std.posix.openatZ(std.posix.AT.FDCWD, path_z, .{ .ACCMODE = .RDONLY }, 0);
        defer _ = std.posix.system.close(fd);

        var list: std.ArrayList(u8) = .empty;
        errdefer list.deinit(allocator);

        var chunk: [4096]u8 = undefined;
        while (true) {
            const read_len = try std.posix.read(fd, &chunk);
            if (read_len == 0) break;
            try list.appendSlice(allocator, chunk[0..read_len]);
        }
        return try list.toOwnedSlice(allocator);
    }

    pub fn refreshPlugins(self: *SettingsWidget) void {
        for (self.installed_plugins.items) |p| {
            self.allocator.free(p.full_name);
            self.allocator.free(p.name);
            self.allocator.free(p.description);
        }
        self.installed_plugins.clearRetainingCapacity();
    }

    fn editConfig(self: *SettingsWidget, p: InstalledPlugin) !void {
        const configs_dir = try std.fs.path.join(self.allocator, &[_][]const u8{ self.data_dir, "plugin_configs" });
        defer self.allocator.free(configs_dir);

        const file_name = try self.allocator.dupe(u8, p.full_name);
        defer self.allocator.free(file_name);
        for (file_name) |*c| {
            if (c.* == '/') {
                c.* = '_';
            }
        }

        const suffix = ".lua";
        const full_file_name = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ file_name, suffix });
        defer self.allocator.free(full_file_name);

        const config_file_path = try std.fs.path.join(self.allocator, &[_][]const u8{ configs_dir, full_file_name });
        errdefer self.allocator.free(config_file_path);

        std.Io.Dir.cwd().createDir(self.io, configs_dir, .default_dir) catch {};

        if (std.Io.Dir.openFileAbsolute(self.io, config_file_path, .{})) |file_value| {
            var file = file_value;
            file.close(self.io);
        } else |err| switch (err) {
            error.FileNotFound => {
                var template_buf: [512]u8 = undefined;
                const template = try std.fmt.bufPrint(
                    &template_buf,
                    "-- Configuration for {s}\n" ++
                        "-- This file is loaded automatically by lazy.nvim\n\n" ++
                        "return {{\n" ++
                        "  -- Add your custom plugin configuration here\n" ++
                        "}}\n",
                    .{p.name},
                );
                try std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = config_file_path, .data = template });
            },
            else => return err,
        }

        self.edit_config_path = config_file_path;
        self.is_open = false;
        self.selected_plugin = null;
    }

    pub fn draw(self: *const SettingsWidget, ren: *renderer.Renderer, screen_w: u16, screen_h: u16, theme: anytype) void {
        if (!self.is_open) return;

        const modal = primitives.Modal.centered(screen_w, screen_h, 80, 24, 5);
        const x = modal.rect.x;
        const y = modal.rect.y;
        const w = modal.rect.w;
        const h = modal.rect.h;

        if (!primitives.usable(modal, 50, 18)) {
            primitives.drawSizeWarning(ren, "Tuim Settings", theme.fg_primary, theme.bg_sidebar);
            return;
        }

        primitives.drawModalFrame(ren, modal, .rounded, theme.fg_primary, theme.bg_sidebar, theme.border_color, theme.bg_editor);

        // Title
        var settings_title_buf: [64]u8 = undefined;
        const title = std.fmt.bufPrint(&settings_title_buf, " Tuim Settings v{s} ", .{build_options.version}) catch " Tuim Settings ";
        ren.drawText(x + 2, y, title, theme.fg_accent, theme.bg_sidebar, true, false);

        const pointer = ren.pointer_position;
        defer ren.pointer_position = pointer;
        if (self.active_dropdown != .none or self.popup_active or self.duplicate_warning or self.selected_plugin != null)
            ren.pointer_position = null;

        // Close button
        ren.drawControlText(x + w - 4, y, if (self.config.nerd_fonts) " 󰅖 " else " x ", .{ .rgb = .{ .r = 255, .g = 85, .b = 85 } }, theme.bg_sidebar, false, false);

        // Save button
        const save_button = primitives.Button{
            .rect = .{ .x = x + w - 18, .y = y + h - 2, .w = 16, .h = 1 },
            .state = if (self.has_unsaved_changes) .selected else .normal,
        };
        save_button.draw(ren, "Save Ctrl+S", .{
            .fg = theme.fg_secondary,
            .bg = theme.bg_sidebar,
            .accent_fg = theme.fg_primary,
            .accent_bg = theme.bg_accent,
            .muted_fg = theme.fg_secondary,
        });

        // Tabs
        var tab_y: u16 = y + 2;
        for (tabs, 0..) |tab, idx| {
            const is_active = (idx == self.active_tab);
            const fg = if (is_active) theme.fg_primary else theme.fg_secondary;
            if (is_active) {
                ren.drawText(x + 1, tab_y, " ┃ ", theme.fg_accent, theme.bg_sidebar, true, false);
                if (self.keyboard_focus == .tabs) {
                    ren.drawText(x + 1, tab_y, "▋", theme.fg_accent, theme.bg_sidebar, true, false);
                }
            }
            ren.drawText(x + 4, tab_y, tab, fg, theme.bg_sidebar, is_active, false);
            ren.highlightHover(.{ .x = x + 1, .y = tab_y, .w = 18, .h = 2 }, theme.bg_sidebar, theme.fg_primary);
            tab_y += 2;
        }

        // Separator between tabs and content
        for (y + 1..y + h - 1) |by| {
            ren.drawText(x + 20, @intCast(by), "│", theme.border_color, theme.bg_sidebar, false, false);
        }

        // Tab Content
        const content_x = x + 22;
        const content_y = y + 2;
        var buf: [128]u8 = undefined;

        switch (self.active_tab) {
            0 => {
                ren.drawText(content_x, content_y, "General Settings", theme.fg_primary, theme.bg_sidebar, true, false);

                const clip_t = if (self.config.clip) "[x]" else "[ ]";
                const clip_str = std.fmt.bufPrint(&buf, "{s} System Clipboard", .{clip_t}) catch "System Clipboard";
                ren.drawControlText(content_x, content_y + 2, clip_str, theme.fg_primary, theme.bg_sidebar, false, false);

                const mode_str = if (self.config.nerd_fonts)
                    std.fmt.bufPrint(&buf, "Mode:  [ {s} ▾ ]", .{self.config.mode}) catch "Mode: normal"
                else
                    std.fmt.bufPrint(&buf, "Mode:  [ {s} v ]", .{self.config.mode}) catch "Mode: normal";
                ren.drawControlText(content_x, content_y + 4, mode_str, theme.fg_primary, theme.bg_sidebar, false, false);

                const auto_t = if (self.config.autocomplete) "[x]" else "[ ]";
                const auto_str = std.fmt.bufPrint(&buf, "{s} Autocomplete", .{auto_t}) catch "Autocomplete";
                ren.drawControlText(content_x, content_y + 6, auto_str, theme.fg_primary, theme.bg_sidebar, false, false);

                const indent_t = if (self.config.autoindent) "[x]" else "[ ]";
                const indent_str = std.fmt.bufPrint(&buf, "{s} Autoindent", .{indent_t}) catch "Autoindent";
                ren.drawControlText(content_x, content_y + 8, indent_str, theme.fg_primary, theme.bg_sidebar, false, false);

                ren.drawText(content_x, content_y + 11, "Normal: full Vim-style editing and modes", theme.fg_secondary, theme.bg_sidebar, false, false);
                ren.drawText(content_x, content_y + 12, "IDE: familiar modeless text editing", theme.fg_secondary, theme.bg_sidebar, false, false);
                ren.drawText(content_x, content_y + 13, "Zen: fullscreen editor; F11 returns here", theme.fg_secondary, theme.bg_sidebar, false, false);
            },
            1 => {
                ren.drawText(content_x, content_y, "Appearance", theme.fg_primary, theme.bg_sidebar, true, false);

                const theme_str = if (self.config.nerd_fonts)
                    std.fmt.bufPrint(&buf, "Theme:  [ {s} ▾ ]", .{themeLabel(self.config.theme)}) catch "Theme: VS Code Dark Modern"
                else
                    std.fmt.bufPrint(&buf, "Theme:  [ {s} v ]", .{themeLabel(self.config.theme)}) catch "Theme: VS Code Dark Modern";
                ren.drawControlText(content_x, content_y + 2, theme_str, theme.fg_primary, theme.bg_sidebar, false, false);

                const sep_str = if (self.config.nerd_fonts)
                    std.fmt.bufPrint(&buf, "Split Separator:  [ {s} ▾ ]", .{self.config.split_separator}) catch "Split Separator: │"
                else
                    std.fmt.bufPrint(&buf, "Split Separator:  [ {s} v ]", .{self.config.split_separator}) catch "Split Separator: │";
                ren.drawControlText(content_x, content_y + 4, sep_str, theme.fg_primary, theme.bg_sidebar, false, false);

                const nf_t = if (self.config.nerd_fonts) "[x]" else "[ ]";
                const nf_str = std.fmt.bufPrint(&buf, "{s} Use Nerd Fonts (Icons)", .{nf_t}) catch "Use Nerd Fonts (Icons)";
                ren.drawControlText(content_x, content_y + 6, nf_str, theme.fg_primary, theme.bg_sidebar, false, false);
            },
            2 => {
                ren.drawText(content_x, content_y, "Editor", theme.fg_primary, theme.bg_sidebar, true, false);

                const type_str = if (self.config.nerd_fonts)
                    std.fmt.bufPrint(&buf, "Indent Type:  [ {s} ▾ ]", .{if (self.config.use_tabs) "tabs" else "spaces"}) catch "Indent Type: spaces"
                else
                    std.fmt.bufPrint(&buf, "Indent Type:  [ {s} v ]", .{if (self.config.use_tabs) "tabs" else "spaces"}) catch "Indent Type: spaces";
                ren.drawControlText(content_x, content_y + 2, type_str, theme.fg_primary, theme.bg_sidebar, false, false);

                const indent_str = if (self.config.nerd_fonts)
                    std.fmt.bufPrint(&buf, "Indent Size:  [ {d} ▾ ]", .{self.config.indent_size}) catch "Indent Size: 4"
                else
                    std.fmt.bufPrint(&buf, "Indent Size:  [ {d} v ]", .{self.config.indent_size}) catch "Indent Size: 4";
                ren.drawControlText(content_x, content_y + 4, indent_str, theme.fg_primary, theme.bg_sidebar, false, false);

                const wrap_t = if (self.config.wrap) "[x]" else "[ ]";
                const wrap_str = std.fmt.bufPrint(&buf, "{s} Text Wrap", .{wrap_t}) catch "Text Wrap";
                ren.drawControlText(content_x, content_y + 6, wrap_str, theme.fg_primary, theme.bg_sidebar, false, false);

                const line_str = if (self.config.nerd_fonts)
                    std.fmt.bufPrint(&buf, "Line Numbers:  [ {s} ▾ ]", .{self.config.line_numbers}) catch "Line Numbers: relative"
                else
                    std.fmt.bufPrint(&buf, "Line Numbers:  [ {s} v ]", .{self.config.line_numbers}) catch "Line Numbers: relative";
                ren.drawControlText(content_x, content_y + 8, line_str, theme.fg_primary, theme.bg_sidebar, false, false);

                const ruler_value = if (self.config.colorcolumn.len == 0) "off" else self.config.colorcolumn;
                const ruler_str = if (self.config.nerd_fonts)
                    std.fmt.bufPrint(&buf, "Column Ruler:  [ {s} ▾ ]", .{ruler_value}) catch "Column Ruler: off"
                else
                    std.fmt.bufPrint(&buf, "Column Ruler:  [ {s} v ]", .{ruler_value}) catch "Column Ruler: off";
                ren.drawControlText(content_x, content_y + 10, ruler_str, theme.fg_primary, theme.bg_sidebar, false, false);
            },
            3 => {
                ren.drawText(content_x, content_y, "Plugins", theme.fg_primary, theme.bg_sidebar, true, false);

                // Mason Button
                const mason_btn = " [ Mason Settings... ] ";
                const is_mason_hover = (self.keyboard_focus == .content and self.hover_row == 0);
                ren.drawControlText(content_x, content_y + 2, mason_btn, if (is_mason_hover) theme.fg_primary else theme.bg_sidebar, if (is_mason_hover) theme.fg_accent else theme.fg_accent, true, false);

                // Plugin Manager Button
                const lazy_btn = " [ Plugin Manager... ] ";
                const is_lazy_hover = (self.keyboard_focus == .content and self.hover_row == 1);
                ren.drawControlText(content_x, content_y + 4, lazy_btn, if (is_lazy_hover) theme.fg_primary else theme.bg_sidebar, if (is_lazy_hover) theme.fg_accent else theme.fg_accent, true, false);

                ren.drawControlText(content_x, content_y + 6, " [ Installed Plugins... ] ", theme.bg_sidebar, theme.fg_accent, true, false);
                ren.drawText(content_x, content_y + 9, "Configure, enable, disable, or uninstall.", theme.fg_secondary, theme.bg_sidebar, false, false);
                ren.drawText(content_x, content_y + 11, "Changes apply after restarting Tuim.", theme.fg_secondary, theme.bg_sidebar, false, false);
            },
            4 => {
                ren.drawText(content_x, content_y, "Keybindings / Enter or click to record", theme.fg_primary, theme.bg_sidebar, true, false);

                const actions = [_][]const u8{ "Toggle Terminal", "Toggle Sidebar", "Toggle Zen Mode", "New File", "Find File", "Search Project", "Quit", "Save File", "Commands", "Next Region" };
                const current_keys = [_][]const u8{
                    self.config.keybindings.toggle_terminal,
                    self.config.keybindings.toggle_explorer,
                    self.config.keybindings.toggle_zen,
                    self.config.keybindings.new_file,
                    self.config.keybindings.find_file,
                    self.config.keybindings.search_project,
                    self.config.keybindings.quit,
                    self.config.keybindings.save_file,
                    self.config.keybindings.commands,
                    self.config.keybindings.focus_next,
                };

                for (actions, 0..) |action, i| {
                    var key_buf: [32]u8 = undefined;
                    const key_str = if (self.active_binding == i)
                        "Press any key... (Esc to cancel)"
                    else
                        formatKeyName(current_keys[i], &key_buf);

                    const draw_str = std.fmt.bufPrint(&buf, "{s}:  [ {s} ]", .{ action, key_str }) catch action;
                    const color = if (self.active_binding == i) theme.fg_accent else theme.fg_primary;
                    ren.drawControlText(content_x, content_y + 2 + @as(u16, @intCast(i)), draw_str, color, theme.bg_sidebar, false, false);
                }

                ren.drawControlText(content_x, content_y + 13, "v Vim-safe", theme.fg_secondary, theme.bg_sidebar, false, false);
                ren.drawControlText(content_x + 13, content_y + 13, "p Familiar", theme.fg_secondary, theme.bg_sidebar, false, false);
                ren.drawControlText(content_x + 26, content_y + 13, "r Reset selected", theme.fg_secondary, theme.bg_sidebar, false, false);
                ren.drawText(content_x, content_y + 14, "Presets replace bindings; Ctrl+S saves", theme.fg_secondary, theme.bg_sidebar, false, false);
            },
            5 => {
                ren.drawText(content_x, content_y, "About Tuim", theme.fg_primary, theme.bg_sidebar, true, false);

                const tuim_line = std.fmt.bufPrint(&buf, "Tuim version: {s}", .{build_options.version}) catch "Tuim version: unknown";
                ren.drawText(content_x, content_y + 2, tuim_line, theme.fg_primary, theme.bg_sidebar, false, false);
                const nvim_version = if (self.nvim_version_len > 0) self.nvim_version[0..self.nvim_version_len] else "unknown";
                const nvim_line = std.fmt.bufPrint(&buf, "Neovim version: {s}", .{nvim_version}) catch "Neovim version: unknown";
                ren.drawText(content_x, content_y + 4, nvim_line, theme.fg_primary, theme.bg_sidebar, false, false);

                const update_label = switch (self.software_update_status) {
                    .idle => "Update to Latest Version",
                    .running => "Updating Tuim...",
                    .success => "Updated - Restart Tuim",
                    .failure => "Update Failed - Retry",
                };
                const update_state: primitives.ControlState = if (self.software_update_status == .running)
                    .disabled
                else if (self.keyboard_focus == .content)
                    .focused
                else
                    .normal;
                (primitives.Button{ .rect = .{ .x = content_x, .y = content_y + 6, .w = 28, .h = 1 }, .state = update_state }).draw(ren, update_label, .{
                    .fg = theme.fg_secondary,
                    .bg = theme.bg_sidebar,
                    .accent_fg = theme.fg_primary,
                    .accent_bg = theme.bg_accent,
                    .muted_fg = theme.fg_secondary,
                });

                if (self.software_update_status != .idle) {
                    const progress_width = @min(@as(u16, 28), w -| 30);
                    const filled_width: u16 = @intCast((@as(u32, progress_width) * self.software_update_progress) / 100);
                    ren.drawRect(.{ .x = content_x, .y = content_y + 8, .w = progress_width, .h = 1 }, "░", theme.fg_secondary, theme.bg_editor);
                    ren.drawRect(.{ .x = content_x, .y = content_y + 8, .w = filled_width, .h = 1 }, "█", theme.fg_accent, theme.bg_editor);
                    const progress_label = std.fmt.bufPrint(&buf, "{d}%", .{self.software_update_progress}) catch "";
                    ren.drawText(content_x + progress_width + 1, content_y + 8, progress_label, theme.fg_primary, theme.bg_sidebar, true, false);
                }

                ren.drawText(content_x, content_y + 10, "Runtime paths", theme.fg_primary, theme.bg_sidebar, true, false);
                a: {
                    const available = if (w > 26) w - 26 else 1;
                    ren.drawText(content_x, content_y + 12, "Data:", theme.fg_secondary, theme.bg_sidebar, false, false);
                    ren.drawTextClipped(content_x + 10, content_y + 12, available, self.data_dir, theme.fg_primary, theme.bg_sidebar, false, false);
                    ren.drawText(content_x, content_y + 14, "Settings:", theme.fg_secondary, theme.bg_sidebar, false, false);
                    ren.drawTextClipped(content_x + 10, content_y + 14, available, self.settings_path, theme.fg_primary, theme.bg_sidebar, false, false);
                    const log_path = std.fmt.bufPrint(&buf, "{s}/tuim.log", .{self.data_dir}) catch self.data_dir;
                    ren.drawText(content_x, content_y + 16, "Log:", theme.fg_secondary, theme.bg_sidebar, false, false);
                    ren.drawTextClipped(content_x + 10, content_y + 16, available, log_path, theme.fg_primary, theme.bg_sidebar, false, false);
                    break :a;
                }
            },
            else => {},
        }

        if (self.keyboard_focus == .content) {
            var row_y: ?u16 = null;
            if (self.active_tab == 3) {
                if (self.hover_row == 0) {
                    row_y = content_y + 2;
                } else if (self.hover_row == 1) {
                    row_y = content_y + 4;
                } else {
                    row_y = content_y + 6;
                }
            } else {
                const step = if (self.active_tab == 4) @as(u16, 1) else @as(u16, 2);
                row_y = content_y + 2 + @as(u16, @intCast(self.hover_row)) * step;
            }
            if (row_y) |ry| {
                ren.drawText(content_x - 2, ry, "▋", theme.fg_accent, theme.bg_sidebar, true, false);
            }
        }

        ren.pointer_position = pointer;
        // Draw active dropdown if any
        if (self.active_dropdown != .none) {
            const drop_x = content_x + 10;
            var drop_y = content_y + 3; // roughly below the selector
            var items_len: usize = 0;
            var drop_w: u16 = 20;

            if (self.active_dropdown == .theme) {
                items_len = self.themes.items.len;
                drop_w = 32;
                drop_y = content_y + 3;
            } else if (self.active_dropdown == .split_separator) {
                items_len = supported_split_seps.len;
                drop_y = content_y + 5;
            } else if (self.active_dropdown == .indent_size) {
                items_len = supported_indents.len;
                drop_y = content_y + 5;
            } else if (self.active_dropdown == .indent_type) {
                items_len = supported_indent_types.len;
                drop_y = content_y + 3;
            } else if (self.active_dropdown == .line_numbers) {
                items_len = supported_line_nums.len;
                drop_y = content_y + 9;
            } else if (self.active_dropdown == .colorcolumn) {
                items_len = supported_colorcolumns.len;
                drop_y = content_y + 11;
            } else if (self.active_dropdown == .mode) {
                items_len = supported_modes.len;
                drop_w = 16;
                drop_y = content_y + 5;
            }

            // clamp drop height to screen_h if it's too tall, or just draw
            const max_visible = if (self.active_dropdown == .theme) @min(items_len, 8) else items_len;
            const drop_h = @as(u16, @intCast(max_visible)) + 2;

            const dropdown = primitives.Modal{ .rect = .{ .x = drop_x, .y = drop_y, .w = drop_w, .h = drop_h } };
            primitives.drawModalFrame(ren, dropdown, .rounded, theme.fg_primary, theme.bg_sidebar, theme.border_color, theme.bg_editor);

            // Items
            var item_y = drop_y + 1;
            if (self.active_dropdown == .theme) {
                var i: usize = self.dropdown_scroll_offset;
                const end_idx = @min(self.themes.items.len, self.dropdown_scroll_offset + max_visible_themes);
                while (i < end_idx) : (i += 1) {
                    if (item_y >= screen_h) break;
                    const t = self.themes.items[i];
                    if (std.mem.startsWith(u8, t, "---")) {
                        ren.drawText(drop_x + 1, item_y, t, theme.fg_secondary, theme.bg_sidebar, false, false);
                    } else {
                        const is_sel = std.mem.eql(u8, self.config.theme, t);
                        const prefix = if (is_sel) " * " else "   ";
                        const str = std.fmt.bufPrint(&buf, "{s}{s}", .{ prefix, themeLabel(t) }) catch " error";
                        ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                        if (i == self.hover_dropdown_idx) ren.drawText(drop_x + 1, item_y, "▋", theme.fg_accent, theme.bg_sidebar, true, false);
                        ren.highlightHover(.{ .x = drop_x + 1, .y = item_y, .w = drop_w - 2, .h = 1 }, theme.bg_sidebar, theme.fg_primary);
                    }
                    item_y += 1;
                }

                // Draw indicators for scrollability
                if (self.dropdown_scroll_offset > 0) {
                    ren.drawText(drop_x + drop_w - 2, drop_y, "▲", theme.fg_accent, theme.bg_sidebar, false, false);
                }
                if (self.dropdown_scroll_offset + max_visible_themes < self.themes.items.len) {
                    ren.drawText(drop_x + drop_w - 2, drop_y + drop_h - 1, "▼", theme.fg_accent, theme.bg_sidebar, false, false);
                }
            } else if (self.active_dropdown == .split_separator) {
                for (supported_split_seps, 0..) |s, idx| {
                    if (item_y >= screen_h) break;
                    const is_sel = std.mem.eql(u8, self.config.split_separator, s);
                    const prefix = if (is_sel) " * " else "   ";
                    const str = std.fmt.bufPrint(&buf, "{s}{s}", .{ prefix, s }) catch " error";
                    ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                    if (idx == self.hover_dropdown_idx) ren.drawText(drop_x + 1, item_y, "▋", theme.fg_accent, theme.bg_sidebar, true, false);
                    ren.highlightHover(.{ .x = drop_x + 1, .y = item_y, .w = drop_w - 2, .h = 1 }, theme.bg_sidebar, theme.fg_primary);
                    item_y += 1;
                }
            } else if (self.active_dropdown == .indent_size) {
                for (supported_indents, 0..) |i, idx| {
                    if (item_y >= screen_h) break;
                    const is_sel = (self.config.indent_size == i);
                    const prefix = if (is_sel) " * " else "   ";
                    const str = std.fmt.bufPrint(&buf, "{s}{d}", .{ prefix, i }) catch " error";
                    ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                    if (idx == self.hover_dropdown_idx) ren.drawText(drop_x + 1, item_y, "▋", theme.fg_accent, theme.bg_sidebar, true, false);
                    ren.highlightHover(.{ .x = drop_x + 1, .y = item_y, .w = drop_w - 2, .h = 1 }, theme.bg_sidebar, theme.fg_primary);
                    item_y += 1;
                }
            } else if (self.active_dropdown == .indent_type) {
                for (supported_indent_types, 0..) |t, idx| {
                    if (item_y >= screen_h) break;
                    const is_sel = if (std.mem.eql(u8, t, "tabs")) self.config.use_tabs else !self.config.use_tabs;
                    const prefix = if (is_sel) " * " else "   ";
                    const str = std.fmt.bufPrint(&buf, "{s}{s}", .{ prefix, t }) catch " error";
                    ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                    if (idx == self.hover_dropdown_idx) ren.drawText(drop_x + 1, item_y, "▋", theme.fg_accent, theme.bg_sidebar, true, false);
                    ren.highlightHover(.{ .x = drop_x + 1, .y = item_y, .w = drop_w - 2, .h = 1 }, theme.bg_sidebar, theme.fg_primary);
                    item_y += 1;
                }
            } else if (self.active_dropdown == .line_numbers) {
                for (supported_line_nums, 0..) |ln, idx| {
                    if (item_y >= screen_h) break;
                    const is_sel = std.mem.eql(u8, self.config.line_numbers, ln);
                    const prefix = if (is_sel) " * " else "   ";
                    const str = std.fmt.bufPrint(&buf, "{s}{s}", .{ prefix, ln }) catch " error";
                    ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                    if (idx == self.hover_dropdown_idx) ren.drawText(drop_x + 1, item_y, "▋", theme.fg_accent, theme.bg_sidebar, true, false);
                    ren.highlightHover(.{ .x = drop_x + 1, .y = item_y, .w = drop_w - 2, .h = 1 }, theme.bg_sidebar, theme.fg_primary);
                    item_y += 1;
                }
            } else if (self.active_dropdown == .colorcolumn) {
                for (supported_colorcolumns, 0..) |column, idx| {
                    if (item_y >= screen_h) break;
                    const is_sel = std.mem.eql(u8, self.config.colorcolumn, column);
                    const prefix = if (is_sel) " * " else "   ";
                    const label = if (column.len == 0) "off (default)" else column;
                    const str = std.fmt.bufPrint(&buf, "{s}{s}", .{ prefix, label }) catch " error";
                    ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                    if (idx == self.hover_dropdown_idx) ren.drawText(drop_x + 1, item_y, "▋", theme.fg_accent, theme.bg_sidebar, true, false);
                    ren.highlightHover(.{ .x = drop_x + 1, .y = item_y, .w = drop_w - 2, .h = 1 }, theme.bg_sidebar, theme.fg_primary);
                    item_y += 1;
                }
            } else if (self.active_dropdown == .mode) {
                for (supported_modes, 0..) |m, idx| {
                    if (item_y >= screen_h) break;
                    const is_sel = std.mem.eql(u8, self.config.mode, m);
                    const prefix = if (is_sel) " * " else "   ";
                    const str = std.fmt.bufPrint(&buf, "{s}{s}", .{ prefix, m }) catch " error";
                    ren.drawText(drop_x + 1, item_y, str, if (is_sel) theme.fg_accent else theme.fg_primary, theme.bg_sidebar, false, false);
                    if (idx == self.hover_dropdown_idx) ren.drawText(drop_x + 1, item_y, "▋", theme.fg_accent, theme.bg_sidebar, true, false);
                    ren.highlightHover(.{ .x = drop_x + 1, .y = item_y, .w = drop_w - 2, .h = 1 }, theme.bg_sidebar, theme.fg_primary);
                    item_y += 1;
                }
            }
        }

        if (self.popup_active) {
            const popup = primitives.Modal.centered(screen_w, screen_h, 30, 7, 0);
            const px = popup.rect.x;
            const py = popup.rect.y;
            primitives.drawModalFrame(ren, popup, .rounded, theme.fg_primary, theme.bg_sidebar, theme.border_color, theme.bg_editor);

            ren.drawText(px + 2, py + 1, " Unsaved Changes ", theme.fg_accent, theme.bg_sidebar, true, false);
            ren.drawText(px + 2, py + 3, "Quit without saving?", theme.fg_primary, theme.bg_sidebar, false, false);

            const palette = primitives.Palette{ .fg = theme.fg_secondary, .bg = theme.bg_sidebar, .accent_fg = theme.fg_primary, .accent_bg = theme.bg_accent, .muted_fg = theme.fg_secondary };
            (primitives.Button{ .rect = .{ .x = px + 3, .y = py + 5, .w = 8, .h = 1 }, .state = if (self.popup_btn_idx == 0) .focused else .normal }).draw(ren, "Yes", palette);
            (primitives.Button{ .rect = .{ .x = px + 15, .y = py + 5, .w = 8, .h = 1 }, .state = if (self.popup_btn_idx == 1) .focused else .normal }).draw(ren, "No", palette);
        } else if (self.duplicate_warning) {
            const warning = primitives.Modal.centered(screen_w, screen_h, 40, 7, 0);
            const px = warning.rect.x;
            const py = warning.rect.y;
            primitives.drawModalFrame(ren, warning, .rounded, theme.fg_primary, theme.bg_sidebar, theme.border_color, theme.bg_editor);

            ren.drawText(px + 2, py + 1, " Duplicate Keybinding ", theme.fg_secondary, theme.bg_sidebar, true, false);
            ren.drawText(px + 2, py + 3, "This key is already in use!", theme.fg_primary, theme.bg_sidebar, false, false);
            (primitives.Button{ .rect = .{ .x = px + 14, .y = py + 5, .w = 8, .h = 1 }, .state = .focused }).draw(ren, "OK", .{ .fg = theme.fg_secondary, .bg = theme.bg_sidebar, .accent_fg = theme.fg_primary, .accent_bg = theme.bg_accent, .muted_fg = theme.fg_secondary });
        }

        if (self.selected_plugin) |p| {
            const plugin_modal = primitives.Modal.centered(screen_w, screen_h, 50, 12, 0);
            const px = plugin_modal.rect.x;
            const py = plugin_modal.rect.y;
            const pw = plugin_modal.rect.w;
            const ph = plugin_modal.rect.h;
            primitives.drawModalFrame(ren, plugin_modal, .rounded, theme.fg_primary, theme.bg_sidebar, theme.border_color, theme.bg_editor);

            var title_buf: [64]u8 = undefined;
            const title_str = std.fmt.bufPrint(&title_buf, " {s} ", .{p.name}) catch " Plugin Info ";
            ren.drawText(px + 2, py, title_str, theme.fg_accent, theme.bg_sidebar, true, false);

            ren.drawText(px + 2, py + 2, p.full_name, theme.fg_primary, theme.bg_sidebar, true, false);

            var stars_buf: [32]u8 = undefined;
            const stars_str = if (self.config.nerd_fonts)
                std.fmt.bufPrint(&stars_buf, "󰓎 {d} stars", .{p.stars}) catch "Stars"
            else
                std.fmt.bufPrint(&stars_buf, "★ {d} stars", .{p.stars}) catch "Stars";
            ren.drawText(px + 2, py + 3, stars_str, .{ .rgb = .{ .r = 250, .g = 200, .b = 20 } }, theme.bg_sidebar, false, false);

            var desc_y = py + 5;
            var start_char: usize = 0;
            while (start_char < p.description.len and desc_y < py + ph - 3) {
                const end_char = @min(p.description.len, start_char + 44);
                ren.drawText(px + 2, desc_y, p.description[start_char..end_char], theme.fg_secondary, theme.bg_sidebar, false, false);
                start_char = end_char;
                desc_y += 1;
            }

            const palette = primitives.Palette{ .fg = theme.fg_secondary, .bg = theme.bg_sidebar, .accent_fg = theme.fg_primary, .accent_bg = theme.bg_accent, .muted_fg = theme.fg_secondary };
            (primitives.Button{ .rect = .{ .x = px + 3, .y = py + ph - 2, .w = 22, .h = 1 }, .state = if (self.popup_btn_idx == 0) .focused else .normal }).draw(ren, "Edit Configuration", palette);
            (primitives.Button{ .rect = .{ .x = px + pw - 14, .y = py + ph - 2, .w = 10, .h = 1 }, .state = if (self.popup_btn_idx == 1) .focused else .normal }).draw(ren, "Close", palette);
        }
    }

    pub fn handleKey(self: *SettingsWidget, key: []const u8) bool {
        if (self.selected_plugin) |p| {
            if (std.mem.eql(u8, key, "<Esc>") or std.mem.eql(u8, key, "q")) {
                self.selected_plugin = null;
                return true;
            }
            if (std.mem.eql(u8, key, "h") or std.mem.eql(u8, key, "<Left>") or std.mem.eql(u8, key, "l") or std.mem.eql(u8, key, "<Right>") or std.mem.eql(u8, key, "<Tab>")) {
                self.popup_btn_idx = (self.popup_btn_idx + 1) % 2;
                return true;
            }
            if (std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "<CR>") or std.mem.eql(u8, key, "<Space>")) {
                if (self.popup_btn_idx == 0) {
                    self.editConfig(p) catch {};
                } else {
                    self.selected_plugin = null;
                }
                return true;
            }
            return true;
        }

        if (self.popup_active) {
            if (std.mem.eql(u8, key, "<Esc>")) {
                self.popup_active = false;
                return true;
            }
            return false;
        }

        if (self.active_dropdown != .none) {
            if (std.mem.eql(u8, key, "<Esc>")) {
                self.active_dropdown = .none;
                return true;
            }
            const items_len = switch (self.active_dropdown) {
                .theme => self.themes.items.len,
                .indent_size => supported_indents.len,
                .indent_type => supported_indent_types.len,
                .line_numbers => supported_line_nums.len,
                .colorcolumn => supported_colorcolumns.len,
                .split_separator => supported_split_seps.len,
                .mode => supported_modes.len,
                .none => 0,
            };
            if (std.mem.eql(u8, key, "j") or std.mem.eql(u8, key, "<Down>")) {
                if (self.hover_dropdown_idx < items_len - 1) {
                    var next_idx = self.hover_dropdown_idx + 1;
                    if (self.active_dropdown == .theme) {
                        while (next_idx < items_len and std.mem.startsWith(u8, self.themes.items[next_idx], "---")) : (next_idx += 1) {}
                    }
                    if (next_idx < items_len) {
                        self.hover_dropdown_idx = next_idx;
                        if (self.active_dropdown == .theme) {
                            if (self.hover_dropdown_idx >= self.dropdown_scroll_offset + max_visible_themes) {
                                self.dropdown_scroll_offset = self.hover_dropdown_idx - (max_visible_themes - 1);
                            }
                        }
                    }
                }
                return true;
            } else if (std.mem.eql(u8, key, "k") or std.mem.eql(u8, key, "<Up>")) {
                if (self.hover_dropdown_idx > 0) {
                    var prev_idx = self.hover_dropdown_idx - 1;
                    if (self.active_dropdown == .theme) {
                        while (prev_idx > 0 and std.mem.startsWith(u8, self.themes.items[prev_idx], "---")) : (prev_idx -= 1) {}
                        if (std.mem.startsWith(u8, self.themes.items[prev_idx], "---")) {
                            return true;
                        }
                    }
                    self.hover_dropdown_idx = prev_idx;
                    if (self.active_dropdown == .theme) {
                        if (self.hover_dropdown_idx < self.dropdown_scroll_offset) {
                            self.dropdown_scroll_offset = self.hover_dropdown_idx;
                        }
                    }
                }
                return true;
            } else if (std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "<CR>") or std.mem.eql(u8, key, "o") or std.mem.eql(u8, key, "<Space>")) {
                const idx = self.hover_dropdown_idx;
                if (self.active_dropdown == .theme) {
                    const t = self.themes.items[idx];
                    if (!std.mem.startsWith(u8, t, "---")) {
                        self.allocator.free(self.config.theme);
                        self.config.theme = self.allocator.dupe(u8, t) catch self.config.theme;
                        self.has_unsaved_changes = true;
                        self.active_dropdown = .none;
                    }
                    return true;
                } else if (self.active_dropdown == .split_separator) {
                    self.allocator.free(self.config.split_separator);
                    self.config.split_separator = self.allocator.dupe(u8, supported_split_seps[idx]) catch self.config.split_separator;
                } else if (self.active_dropdown == .indent_size) {
                    self.config.indent_size = supported_indents[idx];
                } else if (self.active_dropdown == .indent_type) {
                    self.config.use_tabs = std.mem.eql(u8, supported_indent_types[idx], "tabs");
                } else if (self.active_dropdown == .line_numbers) {
                    self.allocator.free(self.config.line_numbers);
                    self.config.line_numbers = self.allocator.dupe(u8, supported_line_nums[idx]) catch self.config.line_numbers;
                } else if (self.active_dropdown == .colorcolumn) {
                    self.allocator.free(self.config.colorcolumn);
                    self.config.colorcolumn = self.allocator.dupe(u8, supported_colorcolumns[idx]) catch self.config.colorcolumn;
                } else if (self.active_dropdown == .mode) {
                    self.allocator.free(self.config.mode);
                    self.config.mode = self.allocator.dupe(u8, supported_modes[idx]) catch self.config.mode;
                }
                self.has_unsaved_changes = true;
                self.active_dropdown = .none;
                return true;
            }
            return false;
        }

        if (self.duplicate_warning) {
            if (std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "<CR>") or std.mem.eql(u8, key, "<Esc>")) {
                self.duplicate_warning = false;
                return true;
            }
            return true;
        }

        if (self.active_binding) |idx| {
            if (std.mem.eql(u8, key, "<Esc>")) {
                self.active_binding = null;
                return true;
            }

            var binding: Keybindings.Field = undefined;
            inline for (binding_fields, 0..) |field, i| {
                if (idx == i) binding = @field(Keybindings.Field, field);
            }
            const is_duplicate = self.config.keybindings.conflict(binding, key);

            if (is_duplicate) {
                self.duplicate_warning = true;
                self.active_binding = null;
                return true;
            }

            const duped = self.allocator.dupe(u8, key) catch return true;
            self.allocator.free(self.config.keybindings.get(binding));
            self.config.keybindings.ptr(binding).* = duped;

            self.active_binding = null;
            self.has_unsaved_changes = true;
            return true;
        }

        if (std.mem.eql(u8, key, "<C-s>") or std.mem.eql(u8, key, "\x13")) {
            return self.saveAndClose();
        }

        if (self.keyboard_focus == .tabs) {
            if (std.mem.eql(u8, key, "j") or std.mem.eql(u8, key, "<Down>")) {
                if (self.active_tab + 1 < tabs.len) {
                    self.active_tab += 1;
                    self.hover_row = 0;
                }
                return true;
            } else if (std.mem.eql(u8, key, "k") or std.mem.eql(u8, key, "<Up>")) {
                if (self.active_tab > 0) {
                    self.active_tab -= 1;
                    self.hover_row = 0;
                }
                return true;
            } else if (std.mem.eql(u8, key, "l") or std.mem.eql(u8, key, "<Right>") or std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "<CR>")) {
                self.keyboard_focus = .content;
                self.hover_row = 0;
                return true;
            }
        } else if (self.keyboard_focus == .content) {
            if (self.active_tab == 4 and (std.mem.eql(u8, key, "v") or std.mem.eql(u8, key, "p"))) {
                var updated = self.config;
                const preset: Keybindings = if (std.mem.eql(u8, key, "v"))
                    .{ .toggle_explorer = "<M-e>", .toggle_terminal = "<M-t>", .new_file = "<M-n>", .find_file = "<M-p>", .search_project = "<M-g>" }
                else
                    .{ .toggle_explorer = "<C-b>" };
                inline for (binding_fields) |field| @field(updated.keybindings, field) = @field(preset, field);
                inline for (binding_fields) |field| {
                    if (updated.keybindings.conflict(@field(Keybindings.Field, field), @field(updated.keybindings, field))) {
                        self.duplicate_warning = true;
                        return true;
                    }
                }
                const owned = SettingsConfig.ownStrings(self.allocator, updated) catch return true;
                self.config.deinit(self.allocator);
                self.config = owned;
                self.has_unsaved_changes = true;
                return true;
            }
            if (self.active_tab == 4 and std.mem.eql(u8, key, "r")) {
                inline for (binding_fields, 0..) |field, i| {
                    if (self.hover_row == i) {
                        self.active_binding = i;
                        return self.handleKey(@field(Keybindings{}, field));
                    }
                }
            }
            if (std.mem.eql(u8, key, "h") or std.mem.eql(u8, key, "<Left>") or std.mem.eql(u8, key, "<Esc>")) {
                self.keyboard_focus = .tabs;
                return true;
            }

            const max_items: usize = switch (self.active_tab) {
                0 => 4,
                1 => 3,
                2 => 5,
                3 => 3,
                4 => binding_fields.len,
                5 => 1,
                else => 0,
            };

            if (std.mem.eql(u8, key, "j") or std.mem.eql(u8, key, "<Down>")) {
                if (self.hover_row < max_items - 1) {
                    self.hover_row += 1;
                    if (self.active_tab == 3 and self.hover_row >= 2) {
                        const plugin_idx = self.hover_row - 2;
                        if (plugin_idx >= self.plugin_scroll_offset + 6) {
                            self.plugin_scroll_offset = plugin_idx - 5;
                        }
                    }
                }
                return true;
            } else if (std.mem.eql(u8, key, "k") or std.mem.eql(u8, key, "<Up>")) {
                if (self.hover_row > 0) {
                    self.hover_row -= 1;
                    if (self.active_tab == 3 and self.hover_row >= 2) {
                        const plugin_idx = self.hover_row - 2;
                        if (plugin_idx < self.plugin_scroll_offset) {
                            self.plugin_scroll_offset = plugin_idx;
                        }
                    }
                }
                return true;
            } else if (std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "<CR>") or std.mem.eql(u8, key, "o") or std.mem.eql(u8, key, "<Space>")) {
                if (self.active_tab == 0) {
                    if (self.hover_row == 0) self.config.clip = !self.config.clip;
                    if (self.hover_row == 1) {
                        self.active_dropdown = .mode;
                        self.hover_dropdown_idx = 0;
                        self.dropdown_scroll_offset = 0;
                    }
                    if (self.hover_row == 2) self.config.autocomplete = !self.config.autocomplete;
                    if (self.hover_row == 3) self.config.autoindent = !self.config.autoindent;
                } else if (self.active_tab == 1) {
                    if (self.hover_row == 0) {
                        self.openThemeDropdown();
                    }
                    if (self.hover_row == 1) {
                        self.active_dropdown = .split_separator;
                        self.hover_dropdown_idx = 0;
                        self.dropdown_scroll_offset = 0;
                    }
                    if (self.hover_row == 2) self.config.nerd_fonts = !self.config.nerd_fonts;
                } else if (self.active_tab == 2) {
                    if (self.hover_row == 0) {
                        self.active_dropdown = .indent_type;
                        self.hover_dropdown_idx = 0;
                        self.dropdown_scroll_offset = 0;
                    }
                    if (self.hover_row == 1) {
                        self.active_dropdown = .indent_size;
                        self.hover_dropdown_idx = 0;
                        self.dropdown_scroll_offset = 0;
                    }
                    if (self.hover_row == 2) self.config.wrap = !self.config.wrap;
                    if (self.hover_row == 3) {
                        self.active_dropdown = .line_numbers;
                        self.hover_dropdown_idx = 0;
                        self.dropdown_scroll_offset = 0;
                    }
                    if (self.hover_row == 4) {
                        self.active_dropdown = .colorcolumn;
                        self.hover_dropdown_idx = 0;
                        self.dropdown_scroll_offset = 0;
                    }
                } else if (self.active_tab == 3) {
                    if (self.hover_row == 0) self.open_mason = true;
                    if (self.hover_row == 1) self.open_lazy = true;
                    if (self.hover_row == 2) self.open_installed = true;
                } else if (self.active_tab == 4) {
                    self.active_binding = self.hover_row;
                    return true;
                } else if (self.active_tab == 5) {
                    if (self.software_update_status != .running) self.software_update_requested = true;
                    return true;
                }
                self.has_unsaved_changes = true;
                return true;
            }
        }

        if (std.mem.eql(u8, key, "<Esc>")) {
            if (self.has_unsaved_changes) {
                self.popup_active = true;
            } else {
                self.is_open = false;
            }
            return true;
        }
        return false;
    }

    fn saveAndClose(self: *SettingsWidget) bool {
        if (self.has_unsaved_changes) {
            self.config.save(self.settings_path) catch {
                self.save_failed = true;
                return true;
            };
            self.save_failed = false;
            self.has_unsaved_changes = false;
            self.needs_apply = true;
        }
        self.is_open = false;
        return true;
    }

    pub fn handleMouse(self: *SettingsWidget, m: input.MouseEvent, screen_w: u16, screen_h: u16) bool {
        if (!self.is_open) return false;

        const mx = m.col;
        const my = m.row;

        if (self.selected_plugin) |p| {
            const plugin_modal = primitives.Modal.centered(screen_w, screen_h, 50, 12, 0);
            const px = plugin_modal.rect.x;
            const py = plugin_modal.rect.y;
            const pw = plugin_modal.rect.w;
            const ph = plugin_modal.rect.h;

            if (plugin_modal.contains(mx, my)) {
                if (my == py + ph - 2) {
                    if ((primitives.Button{ .rect = .{ .x = px + 3, .y = py + ph - 2, .w = 22, .h = 1 } }).hit(mx, my)) {
                        self.editConfig(p) catch {};
                    } else if ((primitives.Button{ .rect = .{ .x = px + pw - 14, .y = py + ph - 2, .w = 10, .h = 1 } }).hit(mx, my)) {
                        self.selected_plugin = null;
                    }
                }
            } else {
                self.selected_plugin = null;
            }
            return true;
        }

        if (self.duplicate_warning) {
            self.duplicate_warning = false;
            return true;
        }

        if (self.active_binding != null) {
            self.active_binding = null;
            return true;
        }

        if (self.popup_active) {
            const popup = primitives.Modal.centered(screen_w, screen_h, 30, 7, 0);
            const px = popup.rect.x;
            const py = popup.rect.y;

            if (popup.contains(mx, my)) {
                if (my == py + 5) {
                    if ((primitives.Button{ .rect = .{ .x = px + 3, .y = py + 5, .w = 8, .h = 1 } }).hit(mx, my)) {
                        const old_cfg = self.config;
                        if (SettingsConfig.load(self.allocator, self.settings_path)) |new_cfg| {
                            self.config = new_cfg;
                            self.allocator.free(old_cfg.theme);
                            self.allocator.free(old_cfg.line_numbers);
                            self.allocator.free(old_cfg.colorcolumn);
                            self.allocator.free(old_cfg.split_separator);
                            self.allocator.free(old_cfg.mode);
                            old_cfg.keybindings.deinit(self.allocator);
                        } else |_| {}
                        self.has_unsaved_changes = false;
                        self.popup_active = false;
                        self.is_open = false;
                    } else if ((primitives.Button{ .rect = .{ .x = px + 15, .y = py + 5, .w = 8, .h = 1 } }).hit(mx, my)) {
                        self.popup_active = false;
                    }
                }
                return true;
            }
            // Consume clicks outside the popup so they don't hit settings
            return true;
        }

        const content_x = (screen_w -| @min(80, screen_w -| 10)) / 2 + 22;
        const content_y = (screen_h -| @min(24, screen_h -| 10)) / 2 + 2;

        if (self.active_dropdown != .none) {
            const drop_x = content_x + 10;
            var drop_y = content_y + 3;
            var items_len: usize = 0;
            var drop_w: u16 = 20;

            if (self.active_dropdown == .theme) {
                items_len = self.themes.items.len;
                drop_w = 32;
                drop_y = content_y + 3;
            } else if (self.active_dropdown == .split_separator) {
                items_len = supported_split_seps.len;
                drop_y = content_y + 5;
            } else if (self.active_dropdown == .indent_size) {
                items_len = supported_indents.len;
                drop_y = content_y + 5;
            } else if (self.active_dropdown == .indent_type) {
                items_len = supported_indent_types.len;
                drop_y = content_y + 3;
            } else if (self.active_dropdown == .line_numbers) {
                items_len = supported_line_nums.len;
                drop_y = content_y + 9;
            } else if (self.active_dropdown == .colorcolumn) {
                items_len = supported_colorcolumns.len;
                drop_y = content_y + 11;
            } else if (self.active_dropdown == .mode) {
                items_len = supported_modes.len;
                drop_w = 16;
                drop_y = content_y + 5;
            }

            const max_visible = if (self.active_dropdown == .theme) @min(items_len, 8) else items_len;
            const drop_h = @as(u16, @intCast(max_visible)) + 2;

            if (m.button == .wheel_up or m.button == .wheel_down) {
                if (self.active_dropdown == .theme and
                    mx >= drop_x and mx < drop_x + drop_w and
                    my >= drop_y and my < drop_y + drop_h)
                {
                    scrollThemeList(
                        self.themes.items,
                        &self.hover_dropdown_idx,
                        &self.dropdown_scroll_offset,
                        m.button == .wheel_down,
                    );
                }
                return true;
            }

            if (mx >= drop_x and mx < drop_x + drop_w and my > drop_y and my < drop_y + drop_h - 1) {
                const click_offset = my - drop_y - 1;
                const idx = if (self.active_dropdown == .theme) self.dropdown_scroll_offset + click_offset else click_offset;
                var changed = false;
                if (self.active_dropdown == .theme) {
                    if (idx < self.themes.items.len) {
                        const t = self.themes.items[idx];
                        if (!std.mem.startsWith(u8, t, "---")) {
                            const new_theme = self.allocator.dupe(u8, t) catch return true;
                            self.allocator.free(self.config.theme);
                            self.config.theme = new_theme;
                            changed = true;
                        }
                    }
                } else if (self.active_dropdown == .split_separator) {
                    if (idx < supported_split_seps.len) {
                        const new_sep = self.allocator.dupe(u8, supported_split_seps[idx]) catch return true;
                        self.allocator.free(self.config.split_separator);
                        self.config.split_separator = new_sep;
                        changed = true;
                    }
                } else if (self.active_dropdown == .indent_size) {
                    if (idx < supported_indents.len) {
                        self.config.indent_size = supported_indents[idx];
                        changed = true;
                    }
                } else if (self.active_dropdown == .indent_type) {
                    if (idx < supported_indent_types.len) {
                        self.config.use_tabs = std.mem.eql(u8, supported_indent_types[idx], "tabs");
                        changed = true;
                    }
                } else if (self.active_dropdown == .line_numbers) {
                    if (idx < supported_line_nums.len) {
                        const new_ln = self.allocator.dupe(u8, supported_line_nums[idx]) catch return true;
                        self.allocator.free(self.config.line_numbers);
                        self.config.line_numbers = new_ln;
                        changed = true;
                    }
                } else if (self.active_dropdown == .colorcolumn) {
                    if (idx < supported_colorcolumns.len) {
                        const new_column = self.allocator.dupe(u8, supported_colorcolumns[idx]) catch return true;
                        self.allocator.free(self.config.colorcolumn);
                        self.config.colorcolumn = new_column;
                        changed = true;
                    }
                } else if (self.active_dropdown == .mode) {
                    if (idx < supported_modes.len) {
                        const new_mode = self.allocator.dupe(u8, supported_modes[idx]) catch return true;
                        self.allocator.free(self.config.mode);
                        self.config.mode = new_mode;
                        self.config.zen = std.mem.eql(u8, self.config.mode, "zen");
                        self.config.ide = std.mem.eql(u8, self.config.mode, "ide");
                        changed = true;
                    }
                }

                if (changed) {
                    self.has_unsaved_changes = true;
                }
            }
            // Any click while dropdown is open closes the dropdown (and consumes the click)
            self.active_dropdown = .none;
            return true;
        }

        const modal = primitives.Modal.centered(screen_w, screen_h, 80, 24, 5);
        const x = modal.rect.x;
        const y = modal.rect.y;
        const w = modal.rect.w;
        const h = modal.rect.h;

        if (!primitives.usable(modal, 50, 18)) {
            self.is_open = false;
            return true;
        }

        if (modal.contains(mx, my)) {
            // Close button
            if (primitives.containsRect(modal.closeButton(), mx, my)) {
                if (self.has_unsaved_changes) {
                    self.popup_active = true;
                } else {
                    self.is_open = false;
                }
                return true;
            }

            // Save button
            const save_button = primitives.Button{ .rect = .{ .x = x + w - 18, .y = y + h - 2, .w = 16, .h = 1 } };
            if (save_button.hit(mx, my)) {
                return self.saveAndClose();
            }

            // Tabs
            if (mx >= x + 1 and mx < x + 20) {
                var tab_y: u16 = y + 2;
                for (tabs, 0..) |_, idx| {
                    if (my >= tab_y and my < tab_y + 2) {
                        self.active_tab = idx;
                        return true;
                    }
                    tab_y += 2;
                }
            }

            // Interactive toggles
            if (mx >= content_x) {
                var changed = false;
                switch (self.active_tab) {
                    0 => {
                        if (my == content_y + 2) {
                            self.config.clip = !self.config.clip;
                            changed = true;
                        } else if (my == content_y + 4) {
                            self.active_dropdown = .mode;
                            self.hover_dropdown_idx = 0;
                            self.dropdown_scroll_offset = 0;
                        } else if (my == content_y + 6) {
                            self.config.autocomplete = !self.config.autocomplete;
                            changed = true;
                        } else if (my == content_y + 8) {
                            self.config.autoindent = !self.config.autoindent;
                            changed = true;
                        }
                    },
                    1 => {
                        if (my == content_y + 2) {
                            self.openThemeDropdown();
                        } else if (my == content_y + 4) {
                            self.active_dropdown = .split_separator;
                            self.hover_dropdown_idx = 0;
                            self.dropdown_scroll_offset = 0;
                        } else if (my == content_y + 10) {
                            self.active_dropdown = .colorcolumn;
                            self.hover_dropdown_idx = 0;
                            self.dropdown_scroll_offset = 0;
                        } else if (my == content_y + 6) {
                            self.config.nerd_fonts = !self.config.nerd_fonts;
                            changed = true;
                        }
                    },
                    2 => {
                        if (my == content_y + 2) {
                            self.active_dropdown = .indent_type;
                            self.hover_dropdown_idx = 0;
                            self.dropdown_scroll_offset = 0;
                        } else if (my == content_y + 4) {
                            self.active_dropdown = .indent_size;
                            self.hover_dropdown_idx = 0;
                            self.dropdown_scroll_offset = 0;
                        } else if (my == content_y + 6) {
                            self.config.wrap = !self.config.wrap;
                            changed = true;
                        } else if (my == content_y + 8) {
                            self.active_dropdown = .line_numbers;
                            self.hover_dropdown_idx = 0;
                            self.dropdown_scroll_offset = 0;
                        }
                    },
                    3 => {
                        if (my == content_y + 2) {
                            self.open_mason = true;
                        } else if (my == content_y + 4) {
                            self.open_lazy = true;
                        } else if (my == content_y + 6) {
                            self.open_installed = true;
                        }
                    },
                    4 => {
                        if (my == content_y + 13) {
                            self.keyboard_focus = .content;
                            return self.handleKey(if (mx < content_x + 13) "v" else if (mx < content_x + 26) "p" else "r");
                        }
                        for (0..binding_fields.len) |i| {
                            if (my == content_y + 2 + @as(u16, @intCast(i))) {
                                self.hover_row = i;
                                self.active_binding = i;
                                changed = true;
                            }
                        }
                    },
                    5 => {
                        const update_button = primitives.Button{ .rect = .{ .x = content_x, .y = content_y + 6, .w = 28, .h = 1 } };
                        if (update_button.hit(mx, my) and self.software_update_status != .running) {
                            self.software_update_requested = true;
                        }
                    },
                    else => {},
                }
                if (changed) {
                    self.has_unsaved_changes = true;
                }
            }
            return true; // ALWAYS consume the click if it's inside the window!
        }
        return false;
    }
};

test "saved command shortcuts reject conflicts and preserve live state on failed saves" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/settings.json", .{tmp.sub_path});
    defer allocator.free(path);
    const missing_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/missing/settings.json", .{tmp.sub_path});
    defer allocator.free(missing_path);
    var config = try SettingsConfig.ownedDefaults(allocator);
    defer config.deinit(allocator);
    try config.saveBinding(allocator, path, .close_buffer, "<C-k>");
    try config.saveBinding(allocator, path, .switch_buffers, "<F4>");
    try std.testing.expectError(error.DuplicateShortcut, config.saveBinding(allocator, path, .save_file, "<C-k>"));
    try std.testing.expectError(error.DuplicateShortcut, config.saveBinding(allocator, path, .close_buffer, "<F1>"));
    try std.testing.expectError(error.FileNotFound, config.saveBinding(allocator, missing_path, .close_buffer, "<F3>"));
    try std.testing.expectEqualStrings("<C-k>", config.keybindings.close_buffer);
    try std.testing.expectEqualStrings("<C-s>", config.keybindings.save_file);
    var loaded = try SettingsConfig.load(allocator, path);
    defer loaded.deinit(allocator);
    try std.testing.expectEqualStrings("<C-k>", loaded.keybindings.close_buffer);
    try std.testing.expectEqualStrings("<F4>", loaded.keybindings.switch_buffers);
}

test "settings roundtrip preserves canonical mode defaults" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/settings.json", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    var config = SettingsConfig{};
    try config.save(path);
    var loaded = try SettingsConfig.load(std.testing.allocator, path);
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("normal", loaded.mode);
    try std.testing.expect(!loaded.ide);
    try std.testing.expect(!loaded.zen);
    try std.testing.expect(!loaded.zen_handoff);
    try std.testing.expect(loaded.nerd_fonts);
    try std.testing.expectEqualStrings("", loaded.colorcolumn);
}

test "legacy Ctrl+Z Zen binding migrates to F11" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/settings.json", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    var legacy = SettingsConfig{};
    legacy.keybindings.toggle_zen = "<C-z>";
    try legacy.save(path);

    var loaded = try SettingsConfig.load(std.testing.allocator, path);
    defer loaded.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("<F11>", loaded.keybindings.toggle_zen);
}

test "settings migrations are deterministic and idempotent" {
    var legacy = SettingsConfig{ .version = 0, .zen = true, .ide = true, .mode = "normal" };
    legacy.keybindings.toggle_zen = "<C-z>";

    const first = try SettingsConfig.migrateToCurrent(legacy, 0);
    const second = try SettingsConfig.migrateToCurrent(first, first.version);
    const repeated = try SettingsConfig.migrateToCurrent(legacy, 0);

    try std.testing.expectEqual(SettingsConfig.current_version, first.version);
    try std.testing.expectEqualStrings("zen", first.mode);
    try std.testing.expect(first.zen);
    try std.testing.expect(!first.ide);
    try std.testing.expectEqualStrings("<F11>", first.keybindings.toggle_zen);
    try std.testing.expectEqualDeep(first, second);
    try std.testing.expectEqualDeep(first, repeated);
}

test "legacy ide boolean migrates to canonical mode" {
    const migrated = try SettingsConfig.migrateToCurrent(.{ .version = 0, .ide = true }, 0);
    try std.testing.expectEqualStrings("ide", migrated.mode);
    try std.testing.expect(migrated.ide);
    try std.testing.expect(!migrated.zen);
}

test "corrupt and truncated settings preserve source and widget uses defaults" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const data_dir = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer std.testing.allocator.free(data_dir);
    const path = try std.fs.path.join(std.testing.allocator, &.{ data_dir, "settings.json" });
    defer std.testing.allocator.free(path);

    for ([_][]const u8{ "not-json", "{\"version\":1,\"theme\":\"broken" }, [_]anyerror{ error.SyntaxError, error.UnexpectedEndOfInput }) |invalid, expected_error| {
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = invalid });
        try std.testing.expectError(expected_error, SettingsConfig.load(std.testing.allocator, path));

        var widget = SettingsWidget.init(std.testing.allocator, path, std.testing.io, data_dir);
        defer widget.deinit();
        try std.testing.expect(widget.load_failed);
        try std.testing.expectEqualStrings("vscode", widget.config.theme);

        const preserved = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(SettingsConfig.max_document_bytes));
        defer std.testing.allocator.free(preserved);
        try std.testing.expectEqualStrings(invalid, preserved);
    }
}

test "oversized settings are rejected without modification" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/settings.json", .{tmp.sub_path});
    defer std.testing.allocator.free(path);
    const oversized = try std.testing.allocator.alloc(u8, SettingsConfig.max_document_bytes + 1);
    defer std.testing.allocator.free(oversized);
    @memset(oversized, 'x');
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = oversized });

    try std.testing.expectError(error.SettingsDocumentTooLarge, SettingsConfig.load(std.testing.allocator, path));
    const stat = try std.Io.Dir.cwd().statFile(std.testing.io, path, .{});
    try std.testing.expectEqual(@as(u64, oversized.len), stat.size);
}

test "unknown fields load but future schemas are left intact" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/settings.json", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    const with_unknown = "{\"version\":1,\"theme\":\"nord\",\"ui_v2_future_field\":{\"kept\":true}}";
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = with_unknown });
    var loaded = try SettingsConfig.load(std.testing.allocator, path);
    defer loaded.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("nord", loaded.theme);

    const future = "{\"version\":2,\"ui_v2_future_field\":true}";
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = future });
    try std.testing.expectError(error.UnsupportedSettingsVersion, SettingsConfig.load(std.testing.allocator, path));
    const preserved = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(SettingsConfig.max_document_bytes));
    defer std.testing.allocator.free(preserved);
    try std.testing.expectEqualStrings(future, preserved);
}

test "atomic save failure leaves old or new valid primary and cleans temporaries" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/settings.json", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    var old = SettingsConfig{ .theme = "kanagawa" };
    try old.save(path);
    var replacement = SettingsConfig{ .theme = "nord" };
    const failure_points = [_]SettingsConfig.SaveFailurePoint{ .after_create, .after_write, .after_sync, .before_replace, .after_replace };
    for (failure_points) |point| {
        try std.testing.expectError(error.InjectedSaveFailure, replacement.saveWithFailure(path, point));
        var loaded = try SettingsConfig.load(std.testing.allocator, path);
        defer loaded.deinit(std.testing.allocator);
        try std.testing.expect(std.mem.eql(u8, loaded.theme, "kanagawa") or std.mem.eql(u8, loaded.theme, "nord"));
        old.theme = loaded.theme;
    }

    var dir = try std.Io.Dir.cwd().openDir(std.testing.io, std.fs.path.dirname(path).?, .{ .iterate = true });
    defer dir.close(std.testing.io);
    var iterator = dir.iterate();
    while (try iterator.next(std.testing.io)) |entry|
        try std.testing.expect(std.mem.indexOf(u8, entry.name, ".tmp.") == null);
}

test "software updater uses the official release installer" {
    try std.testing.expect(std.mem.indexOf(u8, SettingsWidget.software_updater, "https://raw.githubusercontent.com/Rouboufy/tuim/main/setup.sh") != null);
    try std.testing.expect(std.mem.indexOf(u8, SettingsWidget.software_updater, "--no-plugins") != null);
    try std.testing.expect(std.mem.indexOf(u8, SettingsWidget.software_updater, "${APPIMAGE:-}") != null);
    try std.testing.expect(std.mem.indexOf(u8, SettingsWidget.software_updater, "Tuim-linux-x86_64.AppImage") != null);
    try std.testing.expect(std.mem.indexOf(u8, SettingsWidget.software_updater, "SHA256SUMS") != null);
    try std.testing.expect(std.mem.indexOf(u8, SettingsWidget.software_updater, "success") != null);
    try std.testing.expect(std.mem.indexOf(u8, SettingsWidget.software_updater, "failure") != null);
    try std.testing.expect(std.mem.indexOf(u8, SettingsWidget.software_updater, "progress_file") != null);
    try std.testing.expect(std.mem.indexOf(u8, SettingsWidget.software_updater, "TUIM_UPDATE_PROGRESS_FILE") != null);
}

test "software updater polls and clamps atomic progress state" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const data_dir = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer std.testing.allocator.free(data_dir);
    const settings_path = try std.fs.path.join(std.testing.allocator, &.{ data_dir, "settings.json" });
    defer std.testing.allocator.free(settings_path);
    const progress_path = try std.fs.path.join(std.testing.allocator, &.{ data_dir, "software-update.progress" });
    defer std.testing.allocator.free(progress_path);

    var widget = SettingsWidget.init(std.testing.allocator, settings_path, std.testing.io, data_dir);
    defer widget.deinit();
    widget.software_update_status = .running;

    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = progress_path, .data = "63\n" });
    widget.pollSoftwareUpdateProgress();
    try std.testing.expectEqual(@as(u8, 63), widget.software_update_progress);

    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = progress_path, .data = "250\n" });
    widget.pollSoftwareUpdateProgress();
    try std.testing.expectEqual(@as(u8, 100), widget.software_update_progress);
}

test "system theme stays available once when installed themes refresh" {
    var widget = SettingsWidget.init(std.testing.allocator, "/tmp/tuim-no-system-theme-settings.json", std.testing.io, "/tmp");
    defer widget.deinit();
    try widget.setThemesAndGroup(&.{ "default", "system", "custom" });
    try std.testing.expectEqualStrings("system", widget.themes.items[1]);
    var count: usize = 0;
    for (widget.themes.items) |name| {
        if (std.mem.eql(u8, name, "system")) count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), count);
    try widget.setThemesAndGroup(&.{});
    try std.testing.expectEqualStrings("system", widget.themes.items[1]);
}

test "theme dropdown mouse scrolling keeps the highlight visible" {
    const themes = [_][]const u8{
        "--- Tuim Themes ---",
        "vscode",
        "kanagawa",
        "nord",
        "gruvbox",
        "rose-pine",
        "--- Installed ---",
        "custom-one",
        "custom-two",
        "custom-three",
        "custom-four",
    };
    var hover_idx: usize = 1;
    var scroll_offset: usize = 0;

    scrollThemeList(&themes, &hover_idx, &scroll_offset, true);
    try std.testing.expectEqual(@as(usize, 1), scroll_offset);
    try std.testing.expectEqual(@as(usize, 1), hover_idx);

    scrollThemeList(&themes, &hover_idx, &scroll_offset, true);
    try std.testing.expectEqual(@as(usize, 2), scroll_offset);
    try std.testing.expectEqual(@as(usize, 2), hover_idx);

    hover_idx = 10;
    scroll_offset = 3;
    scrollThemeList(&themes, &hover_idx, &scroll_offset, false);
    try std.testing.expectEqual(@as(usize, 2), scroll_offset);
    try std.testing.expectEqual(@as(usize, 9), hover_idx);
}
