const std = @import("std");
const renderer = @import("../renderer.zig");
const Color = renderer.Color;
const Rect = @import("../layout.zig").Rect;
const msgpack = @import("../../nvim/msgpack.zig");
const Value = msgpack.Value;
const rpc_mod = @import("../../nvim/rpc.zig");
const RpcClient = rpc_mod.RpcClient;

fn getFileIcon(name: []const u8) []const u8 {
    if (std.mem.endsWith(u8, name, ".zig")) return " ";
    if (std.mem.endsWith(u8, name, ".lua")) return " ";
    if (std.mem.endsWith(u8, name, ".py")) return " ";
    if (std.mem.endsWith(u8, name, ".md")) return " ";
    if (std.mem.endsWith(u8, name, ".js") or std.mem.endsWith(u8, name, ".ts") or std.mem.endsWith(u8, name, ".jsx") or std.mem.endsWith(u8, name, ".tsx")) return " ";
    if (std.mem.endsWith(u8, name, ".html")) return " ";
    if (std.mem.endsWith(u8, name, ".css")) return " ";
    if (std.mem.endsWith(u8, name, ".json")) return " ";
    if (std.mem.endsWith(u8, name, ".c") or std.mem.endsWith(u8, name, ".cpp") or std.mem.endsWith(u8, name, ".h") or std.mem.endsWith(u8, name, ".hpp")) return " ";
    if (std.mem.endsWith(u8, name, ".rs")) return " ";
    if (std.mem.endsWith(u8, name, ".sh")) return " ";
    if (std.mem.endsWith(u8, name, ".toml") or std.mem.endsWith(u8, name, ".yml") or std.mem.endsWith(u8, name, ".yaml") or std.mem.endsWith(u8, name, ".conf")) return " ";
    if (std.mem.endsWith(u8, name, ".txt")) return "󰈙 ";
    return "󰈔 ";
}

pub const ExplorerItem = struct {
    path: []const u8, // relative path
    name: []const u8,
    is_dir: bool,
    expanded: bool,
    depth: u16,
};

pub const ActionState = enum { none, creating_file, creating_dir, deleting, renaming };

pub const Explorer = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    expanded_dirs: std.StringHashMap(void),
    items: std.array_list.Managed(ExplorerItem),
    arena: std.heap.ArenaAllocator,

    scroll_y: usize = 0,
    selected_idx: ?usize = null,

    // File action state
    action_state: ActionState = .none,
    input_buf: [256]u8 = undefined,
    input_len: usize = 0,
    action_target_path: ?[]const u8 = null, // The directory in which to create, or file to delete

    // Context Menu State
    show_menu: bool = false,
    menu_x: u16 = 0,
    menu_y: u16 = 0,

    // Status tracking
    neovim_modified: std.StringHashMap(void),
    session_saved: std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator, io: std.Io) Explorer {
        return Explorer{
            .allocator = allocator,
            .io = io,
            .expanded_dirs = std.StringHashMap(void).init(allocator),
            .items = std.array_list.Managed(ExplorerItem).init(allocator),
            .arena = std.heap.ArenaAllocator.init(allocator),
            .action_state = .none,
            .neovim_modified = std.StringHashMap(void).init(allocator),
            .session_saved = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *Explorer) void {
        self.expanded_dirs.deinit();
        self.items.deinit();
        self.arena.deinit();

        var it_neo = self.neovim_modified.keyIterator();
        while (it_neo.next()) |k| self.allocator.free(k.*);
        self.neovim_modified.deinit();

        var it_saved = self.session_saved.keyIterator();
        while (it_saved.next()) |k| self.allocator.free(k.*);
        self.session_saved.deinit();
    }

    pub fn refresh(self: *Explorer) !void {
        self.items.clearRetainingCapacity();
        _ = self.arena.reset(.retain_capacity);

        try self.scanDir(".", 0);
    }

    pub fn refreshStatus(self: *Explorer, rpc: *RpcClient) bool {
        var changed = false;

        // 1. Refresh Neovim modified and saved buffers
        const script =
            \\local res = { modified = {}, saved = {} }
            \\for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            \\    local name = vim.api.nvim_buf_get_name(buf)
            \\    if name ~= "" then
            \\        local rel_name = vim.fn.fnamemodify(name, ':.')
            \\        if vim.api.nvim_buf_get_option(buf, 'modified') then
            \\            table.insert(res.modified, rel_name)
            \\        else
            \\            local is_saved = false
            \\            pcall(function() is_saved = vim.b[buf].tuim_session_saved end)
            \\            if is_saved then
            \\                table.insert(res.saved, rel_name)
            \\            end
            \\        end
            \\    end
            \\end
            \\return res
        ;

        var params = self.allocator.alloc(Value, 2) catch return changed;
        defer self.allocator.free(params);
        params[0] = .{ .string = script };
        params[1] = .{ .array = &[_]Value{} };

        if (rpc.call("nvim_exec_lua", params) catch null) |res| {
            defer msgpack.freeValue(res, self.allocator);
            if (res == .map) {
                var new_mod = std.StringHashMap(void).init(self.allocator);
                var new_sav = std.StringHashMap(void).init(self.allocator);

                for (res.map) |kv| {
                    if (kv.key == .string and std.mem.eql(u8, kv.key.string, "modified") and kv.value == .array) {
                        for (kv.value.array) |item| {
                            if (item == .string) new_mod.put(self.allocator.dupe(u8, item.string) catch continue, {}) catch {};
                        }
                    } else if (kv.key == .string and std.mem.eql(u8, kv.key.string, "saved") and kv.value == .array) {
                        for (kv.value.array) |item| {
                            if (item == .string) new_sav.put(self.allocator.dupe(u8, item.string) catch continue, {}) catch {};
                        }
                    }
                }

                if (new_mod.count() != self.neovim_modified.count()) changed = true;
                var it_mod = self.neovim_modified.keyIterator();
                while (it_mod.next()) |k| {
                    if (!new_mod.contains(k.*)) changed = true;
                    self.allocator.free(k.*);
                }
                self.neovim_modified.deinit();
                self.neovim_modified = new_mod;

                if (new_sav.count() != self.session_saved.count()) changed = true;
                var it_sav = self.session_saved.keyIterator();
                while (it_sav.next()) |k| {
                    if (!new_sav.contains(k.*)) changed = true;
                    self.allocator.free(k.*);
                }
                self.session_saved.deinit();
                self.session_saved = new_sav;
            }
        }

        return changed;
    }

    fn scanDir(self: *Explorer, dir_path: []const u8, depth: u16) !void {
        var dir = std.Io.Dir.cwd().openDir(self.io, dir_path, .{ .iterate = true }) catch return;
        defer dir.close(self.io);

        var iter = dir.iterate();
        const EntryInfo = struct { name: []const u8, is_dir: bool };
        var entries = std.array_list.Managed(EntryInfo).init(self.arena.allocator());

        while (try iter.next(self.io)) |entry| {
            if (std.mem.eql(u8, entry.name, ".git") or std.mem.eql(u8, entry.name, "zig-cache") or std.mem.eql(u8, entry.name, "zig-out")) continue;
            try entries.append(.{
                .name = try self.arena.allocator().dupe(u8, entry.name),
                .is_dir = entry.kind == .directory,
            });
        }

        // Sort: dirs first, then files, alphabetically
        std.sort.block(EntryInfo, entries.items, {}, struct {
            fn lessThan(_: void, a: EntryInfo, b: EntryInfo) bool {
                if (a.is_dir and !b.is_dir) return true;
                if (!a.is_dir and b.is_dir) return false;
                return std.mem.lessThan(u8, a.name, b.name);
            }
        }.lessThan);

        for (entries.items) |entry| {
            const rel_path = if (std.mem.eql(u8, dir_path, "."))
                entry.name
            else
                try std.fmt.allocPrint(self.arena.allocator(), "{s}/{s}", .{ dir_path, entry.name });

            const expanded = self.expanded_dirs.contains(rel_path);

            try self.items.append(.{
                .path = rel_path,
                .name = entry.name,
                .is_dir = entry.is_dir,
                .expanded = expanded,
                .depth = depth,
            });

            if (entry.is_dir and expanded) {
                try self.scanDir(rel_path, depth + 1);
            }
        }
    }

    pub fn toggleExpand(self: *Explorer, path: []const u8) !void {
        if (self.expanded_dirs.contains(path)) {
            _ = self.expanded_dirs.remove(path);
        } else {
            try self.expanded_dirs.put(try self.allocator.dupe(u8, path), {});
        }
        try self.refresh();
    }

    pub fn handleDelete(self: *Explorer) !void {
        if (self.action_target_path) |path| {
            if (std.Io.Dir.cwd().deleteFile(self.io, path)) {} else |err| {
                if (err == error.IsDir) {
                    if (std.Io.Dir.cwd().deleteTree(self.io, path)) {} else |_| {}
                }
            }
        }
        self.action_state = .none;
        self.action_target_path = null;
        try self.refresh();
    }

    pub fn handleCreateFile(self: *Explorer) !void {
        if (self.input_len == 0) {
            self.action_state = .none;
            return;
        }
        const name = self.input_buf[0..self.input_len];
        const path = if (self.action_target_path) |p|
            try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ p, name })
        else
            try self.allocator.dupe(u8, name);
        defer self.allocator.free(path);

        if (self.action_state == .creating_dir) {
            if (std.Io.Dir.cwd().createDir(self.io, path, .default_dir)) {} else |_| {}
        } else {
            if (std.Io.Dir.cwd().createFile(self.io, path, .{})) |*f| {
                f.close(self.io);
            } else |_| {}
        }

        self.action_state = .none;
        self.action_target_path = null;
        self.input_len = 0;
        try self.refresh();
    }
    pub fn handleRename(self: *Explorer) !void {
        if (self.input_len == 0 or self.action_target_path == null) {
            self.action_state = .none;
            return;
        }
        const new_name = self.input_buf[0..self.input_len];
        const old_path = self.action_target_path.?;

        // Find parent directory of old_path
        const dir_part = std.fs.path.dirname(old_path) orelse ".";
        const new_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_part, new_name });
        defer self.allocator.free(new_path);

        try std.Io.Dir.renameAbsolute(old_path, new_path, self.io);

        self.action_state = .none;
        self.action_target_path = null;
        self.input_len = 0;
        try self.refresh();
    }

    pub fn handleMenuClick(self: *Explorer, col: u16, row: u16) !bool {
        if (!self.show_menu) return false;

        const mx = self.menu_x;
        const my = self.menu_y;
        const menu_w: u16 = 16;
        const menu_h: u16 = if (self.selected_idx) |idx|
            (if (self.items.items[idx].is_dir) @as(u16, 4) else @as(u16, 2))
        else
            @as(u16, 2);

        // Check if the click is within the menu boundaries
        if (col >= mx and col < mx + menu_w and row > my and row <= my + menu_h) {
            const rel_row = row - my - 1; // 0-indexed option index

            self.show_menu = false; // Close menu after choice

            if (self.selected_idx) |idx| {
                const item = self.items.items[idx];
                if (item.is_dir) {
                    // Directory Options: New File, New Folder, Rename, Delete
                    switch (rel_row) {
                        0 => { // New File
                            self.action_state = .creating_file;
                            self.input_len = 0;
                            self.action_target_path = item.path;
                        },
                        1 => { // New Folder
                            self.action_state = .creating_dir;
                            self.input_len = 0;
                            self.action_target_path = item.path;
                        },
                        2 => { // Rename
                            self.action_state = .renaming;
                            const basename = std.fs.path.basename(item.path);
                            const copy_len = @min(basename.len, self.input_buf.len);
                            @memcpy(self.input_buf[0..copy_len], basename[0..copy_len]);
                            self.input_len = copy_len;
                            self.action_target_path = item.path;
                        },
                        3 => { // Delete
                            self.action_state = .deleting;
                            self.action_target_path = item.path;
                        },
                        else => {},
                    }
                } else {
                    // File Options: Rename, Delete
                    switch (rel_row) {
                        0 => { // Rename
                            self.action_state = .renaming;
                            const basename = std.fs.path.basename(item.path);
                            const copy_len = @min(basename.len, self.input_buf.len);
                            @memcpy(self.input_buf[0..copy_len], basename[0..copy_len]);
                            self.input_len = copy_len;
                            self.action_target_path = item.path;
                        },
                        1 => { // Delete
                            self.action_state = .deleting;
                            self.action_target_path = item.path;
                        },
                        else => {},
                    }
                }
            } else {
                // Empty Space Options: New File, New Folder
                switch (rel_row) {
                    0 => { // New File
                        self.action_state = .creating_file;
                        self.input_len = 0;
                        self.action_target_path = null;
                    },
                    1 => { // New Folder
                        self.action_state = .creating_dir;
                        self.input_len = 0;
                        self.action_target_path = null;
                    },
                    else => {},
                }
            }
            return true;
        }

        return false;
    }

    pub fn handleMouse(self: *Explorer, m_col: u16, m_row: u16, rect: Rect) !?[]const u8 {
        if (m_col >= rect.x and m_col < rect.x + rect.w and m_row >= rect.y and m_row < rect.y + rect.h) {
            const rel_y = m_row - rect.y;

            // Handle action bar (top line)
            if (rel_y == 0) {
                if (m_col >= rect.x + rect.w - 8 and m_col <= rect.x + rect.w - 6) {
                    self.action_state = .creating_file;
                    self.input_len = 0;
                    if (self.selected_idx) |idx| {
                        const sel = self.items.items[idx];
                        self.action_target_path = if (sel.is_dir) sel.path else std.fs.path.dirname(sel.path) orelse ".";
                    } else {
                        self.action_target_path = null;
                    }
                    return null;
                }
                if (m_col >= rect.x + rect.w - 5 and m_col <= rect.x + rect.w - 3) {
                    self.action_state = .creating_dir;
                    self.input_len = 0;
                    if (self.selected_idx) |idx| {
                        const sel = self.items.items[idx];
                        self.action_target_path = if (sel.is_dir) sel.path else std.fs.path.dirname(sel.path) orelse ".";
                    } else {
                        self.action_target_path = null;
                    }
                    return null;
                }
                if (m_col >= rect.x + rect.w - 2 and m_col <= rect.x + rect.w) {
                    if (self.selected_idx) |idx| {
                        self.action_state = .deleting;
                        self.action_target_path = self.items.items[idx].path;
                    }
                    return null;
                }
                return null;
            }

            if (self.action_state != .none) {
                return null; // Don't allow clicking items while prompt is open
            }
            if (rel_y == 0) return null;

            const item_idx = rel_y - 1 + self.scroll_y;
            if (item_idx < self.items.items.len) {
                self.selected_idx = item_idx;
                const item = self.items.items[item_idx];
                if (item.is_dir) {
                    try self.toggleExpand(item.path);
                    return null;
                } else {
                    return item.path; // Return path to open
                }
            } else {
                self.selected_idx = null;
            }
        }
        return null;
    }

    pub fn handleScroll(self: *Explorer, dy: i32) void {
        if (dy < 0) {
            if (self.scroll_y > 0) self.scroll_y -= 1;
        } else if (dy > 0) {
            if (self.scroll_y + 1 < self.items.items.len) {
                self.scroll_y += 1;
            }
        }
    }

    pub fn handleKey(self: *Explorer, key: []const u8, rpc: ?*RpcClient) !bool {
        if (self.action_state == .none) {
            if (std.mem.eql(u8, key, "j") or std.mem.eql(u8, key, "<Down>")) {
                if (self.items.items.len > 0) {
                    if (self.selected_idx) |idx| {
                        self.selected_idx = @min(idx + 1, self.items.items.len - 1);
                    } else {
                        self.selected_idx = 0;
                    }
                    if (self.selected_idx.? >= self.scroll_y + 30) self.scroll_y += 1; // Basic scrolling boundary
                }
                return true;
            } else if (std.mem.eql(u8, key, "k") or std.mem.eql(u8, key, "<Up>")) {
                if (self.items.items.len > 0) {
                    if (self.selected_idx) |idx| {
                        self.selected_idx = if (idx == 0) 0 else idx - 1;
                    } else {
                        self.selected_idx = 0;
                    }
                    if (self.selected_idx.? < self.scroll_y) self.scroll_y = self.selected_idx.?;
                }
                return true;
            } else if (std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "o")) {
                if (self.selected_idx) |idx| {
                    if (idx < self.items.items.len) {
                        const item = self.items.items[idx];
                        if (item.is_dir) {
                            try self.toggleExpand(item.path);
                            try self.refresh();
                        } else {
                            if (rpc) |client| {
                                var cmd_buf: [512]u8 = undefined;
                                const cmd = std.fmt.bufPrint(&cmd_buf, "edit {s}", .{item.path}) catch "edit .";
                                var p = [_]Value{.{ .string = cmd }};
                                _ = client.call("nvim_command", &p) catch {};
                            }
                        }
                    }
                }
                return true;
            } else if (std.mem.eql(u8, key, "c")) {
                self.action_state = .creating_file;
                self.input_len = 0;
                if (self.selected_idx) |idx| {
                    const sel = self.items.items[idx];
                    self.action_target_path = if (sel.is_dir) sel.path else std.fs.path.dirname(sel.path) orelse ".";
                } else {
                    self.action_target_path = null;
                }
                return true;
            } else if (std.mem.eql(u8, key, "d")) {
                self.action_state = .creating_dir;
                self.input_len = 0;
                if (self.selected_idx) |idx| {
                    const sel = self.items.items[idx];
                    self.action_target_path = if (sel.is_dir) sel.path else std.fs.path.dirname(sel.path) orelse ".";
                } else {
                    self.action_target_path = null;
                }
                return true;
            } else if (std.mem.eql(u8, key, "r")) {
                if (self.selected_idx) |idx| {
                    self.action_state = .renaming;
                    self.action_target_path = self.items.items[idx].path;
                    self.input_len = 0;
                }
                return true;
            } else if (std.mem.eql(u8, key, "x")) {
                if (self.selected_idx) |idx| {
                    self.action_state = .deleting;
                    self.action_target_path = self.items.items[idx].path;
                }
                return true;
            } else if (std.mem.eql(u8, key, "R")) {
                try self.refresh();
                return true;
            }
            return false;
        }

        if (std.mem.eql(u8, key, "<Enter>")) {
            if (self.action_state == .deleting) {
                try self.handleDelete();
            } else if (self.action_state == .renaming) {
                try self.handleRename();
            } else {
                try self.handleCreateFile();
            }
            return true;
        } else if (std.mem.eql(u8, key, "<Esc>") or (key.len == 1 and key[0] == 0x1b)) {
            self.action_state = .none;
            return true;
        } else if (std.mem.eql(u8, key, "<BS>") or std.mem.eql(u8, key, "\x7f")) {
            if (self.input_len > 0) self.input_len -= 1;
            return true;
        } else if (key.len == 1 and key[0] >= 32 and key[0] <= 126 and self.action_state != .deleting) {
            if (self.input_len < self.input_buf.len) {
                self.input_buf[self.input_len] = key[0];
                self.input_len += 1;
            }
            return true;
        }
        return false;
    }

    fn drawTextClipped(rend: *renderer.Renderer, x: u16, y: u16, text: []const u8, max_w: u16, fg: Color, bg: Color, bold: bool, italic: bool) void {
        var col = x;
        var i: usize = 0;
        var rendered_len: u16 = 0;
        while (i < text.len and rendered_len < max_w) {
            const len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
            const char = text[i..@min(text.len, i + len)];
            var cell = renderer.Cell{
                .fg = fg,
                .bg = bg,
                .bold = bold,
                .italic = italic,
            };
            cell.setChar(char);
            rend.setCell(col, y, cell);
            col += 1;
            i += len;
            rendered_len += 1;
        }
    }

    pub fn draw(self: *Explorer, rend: *renderer.Renderer, rect: Rect, colors: anytype) void {
        rend.drawRect(rect, " ", colors.fg_primary, colors.bg_sidebar);

        const pointer = rend.pointer_position;
        defer rend.pointer_position = pointer;
        if (self.show_menu) rend.pointer_position = null;

        // Draw title and buttons
        if (rect.w == 0 or rect.h == 0) return;
        drawTextClipped(rend, rect.x + 1, rect.y, "EXPLORER", rect.w - 1, colors.fg_secondary, colors.bg_sidebar, true, false);

        if (rect.w >= 8) {
            rend.drawButtonText(rect.x + rect.w - 8, rect.y, 2, "+F", colors.fg_accent, colors.bg_sidebar, true, false);
            rend.drawButtonText(rect.x + rect.w - 5, rect.y, 2, "+D", colors.fg_accent, colors.bg_sidebar, true, false);
            rend.drawButtonText(rect.x + rect.w - 2, rect.y, 2, " X", colors.fg_accent, colors.bg_sidebar, true, false);
        }

        const max_items = if (rect.h > 0) @max(1, rect.h - 1) else 0;
        var y: u16 = 1;

        // Draw Items
        var i: usize = self.scroll_y;
        while (i < self.items.items.len and y < max_items) : ({
            i += 1;
            y += 1;
        }) {
            const item = self.items.items[i];
            defer rend.highlightHover(.{ .x = rect.x, .y = rect.y + y, .w = rect.w -| 1, .h = 1 }, colors.bg_sidebar, colors.fg_primary);
            const is_selected = (self.selected_idx != null and self.selected_idx.? == i);
            const bg = if (is_selected) colors.bg_editor else colors.bg_sidebar;

            // Highlight selected row
            if (is_selected) {
                rend.drawRect(Rect{ .x = rect.x, .y = rect.y + y, .w = rect.w, .h = 1 }, " ", colors.fg_primary, bg);
                rend.drawText(rect.x, rect.y + y, "▋", colors.fg_accent, bg, true, false);
            }

            const indent = @as(usize, item.depth) * 2;
            const prefix = if (item.is_dir) (if (item.expanded) "v " else "> ") else "  ";

            // Status check
            const is_unsaved = self.neovim_modified.contains(item.path);
            const is_session_saved = self.session_saved.contains(item.path);

            // Icon
            const icon = if (colors.nerd_fonts) (if (item.is_dir) "󰉋 " else getFileIcon(item.name)) else "";
            const text_x = rect.x + 1 + @as(u16, @intCast(@min(32000, indent)));

            var avail_w: u16 = 0;
            if (text_x < rect.x + rect.w) avail_w = rect.x + rect.w - text_x;
            if (avail_w > 0) {
                var buf: [256]u8 = undefined;
                const formatted = std.fmt.bufPrint(&buf, "{s}{s}{s}", .{ prefix, icon, item.name }) catch continue;

                var item_fg = colors.fg_primary;
                if (is_unsaved) {
                    item_fg = .{ .rgb = .{ .r = 255, .g = 80, .b = 80 } }; // Red-ish
                } else if (is_session_saved) {
                    item_fg = .{ .rgb = .{ .r = 80, .g = 255, .b = 80 } }; // Green-ish
                }

                drawTextClipped(rend, text_x, rect.y + y, formatted, avail_w, item_fg, bg, false, false);

                // Draw 'C' indicator at the end if modified
                if (is_unsaved or is_session_saved) {
                    const indicator_fg = if (is_unsaved)
                        Color{ .rgb = .{ .r = 255, .g = 0, .b = 0 } }
                    else
                        Color{ .rgb = .{ .r = 0, .g = 255, .b = 0 } };

                    if (rect.w > 3) {
                        rend.drawText(rect.x + rect.w - 2, rect.y + y, "C", indicator_fg, bg, true, false);
                    }
                }
            }
        }

        // Draw prompt if action_state != .none
        if (self.action_state != .none and rect.h > 2) {
            const prompt_y = if (rect.h > 0) rect.y + rect.h - 1 else rect.y;
            rend.drawRect(Rect{ .x = rect.x, .y = prompt_y - 1, .w = rect.w, .h = 2 }, " ", colors.fg_primary, colors.bg_editor);

            const ptext = switch (self.action_state) {
                .creating_file => "New File:",
                .creating_dir => "New Dir:",
                .deleting => "Del? (Enter=Y):",
                .renaming => "Rename:",
                else => "",
            };
            drawTextClipped(rend, rect.x + 1, prompt_y - 1, ptext, rect.w - 2, colors.fg_accent, colors.bg_editor, true, false);

            var val_buf: [256]u8 = undefined;
            const val_text = if (self.action_state == .deleting)
                self.action_target_path orelse ""
            else
                self.input_buf[0..self.input_len];

            const display_val = std.fmt.bufPrint(&val_buf, "{s}_", .{val_text}) catch val_text;
            drawTextClipped(rend, rect.x + 1, prompt_y, display_val, rect.w - 2, colors.fg_primary, colors.bg_editor, false, false);
        }

        // Draw context menu if show_menu == true
        if (self.show_menu) {
            rend.pointer_position = pointer;
            const mx = self.menu_x;
            const my = self.menu_y;

            const bg_menu = colors.bg_editor;
            const fg_menu = colors.fg_primary;
            const border_fg = colors.fg_accent;

            // Draw top border
            rend.drawText(mx, my, "┌──────────────┐", border_fg, bg_menu, false, false);

            // Draw options
            if (self.selected_idx) |idx| {
                if (self.items.items[idx].is_dir) {
                    rend.drawControlText(mx, my + 1, if (colors.nerd_fonts) "│ 󰝒 New File   │" else "│ + New File   │", fg_menu, bg_menu, false, false);
                    rend.drawControlText(mx, my + 2, if (colors.nerd_fonts) "│ 󰉋 New Folder │" else "│ + New Folder │", fg_menu, bg_menu, false, false);
                    rend.drawControlText(mx, my + 3, if (colors.nerd_fonts) "│ 󰏫 Rename     │" else "│ ~ Rename     │", fg_menu, bg_menu, false, false);
                    rend.drawControlText(mx, my + 4, if (colors.nerd_fonts) "│ 󰆴 Delete     │" else "│ - Delete     │", fg_menu, bg_menu, false, false);
                    rend.drawText(mx, my + 5, "└──────────────┘", border_fg, bg_menu, false, false);
                } else {
                    rend.drawControlText(mx, my + 1, if (colors.nerd_fonts) "│ 󰏫 Rename     │" else "│ ~ Rename     │", fg_menu, bg_menu, false, false);
                    rend.drawControlText(mx, my + 2, if (colors.nerd_fonts) "│ 󰆴 Delete     │" else "│ - Delete     │", fg_menu, bg_menu, false, false);
                    rend.drawText(mx, my + 3, "└──────────────┘", border_fg, bg_menu, false, false);
                }
            } else {
                rend.drawControlText(mx, my + 1, if (colors.nerd_fonts) "│ 󰝒 New File   │" else "│ + New File   │", fg_menu, bg_menu, false, false);
                rend.drawControlText(mx, my + 2, if (colors.nerd_fonts) "│ 󰉋 New Folder │" else "│ + New Folder │", fg_menu, bg_menu, false, false);
                rend.drawText(mx, my + 3, "└──────────────┘", border_fg, bg_menu, false, false);
            }
        }
    }
};
