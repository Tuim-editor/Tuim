const std = @import("std");
const renderer = @import("../renderer.zig");
const Color = renderer.Color;
const Rect = @import("../layout.zig").Rect;
const input = @import("../input.zig");
const primitives = @import("primitives.zig");

pub const StorePlugin = struct {
    name: []const u8,
    full_name: []const u8,
    stars: usize,
    description: []const u8,
    installed: bool,
    enabled: bool = true,
    protected: bool = false,
    status: []const u8 = "Not installed",
};

pub const Category = enum(u8) {
    all,
    colorscheme,
    lsp,
    git,
    ai,
    treesitter,
    telescope,
    installed,

    pub fn shortLabel(self: Category) []const u8 {
        return switch (self) {
            .all => "All",
            .colorscheme => "Theme",
            .lsp => "LSP",
            .git => "Git",
            .ai => "AI",
            .treesitter => "TS",
            .telescope => "Tele",
            .installed => "Inst",
        };
    }

    pub fn label(self: Category) []const u8 {
        return switch (self) {
            .all => "All Plugins",
            .colorscheme => "Themes & Colors",
            .lsp => "LSP Configuration",
            .git => "Git Integrations",
            .ai => "AI & LLM Assistants",
            .treesitter => "Treesitter Parsers",
            .telescope => "Telescope Extensions",
            .installed => "Installed Plugins",
        };
    }

    pub fn toTagName(self: Category) []const u8 {
        return switch (self) {
            .all => "all",
            .colorscheme => "colorscheme",
            .lsp => "lsp",
            .git => "git",
            .ai => "ai",
            .treesitter => "treesitter",
            .telescope => "telescope",
            .installed => "installed",
        };
    }
};

pub const ExtensionShop = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    data_dir: []const u8,
    plugins: std.array_list.Managed(StorePlugin),
    search_query: std.array_list.Managed(u8),
    selected_idx: usize = 0,
    scroll_offset: usize = 0,
    is_searching: bool = false,
    message: ?[]const u8 = null,
    selected_category: Category = .installed,
    is_open: bool = false,
    show_reload_confirm: bool = false,
    is_detail_open: bool = false,
    edit_config_path: ?[]const u8 = null,
    confirm_remove: bool = false,

    panel_rect: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    sidebar_rect: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },

    pub fn init(allocator: std.mem.Allocator, io: std.Io, data_dir: []const u8) ExtensionShop {
        return .{
            .allocator = allocator,
            .io = io,
            .data_dir = data_dir,
            .plugins = std.array_list.Managed(StorePlugin).init(allocator),
            .search_query = std.array_list.Managed(u8).init(allocator),
            .selected_category = .installed,
            .is_open = false,
            .show_reload_confirm = false,
            .is_detail_open = false,
            .edit_config_path = null,
        };
    }

    pub fn deinit(self: *ExtensionShop) void {
        self.clearPlugins();
        self.plugins.deinit();
        self.search_query.deinit();
        if (self.message) |msg| self.allocator.free(msg);
        if (self.edit_config_path) |path| self.allocator.free(path);
    }

    fn clearPlugins(self: *ExtensionShop) void {
        for (self.plugins.items) |p| {
            self.allocator.free(p.name);
            self.allocator.free(p.full_name);
            self.allocator.free(p.description);
            self.allocator.free(p.status);
        }
        self.plugins.clearAndFree();
    }

    pub fn setMessage(self: *ExtensionShop, msg: []const u8) void {
        if (self.message) |m| self.allocator.free(m);
        self.message = self.allocator.dupe(u8, msg) catch null;
    }

    pub fn triggerSearch(self: *ExtensionShop) !void {
        self.clearPlugins();

        const script_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.data_dir, "store_search.py" });
        defer self.allocator.free(script_path);

        const query = self.search_query.items;
        const argv = &[_][]const u8{ "python3", script_path, "search", query, self.selected_category.toTagName() };

        var child = std.process.spawn(self.io, .{
            .argv = argv,
            .stdout = .pipe,
            .stderr = .ignore,
        }) catch {
            self.setMessage("Failed to run store_search.py");
            return;
        };
        errdefer {
            if (child.id != null) child.kill(self.io);
        }

        var stdout = std.array_list.Managed(u8).init(self.allocator);
        defer stdout.deinit();

        if (child.stdout) |out| {
            while (true) {
                var chunk: [1024]u8 = undefined;
                const len = std.posix.read(out.handle, &chunk) catch 0;
                if (len == 0) break;
                try stdout.appendSlice(chunk[0..len]);
            }
        }

        _ = try child.wait(self.io);

        const json_str = stdout.items;
        if (json_str.len == 0) return;

        // Parse JSON output into our ArrayList
        const parsed = std.json.parseFromSlice([]struct {
            name: []const u8,
            full_name: []const u8,
            stars: usize,
            description: []const u8,
            installed: bool,
            enabled: bool = true,
            protected: bool = false,
            status: []const u8 = "Not installed",
        }, self.allocator, json_str, .{ .ignore_unknown_fields = true }) catch {
            const failure = std.json.parseFromSlice(struct { message: []const u8 }, self.allocator, json_str, .{ .ignore_unknown_fields = true }) catch {
                self.setMessage("Failed to parse search results");
                return;
            };
            defer failure.deinit();
            self.setMessage(failure.value.message);
            return;
        };
        defer parsed.deinit();

        for (parsed.value) |p| {
            try self.plugins.append(.{
                .name = try self.allocator.dupe(u8, p.name),
                .full_name = try self.allocator.dupe(u8, p.full_name),
                .stars = p.stars,
                .description = try self.allocator.dupe(u8, p.description),
                .installed = p.installed,
                .enabled = p.enabled,
                .protected = p.protected,
                .status = try self.allocator.dupe(u8, p.status),
            });
        }

        self.selected_idx = 0;
        self.scroll_offset = 0;
    }

    const filters = [_]Category{ .all, .colorscheme, .lsp, .git, .ai, .treesitter, .telescope };

    pub fn open(self: *ExtensionShop) !void {
        self.is_open = true;
        self.is_detail_open = false;
        self.confirm_remove = false;
        self.is_searching = false;
        try self.triggerSearch();
    }

    fn selectCategory(self: *ExtensionShop, category: Category) !void {
        self.selected_category = category;
        self.search_query.clearRetainingCapacity();
        self.is_detail_open = false;
        self.is_searching = false;
        self.confirm_remove = false;
        self.show_reload_confirm = false;
        self.is_open = true;
        try self.triggerSearch();
    }

    fn split(self: *ExtensionShop) bool {
        return self.panel_rect.w >= 76;
    }

    const ConfirmLayout = struct {
        card: Rect,
        accept: Rect,
        cancel: Rect,
    };

    fn confirmLayout(rect: Rect) ConfirmLayout {
        const card_w = @min(rect.w -| 4, 42);
        const card_h: u16 = 7;
        const card = Rect{
            .x = rect.x + (rect.w -| card_w) / 2,
            .y = rect.y + (rect.h -| card_h) / 2,
            .w = card_w,
            .h = card_h,
        };
        const button_w: u16 = 12;
        return .{
            .card = card,
            .accept = .{ .x = card.x + 2, .y = card.y + 4, .w = button_w, .h = 1 },
            .cancel = .{ .x = card.x + 16, .y = card.y + 4, .w = button_w, .h = 1 },
        };
    }

    fn visibleRows(self: *ExtensionShop) usize {
        return @max(1, (self.panel_rect.h -| 9) / 3);
    }
    fn select(self: *ExtensionShop, index: usize) void {
        self.selected_idx = @min(index, self.plugins.items.len -| 1);
        self.confirm_remove = false;
        if (self.selected_idx < self.scroll_offset) self.scroll_offset = self.selected_idx;
        if (self.selected_idx >= self.scroll_offset + self.visibleRows()) self.scroll_offset = self.selected_idx - self.visibleRows() + 1;
    }

    pub fn draw(self: *ExtensionShop, rend: *renderer.Renderer, rect: Rect, colors: anytype) void {
        self.sidebar_rect = rect;
        if (rect.w < 4 or rect.h < 2) return;
        rend.drawRect(rect, " ", colors.fg_primary, colors.bg_sidebar);
        rend.drawTextClipped(rect.x + 2, rect.y, rect.w -| 4, "EXTENSIONS", colors.fg_primary, colors.bg_sidebar, true, false);
        const labels = [_][]const u8{ "Installed", "Discover" };
        for (labels, 0..) |label, i| {
            const y = rect.y + 2 + @as(u16, @intCast(i)) * 2;
            if (y >= rect.y + rect.h) break;
            const active = (i == 0) == (self.selected_category == .installed);
            rend.drawButtonText(rect.x + 1, y, rect.w -| 3, label, if (active) @import("../theme.zig").readableForeground(colors.fg_primary, colors.bg_accent, 4.5) else colors.fg_primary, if (active) colors.bg_accent else colors.bg_sidebar, active, false);
        }
        if (self.selected_category != .installed) {
            for (filters, 0..) |category, i| {
                const y = rect.y + 7 + @as(u16, @intCast(i));
                if (y >= rect.y + rect.h -| 2) break;
                const active = self.selected_category == category;
                rend.drawButtonText(rect.x + 2, y, rect.w -| 4, category.label(), if (active) colors.fg_accent else colors.fg_secondary, colors.bg_sidebar, active, false);
            }
        } else if (rect.h > 11) {
            rend.drawTextClipped(rect.x + 2, rect.y + 7, rect.w -| 4, "Make Tuim yours.", colors.fg_accent, colors.bg_sidebar, true, false);
            rend.drawTextClipped(rect.x + 2, rect.y + 9, rect.w -| 4, "Manage your plugins", colors.fg_secondary, colors.bg_sidebar, false, false);
            rend.drawTextClipped(rect.x + 2, rect.y + 10, rect.w -| 4, "Explore new tools.", colors.fg_secondary, colors.bg_sidebar, false, false);
        }
        if (rect.h > 4) rend.drawTextClipped(rect.x + 2, rect.y + rect.h - 1, rect.w -| 4, "1 Installed / 2 Find", colors.fg_secondary, colors.bg_sidebar, false, false);
    }

    pub fn drawPanel(self: *ExtensionShop, rend: *renderer.Renderer, rect: Rect, colors: anytype) void {
        self.panel_rect = rect;
        rend.drawRect(rect, " ", colors.fg_primary, colors.bg_editor);
        if (rect.w < 34 or rect.h < 12) {
            if (self.confirm_remove or self.show_reload_confirm) {
                if (rect.h > 0) rend.drawButtonText(rect.x, rect.y, rect.w, if (self.confirm_remove) "Uninstall?" else "Restart Tuim?", @import("../theme.zig").readableForeground(colors.fg_primary, colors.bg_accent, 4.5), colors.bg_accent, true, false);
                if (rect.h > 1) rend.drawTextClipped(rect.x, rect.y + 1, rect.w, "Enlarge to confirm", colors.fg_primary, colors.bg_editor, false, false);
                if (rect.h > 2) rend.drawTextClipped(rect.x, rect.y + 2, rect.w, "N / Esc: cancel", colors.fg_secondary, colors.bg_editor, false, false);
                return;
            }
            rend.drawTextClipped(rect.x, rect.y, rect.w, "Extensions: enlarge to browse", colors.fg_accent, colors.bg_editor, true, false);
            if (rect.h > 1) rend.drawTextClipped(rect.x, rect.y + 1, rect.w, "Esc returns to your file", colors.fg_secondary, colors.bg_editor, false, false);
            return;
        }
        const x = rect.x + 2;
        const y = rect.y;
        const width = rect.w - 4;
        rend.drawTextClipped(x, y + 1, width -| 10, if (self.selected_category == .installed) "Your plugins" else "Discover extensions", colors.fg_primary, colors.bg_editor, true, false);
        rend.drawButtonText(rect.x + rect.w - 10, y + 1, 8, "Esc Back", colors.fg_secondary, colors.bg_editor, false, false);
        rend.drawButtonText(x, y + 3, 15, "1 Installed", if (self.selected_category == .installed) @import("../theme.zig").readableForeground(colors.fg_primary, colors.bg_accent, 4.5) else colors.fg_secondary, if (self.selected_category == .installed) colors.bg_accent else colors.bg_sidebar, true, false);
        rend.drawButtonText(x + 16, y + 3, 13, "2 Discover", if (self.selected_category != .installed) @import("../theme.zig").readableForeground(colors.fg_primary, colors.bg_accent, 4.5) else colors.fg_secondary, if (self.selected_category != .installed) colors.bg_accent else colors.bg_sidebar, true, false);
        var count_buf: [72]u8 = undefined;
        const count = std.fmt.bufPrint(&count_buf, "{d} plugins  /  {s}", .{ self.plugins.items.len, if (self.selected_category == .installed) @as([]const u8, "local library") else self.selected_category.shortLabel() }) catch "";
        if (width > 52) rend.drawTextClipped(x + 32, y + 3, width - 32, count, colors.fg_secondary, colors.bg_editor, false, false);
        var query_buf: [256]u8 = undefined;
        const query = std.fmt.bufPrint(&query_buf, "{s}{s}{s}", .{ if (self.is_searching) @as([]const u8, "Search: ") else "/ Search: ", if (self.search_query.items.len == 0 and !self.is_searching) @as([]const u8, "name or description") else self.search_query.items, if (self.is_searching) @as([]const u8, "_") else "" }) catch "/ Search";
        rend.drawButtonText(x, y + 5, width, query, colors.fg_secondary, colors.bg_sidebar, false, false);

        const list_width = if (self.split()) width * 45 / 100 else width;
        if (!self.is_detail_open or self.split()) {
            if (self.plugins.items.len == 0) {
                rend.drawTextClipped(x, y + 8, list_width, if (self.search_query.items.len > 0) "No matching plugins." else if (self.selected_category == .installed) "Your plugin library is empty." else "Catalog unavailable. Press R to retry.", colors.fg_primary, colors.bg_editor, true, false);
                rend.drawTextClipped(x, y + 10, list_width, if (self.selected_category == .installed) "Choose Discover to add your first plugin." else "Check your connection, or try another search.", colors.fg_secondary, colors.bg_editor, false, false);
            }
            const end = @min(self.plugins.items.len, self.scroll_offset + self.visibleRows());
            for (self.scroll_offset..@max(self.scroll_offset, end)) |i| {
                const p = self.plugins.items[i];
                const py = y + 7 + @as(u16, @intCast(i - self.scroll_offset)) * 3;
                const active = self.selected_idx == i;
                const bg = if (active) colors.bg_accent else colors.bg_editor;
                const fg = @import("../theme.zig").readableForeground(colors.fg_primary, bg, 4.5);
                const card = Rect{ .x = x, .y = py, .w = list_width, .h = 2 };
                rend.drawRect(card, " ", colors.fg_primary, bg);
                rend.drawTextClipped(x + 1, py, list_width -| 2, p.name, fg, bg, true, false);
                rend.drawTextClipped(x + 1, py + 1, list_width -| 2, if (self.selected_category == .installed) p.status else p.description, if (active) fg else colors.fg_secondary, bg, false, false);
                if (active) rend.drawTextClipped(x, py, 1, "▎", fg, bg, true, false);
                rend.highlightHover(card, bg, colors.fg_primary);
            }
        }
        if (self.plugins.items.len > 0 and (self.split() or self.is_detail_open)) {
            const dx = if (self.split()) x + list_width + 3 else x;
            const dw = if (self.split()) width - list_width - 3 else width;
            if (self.split()) rend.drawRect(.{ .x = dx - 2, .y = y + 7, .w = 1, .h = rect.h -| 10 }, "│", colors.border_color, colors.bg_editor);
            self.drawDetails(rend, .{ .x = dx, .y = y + 7, .w = dw, .h = rect.h -| 10 }, colors);
        }
        if (self.confirm_remove or self.show_reload_confirm) {
            const confirm = confirmLayout(rect);
            const title_fg = @import("../theme.zig").readableForeground(colors.fg_primary, colors.bg_accent, 4.5);
            rend.drawRect(confirm.card, " ", colors.fg_primary, colors.bg_sidebar);
            rend.drawRect(.{ .x = confirm.card.x, .y = confirm.card.y, .w = confirm.card.w, .h = 1 }, " ", colors.fg_primary, colors.bg_accent);
            rend.drawTextClipped(confirm.card.x + 1, confirm.card.y, confirm.card.w -| 2, if (self.confirm_remove) "Uninstall?" else "Restart Tuim?", title_fg, colors.bg_accent, true, false);
            rend.drawTextClipped(confirm.card.x + 2, confirm.card.y + 1, confirm.card.w -| 4, if (self.confirm_remove and self.selected_idx < self.plugins.items.len) self.plugins.items[self.selected_idx].name else "Plugin changes saved.", colors.fg_primary, colors.bg_sidebar, false, false);
            rend.drawTextClipped(confirm.card.x + 2, confirm.card.y + 2, confirm.card.w -| 4, if (self.confirm_remove) "Configuration will be kept." else "Restart to apply them.", colors.fg_secondary, colors.bg_sidebar, false, false);
            rend.drawButtonText(confirm.accept.x, confirm.accept.y, confirm.accept.w, if (self.confirm_remove) "[Y] Remove" else "[Y] Restart", @import("../theme.zig").readableForeground(colors.fg_primary, colors.bg_accent, 4.5), colors.bg_accent, true, false);
            rend.drawButtonText(confirm.cancel.x, confirm.cancel.y, confirm.cancel.w, if (self.confirm_remove) "[N] Cancel" else "[N] Later", colors.fg_primary, colors.bg_editor, true, false);
            rend.drawTextClipped(confirm.card.x + 1, confirm.card.y + 6, confirm.card.w -| 2, if (self.confirm_remove) "Esc  Cancel" else "Esc  Close", colors.fg_secondary, colors.bg_sidebar, false, false);
        } else {
            const foot_y = y + rect.h - 2;
            const hint = if (self.is_searching) "Enter Search   Esc Cancel" else if (width < 60) "Enter Details  E Config  D Toggle  U Remove" else "Enter Details   E Config   D Enable/Disable   U Uninstall";
            rend.drawButtonText(x, foot_y, width, hint, colors.fg_secondary, colors.bg_sidebar, false, false);
        }
        const foot_y = y + rect.h - 2;
        if (self.message) |msg| rend.drawTextClipped(x, foot_y + 1, width, msg, colors.fg_accent, colors.bg_editor, false, false);
    }

    fn drawDetails(self: *ExtensionShop, rend: *renderer.Renderer, rect: Rect, colors: anytype) void {
        if (rect.h < 3) return;
        const p = self.plugins.items[self.selected_idx];
        rend.drawTextClipped(rect.x, rect.y, rect.w, p.name, colors.fg_primary, colors.bg_editor, true, false);
        rend.drawTextClipped(rect.x, rect.y + 1, rect.w, p.full_name, colors.fg_secondary, colors.bg_editor, false, false);
        if (rect.h > 3) rend.drawTextClipped(rect.x, rect.y + 3, rect.w, p.status, colors.fg_accent, colors.bg_editor, true, false);
        if (rect.h > 5) rend.drawButtonText(rect.x, rect.y + 5, rect.w, if (p.protected) "Managed by Tuim / local source" else if (p.installed) "E  Configure plugin" else "Enter  Install plugin", @import("../theme.zig").readableForeground(colors.fg_primary, colors.bg_accent, 4.5), colors.bg_accent, true, false);
        if (p.installed and !p.protected) {
            if (rect.h > 7) rend.drawButtonText(rect.x, rect.y + 7, rect.w, if (p.enabled) "D  Disable plugin" else "D  Enable plugin", colors.fg_primary, colors.bg_sidebar, false, false);
            if (rect.h > 9) rend.drawButtonText(rect.x, rect.y + 9, rect.w, "U  Uninstall plugin", colors.fg_secondary, colors.bg_sidebar, false, false);
        }
        if (rect.h > 12) {
            var words = std.mem.tokenizeAny(u8, p.description, " \t\n\r");
            var row: u16 = 12;
            var col: u16 = 0;
            while (words.next()) |word| {
                if (col > 0 and col + word.len + 1 > rect.w) {
                    row += 1;
                    col = 0;
                }
                if (row >= rect.h) break;
                const n: u16 = @intCast(@min(word.len, rect.w -| col));
                rend.drawTextClipped(rect.x + col, rect.y + row, n, word, colors.fg_secondary, colors.bg_editor, false, false);
                col += n + 1;
            }
        }
    }

    pub fn handleKey(self: *ExtensionShop, key: []const u8) !bool {
        if (!self.is_open) {
            try self.open();
            return true;
        }
        return self.handlePanelKey(key);
    }

    pub fn handlePanelKey(self: *ExtensionShop, key: []const u8) !bool {
        if (self.is_searching) {
            if (std.mem.eql(u8, key, "<Esc>")) self.is_searching = false else if (std.mem.eql(u8, key, "<Enter>")) {
                self.is_searching = false;
                try self.triggerSearch();
            } else if (std.mem.eql(u8, key, "<BS>") or std.mem.eql(u8, key, "<Backspace>")) {
                _ = self.search_query.pop();
            } else if (key.len > 0 and (key.len == 1 or key[0] != '<')) {
                for (key) |c| {
                    if (c >= 32 and c < 127) try self.search_query.append(c);
                }
            }
            return true;
        }
        if (self.confirm_remove or self.show_reload_confirm) {
            if (std.mem.eql(u8, key, "y") or std.mem.eql(u8, key, "Y")) {
                if (self.panel_rect.w < 34 or self.panel_rect.h < 12) return true;
                if (self.confirm_remove) {
                    self.confirm_remove = false;
                    try self.changePlugin(self.selected_idx, "remove");
                } else {
                    self.show_reload_confirm = false;
                    return error.ReloadApplication;
                }
            } else if (std.mem.eql(u8, key, "n") or std.mem.eql(u8, key, "<Esc>") or std.mem.eql(u8, key, "<Enter>")) {
                self.confirm_remove = false;
                self.show_reload_confirm = false;
            }
            return true;
        }
        if (std.mem.eql(u8, key, "<Esc>")) {
            if (self.is_detail_open and !self.split()) self.is_detail_open = false else self.is_open = false;
        } else if (std.mem.eql(u8, key, "1")) try self.selectCategory(.installed) else if (std.mem.eql(u8, key, "2")) try self.selectCategory(.all) else if (std.mem.eql(u8, key, "/")) self.is_searching = true else if (std.mem.eql(u8, key, "<Tab>")) try self.selectCategory(if (self.selected_category == .installed) .all else .installed) else if (std.mem.eql(u8, key, "c") and self.selected_category != .installed) {
            for (filters, 0..) |category, i| {
                if (category == self.selected_category) {
                    try self.selectCategory(filters[(i + 1) % filters.len]);
                    break;
                }
            }
        } else if (std.mem.eql(u8, key, "r")) try self.triggerSearch() else if (std.mem.eql(u8, key, "j") or std.mem.eql(u8, key, "<Down>")) self.select(self.selected_idx + 1) else if (std.mem.eql(u8, key, "k") or std.mem.eql(u8, key, "<Up>")) self.select(self.selected_idx -| 1) else if (std.mem.eql(u8, key, "<Home>")) self.select(0) else if (std.mem.eql(u8, key, "<End>")) self.select(self.plugins.items.len -| 1) else if (self.plugins.items.len > 0) {
            const p = self.plugins.items[self.selected_idx];
            if (std.mem.eql(u8, key, "<Enter>")) {
                if (!p.installed and (self.is_detail_open or self.split())) try self.changePlugin(self.selected_idx, "add") else self.is_detail_open = true;
            } else if (!p.protected) {
                if (std.mem.eql(u8, key, "e") and p.installed) try self.editConfig(p) else if (std.mem.eql(u8, key, "d") and p.installed) try self.changePlugin(self.selected_idx, if (p.enabled) "disable" else "enable") else if (std.mem.eql(u8, key, "u") and p.installed) self.confirm_remove = true;
            }
        }
        return true;
    }

    pub fn handleMouse(self: *ExtensionShop, mx: u16, my: u16, rect: Rect) !bool {
        if (!primitives.containsRect(rect, mx, my)) return false;
        if (my == rect.y + 2) try self.selectCategory(.installed) else if (my == rect.y + 4) try self.selectCategory(.all) else if (self.selected_category != .installed and my >= rect.y + 7 and my < rect.y + 7 + filters.len) try self.selectCategory(filters[my - rect.y - 7]);
        return true;
    }

    pub fn handlePanelMouse(self: *ExtensionShop, m: input.MouseEvent) !bool {
        const rect = self.panel_rect;
        if (self.confirm_remove or self.show_reload_confirm) {
            if (m.action != .press or m.button != .left or rect.w < 34 or rect.h < 12) return true;
            const confirm = confirmLayout(rect);
            if (primitives.containsRect(confirm.accept, m.col, m.row)) return self.handlePanelKey("y");
            if (primitives.containsRect(confirm.cancel, m.col, m.row)) return self.handlePanelKey("n");
            return true;
        }
        if (primitives.containsRect(self.sidebar_rect, m.col, m.row)) return self.handleMouse(m.col, m.row, self.sidebar_rect);
        if (!primitives.containsRect(rect, m.col, m.row)) return false;
        if (m.button == .wheel_up) {
            self.select(self.selected_idx -| 1);
            return true;
        }
        if (m.button == .wheel_down) {
            self.select(self.selected_idx + 1);
            return true;
        }
        if (m.action != .press or m.button != .left) return true;
        if (rect.w < 34 or rect.h < 12) return true;
        const x = rect.x + 2;
        const y = rect.y;
        if (m.row == y + 1 and m.col >= rect.x + rect.w - 10) return self.handlePanelKey("<Esc>");
        if (m.row == y + 3) {
            if (m.col < x + 15) try self.selectCategory(.installed) else if (m.col < x + 29) try self.selectCategory(.all);
            return true;
        }
        if (m.row == y + 5) {
            self.is_searching = true;
            return true;
        }
        const width = rect.w - 4;
        const list_width = if (self.split()) width * 45 / 100 else width;
        if ((!self.is_detail_open or self.split()) and m.col < x + list_width and m.row >= y + 7 and m.row < y + rect.h - 2) {
            const idx = self.scroll_offset + (m.row - y - 7) / 3;
            if (idx < self.plugins.items.len) {
                self.select(idx);
                self.is_detail_open = true;
            }
        } else if (self.plugins.items.len > 0 and (self.is_detail_open or self.split())) {
            if (m.row == y + 12) return self.handlePanelKey(if (self.plugins.items[self.selected_idx].installed) "e" else "<Enter>");
            if (m.row == y + 14) return self.handlePanelKey("d");
            if (m.row == y + 16) return self.handlePanelKey("u");
        }
        return true;
    }

    pub fn changePlugin(self: *ExtensionShop, idx: usize, action: []const u8) !void {
        if (idx >= self.plugins.items.len) return;
        const p = self.plugins.items[idx];
        if (p.protected) {
            self.setMessage("This plugin is managed by Tuim or its source.");
            return;
        }
        const script_path = try std.fs.path.join(self.allocator, &.{ self.data_dir, "store_search.py" });
        defer self.allocator.free(script_path);
        var child = try std.process.spawn(self.io, .{ .argv = &.{ "python3", script_path, action, p.full_name }, .stdout = .pipe, .stderr = .ignore });
        errdefer {
            if (child.id != null) child.kill(self.io);
        }
        var output = std.array_list.Managed(u8).init(self.allocator);
        defer output.deinit();
        if (child.stdout) |out| {
            while (true) {
                var chunk: [1024]u8 = undefined;
                const len = std.posix.read(out.handle, &chunk) catch 0;
                if (len == 0) break;
                try output.appendSlice(chunk[0..len]);
            }
        }
        const term = try child.wait(self.io);
        const parsed = std.json.parseFromSlice(struct { success: bool, message: []const u8 }, self.allocator, output.items, .{ .ignore_unknown_fields = true }) catch {
            self.setMessage("Unable to update plugin. Inspect the Tuim log.");
            return;
        };
        defer parsed.deinit();
        self.setMessage(parsed.value.message);
        if (!parsed.value.success or term != .exited or term.exited != 0) return;
        self.is_detail_open = false;
        try self.triggerSearch();
        self.show_reload_confirm = true;
    }

    fn editConfig(self: *ExtensionShop, p: StorePlugin) !void {
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
                var template_buf: [1024]u8 = undefined;
                const template = try std.fmt.bufPrint(
                    &template_buf,
                    "-- Configuration for {s}\n" ++
                        "-- Restart Tuim after saving. Return a lazy.nvim spec override.\n" ++
                        "-- opts configures plugins using automatic setup.\n" ++
                        "-- For bundled custom setup, override config with a function.\n\n" ++
                        "return {{\n" ++
                        "  -- opts = {{ }},\n" ++
                        "  -- config = function(plugin, opts)\n" ++
                        "  --   require(\"plugin_module\").setup(opts or {{}})\n" ++
                        "  -- end,\n" ++
                        "}}\n",
                    .{p.name},
                );
                try std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = config_file_path, .data = template });
            },
            else => return err,
        }

        if (self.edit_config_path) |old| self.allocator.free(old);
        self.edit_config_path = config_file_path;
    }
};
