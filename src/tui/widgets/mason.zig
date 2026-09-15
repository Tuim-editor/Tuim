const std = @import("std");
const renderer = @import("../renderer.zig");
const Color = renderer.Color;
const msgpack = @import("../../nvim/msgpack.zig");
const Value = msgpack.Value;
const rpc_mod = @import("../../nvim/rpc.zig");
const RpcClient = rpc_mod.RpcClient;
const input = @import("../input.zig");
const primitives = @import("primitives.zig");

pub const MasonTab = enum {
    lsp,
    dap,
    linter,
    formatter,
    runtime,
    compiler,

    pub fn label(self: MasonTab) []const u8 {
        return switch (self) {
            .lsp => " LSP ",
            .dap => " DAP ",
            .linter => " Linter ",
            .formatter => " Formatter ",
            .runtime => " Runtime ",
            .compiler => " Compiler ",
        };
    }

    pub fn fromString(s: []const u8) ?MasonTab {
        if (std.mem.eql(u8, s, "LSP")) return .lsp;
        if (std.mem.eql(u8, s, "DAP")) return .dap;
        if (std.mem.eql(u8, s, "Linter")) return .linter;
        if (std.mem.eql(u8, s, "Formatter")) return .formatter;
        if (std.mem.eql(u8, s, "Runtime")) return .runtime;
        if (std.mem.eql(u8, s, "Compiler")) return .compiler;
        return null;
    }
};

pub const InstallStatus = enum {
    idle,
    installing,
    success,
    err,
};

pub const MasonPackage = struct {
    name: []const u8,
    is_installed: bool = false,
    selected: bool = false, // user's desired state
    tabs: std.EnumSet(MasonTab),
};

pub const MasonWidget = struct {
    is_open: bool = false,
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    packages: std.array_list.Managed(MasonPackage),
    scroll_offset: usize = 0,
    selected_idx: usize = 0,
    selected_tab: MasonTab = .lsp,

    // Search
    search_query: [64]u8 = @splat(0),
    search_len: usize = 0,
    is_searching: bool = false,

    // Install status overlay
    install_status: InstallStatus = .idle,
    status_message: [128]u8 = @splat(0),
    status_len: usize = 0,
    health_summary: [256]u8 = @splat(0),
    health_len: usize = 0,

    pub fn init(allocator: std.mem.Allocator) MasonWidget {
        return .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .packages = std.array_list.Managed(MasonPackage).init(allocator),
        };
    }

    pub fn deinit(self: *MasonWidget) void {
        self.arena.deinit();
        self.packages.deinit();
    }

    pub fn refresh(self: *MasonWidget, rpc: *RpcClient) void {
        const script =
            \\local has_mason, registry = pcall(require, 'mason-registry')
            \\if not has_mason then return {} end
            \\local res = {}
            \\for _, p in ipairs(registry.get_all_packages()) do
            \\    table.insert(res, {
            \\        name = p.name,
            \\        categories = p.spec.categories,
            \\        installed = p:is_installed()
            \\    })
            \\end
            \\return res
        ;

        var params = self.allocator.alloc(Value, 2) catch return;
        defer self.allocator.free(params);
        params[0] = .{ .string = script };
        params[1] = .{ .array = &[_]Value{} };

        if (rpc.isAsyncEnabled()) {
            _ = rpc.requestAsyncWithHandler("nvim_exec_lua", params, self, asyncRefreshComplete) catch return;
            self.refreshHealth(rpc);
            return;
        }

        if (rpc.call("nvim_exec_lua", params) catch null) |res| {
            defer msgpack.freeValue(res, self.allocator);
            if (res == .array) {
                _ = self.arena.reset(.retain_capacity);
                self.packages.clearRetainingCapacity();

                for (res.array) |item| {
                    if (item == .map) {
                        var pkg: MasonPackage = .{
                            .name = "",
                            .tabs = std.EnumSet(MasonTab).empty,
                        };
                        for (item.map) |kv| {
                            if (kv.key == .string) {
                                if (std.mem.eql(u8, kv.key.string, "name") and kv.value == .string) {
                                    pkg.name = self.arena.allocator().dupe(u8, kv.value.string) catch "";
                                } else if (std.mem.eql(u8, kv.key.string, "installed") and kv.value == .bool) {
                                    pkg.is_installed = kv.value.bool;
                                    pkg.selected = pkg.is_installed;
                                } else if (std.mem.eql(u8, kv.key.string, "categories") and kv.value == .array) {
                                    for (kv.value.array) |cat_val| {
                                        if (cat_val == .string) {
                                            if (MasonTab.fromString(cat_val.string)) |tab| {
                                                pkg.tabs.insert(tab);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if (pkg.name.len > 0) {
                            self.packages.append(pkg) catch {};
                        }
                    }
                }

                std.sort.block(MasonPackage, self.packages.items, {}, struct {
                    fn lessThan(_: void, a: MasonPackage, b: MasonPackage) bool {
                        return std.mem.lessThan(u8, a.name, b.name);
                    }
                }.lessThan);

                self.ensureSelectionValid();
            }
        }
        self.refreshHealth(rpc);
    }

    fn asyncRefreshComplete(context: ?*anyopaque, completion: *@import("../../nvim/async_transport.zig").Completion) anyerror!void {
        const self: *MasonWidget = @ptrCast(@alignCast(context.?));
        switch (completion.outcome) {
            .response => |response| if (response.error_value == .nil) self.applyPackageResult(response.result),
            .failed => {},
        }
    }

    fn applyPackageResult(self: *MasonWidget, res: Value) void {
        if (res != .array) return;
        _ = self.arena.reset(.retain_capacity);
        self.packages.clearRetainingCapacity();
        for (res.array) |item| {
            if (item != .map) continue;
            var pkg: MasonPackage = .{ .name = "", .tabs = std.EnumSet(MasonTab).empty };
            for (item.map) |kv| {
                if (kv.key != .string) continue;
                if (std.mem.eql(u8, kv.key.string, "name") and kv.value == .string) pkg.name = self.arena.allocator().dupe(u8, kv.value.string) catch "" else if (std.mem.eql(u8, kv.key.string, "installed") and kv.value == .bool) {
                    pkg.is_installed = kv.value.bool;
                    pkg.selected = pkg.is_installed;
                } else if (std.mem.eql(u8, kv.key.string, "categories") and kv.value == .array) for (kv.value.array) |category| if (category == .string) if (MasonTab.fromString(category.string)) |tab| pkg.tabs.insert(tab);
            }
            if (pkg.name.len > 0) self.packages.append(pkg) catch {};
        }
        std.sort.block(MasonPackage, self.packages.items, {}, struct {
            fn lessThan(_: void, a: MasonPackage, b: MasonPackage) bool {
                return std.mem.lessThan(u8, a.name, b.name);
            }
        }.lessThan);
        self.ensureSelectionValid();
    }

    fn refreshHealth(self: *MasonWidget, rpc: *RpcClient) void {
        const script =
            \\if not pcall(require, 'mason-registry') then return 'Language tools unavailable. Enable Mason in Settings > Plugins.' end
            \\local active = {}
            \\for _, client in ipairs(vim.lsp.get_clients()) do table.insert(active, client.name) end
            \\local recommended = vim.g.tuim_recommended_servers or {}
            \\local commands = { zls='zls', lua_ls='lua-language-server', pyright='pyright-langserver', rust_analyzer='rust-analyzer', ts_ls='typescript-language-server', gopls='gopls', clangd='clangd' }
            \\local missing = {}
            \\for _, server in ipairs(recommended) do local cmd=commands[server]; if cmd and vim.fn.executable(cmd)==0 then table.insert(missing, cmd) end end
            \\return string.format('Active: %s | Recommended: %s | Missing: %s', #active>0 and table.concat(active, ',') or 'none', #recommended>0 and table.concat(recommended, ',') or 'manual', #missing>0 and table.concat(missing, ',') or 'none')
        ;
        var params = [_]Value{ .{ .string = script }, .{ .array = &[_]Value{} } };
        if (rpc.isAsyncEnabled()) {
            _ = rpc.requestAsyncWithHandler("nvim_exec_lua", &params, self, asyncHealthComplete) catch return;
            return;
        }
        if (rpc.call("nvim_exec_lua", &params) catch null) |res| {
            defer msgpack.freeValue(res, self.allocator);
            if (res == .string) {
                const len = @min(res.string.len, self.health_summary.len);
                @memcpy(self.health_summary[0..len], res.string[0..len]);
                self.health_len = len;
            }
        }
    }

    fn asyncHealthComplete(context: ?*anyopaque, completion: *@import("../../nvim/async_transport.zig").Completion) anyerror!void {
        const self: *MasonWidget = @ptrCast(@alignCast(context.?));
        switch (completion.outcome) {
            .response => |response| if (response.error_value == .nil and response.result == .string) {
                const len = @min(response.result.string.len, self.health_summary.len);
                @memcpy(self.health_summary[0..len], response.result.string[0..len]);
                self.health_len = len;
            },
            .failed => {},
        }
    }

    fn matchesSearch(self: *const MasonWidget, pkg: MasonPackage) bool {
        if (self.search_len == 0) return true;
        const query = self.search_query[0..self.search_len];
        return std.ascii.findIgnoreCase(pkg.name, query) != null;
    }

    fn ensureSelectionValid(self: *MasonWidget) void {
        if (self.packages.items.len == 0) return;
        if (self.selected_idx < self.packages.items.len) {
            const pkg = self.packages.items[self.selected_idx];
            if (pkg.tabs.contains(self.selected_tab) and self.matchesSearch(pkg)) return;
        }
        for (self.packages.items, 0..) |pkg, i| {
            if (pkg.tabs.contains(self.selected_tab) and self.matchesSearch(pkg)) {
                self.selected_idx = i;
                return;
            }
        }
    }

    fn pendingCount(self: *const MasonWidget) usize {
        var count: usize = 0;
        for (self.packages.items) |pkg| {
            if (pkg.selected != pkg.is_installed) count += 1;
        }
        return count;
    }

    fn setStatus(self: *MasonWidget, status: InstallStatus, msg: []const u8) void {
        self.install_status = status;
        const copy_len = @min(msg.len, self.status_message.len);
        @memcpy(self.status_message[0..copy_len], msg[0..copy_len]);
        self.status_len = copy_len;
    }

    pub fn draw(self: *const MasonWidget, ren: *renderer.Renderer, screen_w: u16, screen_h: u16, theme: anytype) void {
        if (!self.is_open) return;
        const modal = primitives.Modal.centered(screen_w, screen_h, 84, 30, 2);
        const x = modal.rect.x;
        const y = modal.rect.y;
        const w = modal.rect.w;
        const h = modal.rect.h;

        if (!primitives.usable(modal, 40, 15)) {
            primitives.drawSizeWarning(ren, "Mason Package Manager", theme.fg_primary, theme.bg_sidebar);
            return;
        }

        primitives.drawModalFrame(ren, modal, .rounded, theme.fg_primary, theme.bg_sidebar, theme.border_color, theme.bg_editor);

        // Close button
        ren.drawText(x + w - 3, y, " × ", .{ .rgb = .{ .r = 255, .g = 85, .b = 85 } }, theme.bg_sidebar, true, false);

        // Header
        ren.drawText(x + 2, y, "  Mason Package Manager ", theme.fg_accent, theme.bg_sidebar, true, false);
        if (self.health_len > 0 and w > 8) {
            ren.drawTextClipped(x + 2, y + 1, w - 4, self.health_summary[0..self.health_len], theme.fg_secondary, theme.bg_sidebar, false, false);
        }

        // Search bar
        const search_x = x + 28;
        if (self.is_searching or self.search_len > 0) {
            var search_buf: [80]u8 = undefined;
            const display_query = if (self.search_len > 0) self.search_query[0..self.search_len] else "";
            const search_line = std.fmt.bufPrint(&search_buf, " 🔍 {s}{s} ", .{ display_query, if (self.is_searching) "▌" else "" }) catch "";
            ren.drawControlText(search_x, y, search_line, theme.fg_primary, theme.bg_sidebar, false, false);
        } else {
            ren.drawControlText(search_x, y, " [/] search ", theme.fg_secondary, theme.bg_sidebar, false, false);
        }

        // Stats (installed/total for current tab+search)
        var tab_total: usize = 0;
        var tab_installed: usize = 0;
        var tab_selected: usize = 0;
        for (self.packages.items) |pkg| {
            if (pkg.tabs.contains(self.selected_tab) and self.matchesSearch(pkg)) {
                tab_total += 1;
                if (pkg.is_installed) tab_installed += 1;
                if (pkg.selected) tab_selected += 1;
            }
        }
        var stats_buf: [64]u8 = undefined;
        const stats = std.fmt.bufPrint(&stats_buf, " {d} installed · {d} selected ", .{ tab_installed, tab_selected }) catch "";
        if (stats.len + 2 < w) {
            ren.drawText(x + w - 2 - @as(u16, @intCast(stats.len)), y + 2, stats, theme.fg_secondary, theme.bg_sidebar, false, false);
        }

        // Tab bar
        const tab_y = y + 2;
        var tx: u16 = x + 2;
        inline for (std.meta.tags(MasonTab)) |tab_enum| {
            const label = tab_enum.label();
            const is_selected = (self.selected_tab == tab_enum);
            const fg = if (is_selected) theme.bg_sidebar else theme.fg_primary;
            const bg = if (is_selected) theme.fg_accent else theme.bg_sidebar;
            ren.drawControlText(tx, tab_y, label, fg, bg, is_selected, false);
            tx += @as(u16, @intCast(label.len)) + 1;
        }

        // Separator under tabs
        for (x + 1..x + w - 1) |bx| {
            ren.drawText(@intCast(bx), tab_y + 1, "─", theme.border_color, theme.bg_sidebar, false, false);
        }

        // Column header
        const header_y = tab_y + 2;
        ren.drawText(x + 2, header_y, "  ", theme.fg_secondary, theme.bg_sidebar, false, false);
        ren.drawText(x + 6, header_y, "Package Name", theme.fg_secondary, theme.bg_sidebar, false, false);
        ren.drawText(x + w - 14, header_y, "Status", theme.fg_secondary, theme.bg_sidebar, false, false);

        // List
        const list_y = header_y + 1;
        const visible_items = h -| 10;

        var rendered_count: usize = 0;
        var skipped_count: usize = 0;
        for (self.packages.items, 0..) |pkg, i| {
            if (!pkg.tabs.contains(self.selected_tab) or !self.matchesSearch(pkg)) continue;

            if (skipped_count < self.scroll_offset) {
                skipped_count += 1;
                continue;
            }

            if (rendered_count >= visible_items) break;

            const py = list_y + @as(u16, @intCast(rendered_count));
            defer ren.highlightHover(.{ .x = x + 1, .y = py, .w = w - 2, .h = 1 }, theme.bg_sidebar, theme.fg_primary);
            const is_cursor = (i == self.selected_idx);

            // Row background
            const row_bg = if (is_cursor) theme.bg_editor else theme.bg_sidebar;
            const row_fg = if (is_cursor) theme.fg_accent else theme.fg_primary;
            for (x + 1..x + w - 1) |bx| {
                ren.drawText(@intCast(bx), py, " ", row_fg, row_bg, false, false);
            }

            // Cursor indicator
            if (is_cursor) {
                ren.drawText(x + 2, py, "▶", theme.fg_accent, row_bg, true, false);
            }

            // Checkbox: [x] if selected, [ ] if not
            const checkbox = if (pkg.selected) "[✓]" else "[ ]";
            const check_fg: Color = if (pkg.selected) theme.fg_accent else theme.fg_secondary;
            ren.drawText(x + 4, py, checkbox, check_fg, row_bg, pkg.selected, false);

            // Package name (truncated)
            const max_name = w -| 22;
            const display_name = if (pkg.name.len > max_name) pkg.name[0..max_name] else pkg.name;
            ren.drawText(x + 9, py, display_name, row_fg, row_bg, false, false);

            // Status badge on the right
            const status_str = if (pkg.is_installed and pkg.selected)
                " installed "
            else if (pkg.is_installed and !pkg.selected)
                " removing  "
            else if (!pkg.is_installed and pkg.selected)
                " pending   "
            else
                "           ";

            const status_color: Color = if (pkg.is_installed and pkg.selected)
                .{ .rgb = .{ .r = 80, .g = 200, .b = 120 } }
            else if (pkg.is_installed and !pkg.selected)
                .{ .rgb = .{ .r = 255, .g = 140, .b = 60 } }
            else if (!pkg.is_installed and pkg.selected)
                .{ .rgb = .{ .r = 100, .g = 160, .b = 255 } }
            else
                theme.fg_secondary;

            ren.drawText(x + w - 13, py, status_str, status_color, row_bg, false, false);

            rendered_count += 1;
        }

        if (rendered_count == 0) {
            const message = if (self.search_len > 0) "No packages match this search." else "No packages available. Refresh Mason or check the log.";
            ren.drawTextClipped(x + 3, list_y + 1, w -| 6, message, theme.fg_secondary, theme.bg_sidebar, false, false);
        }

        // Scrollbar
        if (tab_total > visible_items) {
            const scroll_h = visible_items -| 2;
            const scroll_y = list_y + 1;
            const max_scroll = tab_total - visible_items;
            const pos = @as(u16, @intCast((self.scroll_offset * scroll_h) / (max_scroll + 1)));
            for (0..scroll_h) |si| {
                const char = if (si == pos) "█" else "░";
                ren.drawText(x + w - 2, scroll_y + @as(u16, @intCast(si)), char, theme.fg_accent, theme.bg_sidebar, false, false);
            }
        }

        // Bottom separator
        const footer_sep_y = y + h - 3;
        for (x + 1..x + w - 1) |bx| {
            ren.drawText(@intCast(bx), footer_sep_y, "─", theme.border_color, theme.bg_sidebar, false, false);
        }

        // Footer hints (left side)
        const footer_y = y + h - 2;
        ren.drawText(x + 2, footer_y, " Space/click: toggle  ↑↓: navigate  /: search ", theme.fg_secondary, theme.bg_sidebar, false, false);

        // "[ Install & Close ]" button — bottom right like settings
        const pending = self.pendingCount();
        var btn_buf: [32]u8 = undefined;
        const btn_label = if (pending > 0)
            std.fmt.bufPrint(&btn_buf, "Install ({d})", .{pending}) catch "Install"
        else
            "Install & Close";
        const btn_w = @as(u16, @intCast(btn_label.len)) + 2;
        const install_button = primitives.Button{ .rect = .{ .x = x + w - 2 - btn_w, .y = footer_y, .w = btn_w, .h = 1 }, .state = if (pending > 0) .selected else .normal };
        install_button.draw(ren, btn_label, .{ .fg = theme.fg_secondary, .bg = theme.bg_sidebar, .accent_fg = theme.fg_primary, .accent_bg = theme.fg_accent, .muted_fg = theme.fg_secondary });

        // Status overlay (shown during/after install)
        if (self.install_status != .idle) {
            const ow: u16 = @min(50, w -| 4);
            const oh: u16 = 7;
            const ox: u16 = x + (w -| ow) / 2;
            const oy: u16 = y + (h -| oh) / 2;
            const overlay = primitives.Modal{ .rect = .{ .x = ox, .y = oy, .w = ow, .h = oh } };
            primitives.drawModalFrame(ren, overlay, .rounded, theme.fg_primary, theme.bg_editor, theme.border_color, theme.bg_editor);

            switch (self.install_status) {
                .installing => {
                    ren.drawText(ox + 2, oy, " Installing... ", theme.fg_accent, theme.bg_editor, true, false);
                    ren.drawText(ox + 2, oy + 2, "Mason is installing your packages.", theme.fg_primary, theme.bg_editor, false, false);
                    ren.drawText(ox + 2, oy + 3, "This may take a moment...", theme.fg_secondary, theme.bg_editor, false, false);
                    ren.drawText(ox + 2, oy + 5, "[ Please wait ]", theme.fg_secondary, theme.bg_editor, false, false);
                },
                .success => {
                    ren.drawText(ox + 2, oy, " ✓ Done ", .{ .rgb = .{ .r = 80, .g = 200, .b = 120 } }, theme.bg_editor, true, false);
                    ren.drawText(ox + 2, oy + 2, "Packages installed successfully!", .{ .rgb = .{ .r = 80, .g = 200, .b = 120 } }, theme.bg_editor, true, false);
                    const msg = self.status_message[0..self.status_len];
                    if (msg.len > 0) {
                        ren.drawText(ox + 2, oy + 3, msg, theme.fg_secondary, theme.bg_editor, false, false);
                    }
                    ren.drawText(ox + 2, oy + 5, "[ Press any key or click to close ]", theme.fg_secondary, theme.bg_editor, false, false);
                },
                .err => {
                    ren.drawText(ox + 2, oy, " ✗ Error ", .{ .rgb = .{ .r = 255, .g = 85, .b = 85 } }, theme.bg_editor, true, false);
                    ren.drawText(ox + 2, oy + 2, "Some packages may have failed.", .{ .rgb = .{ .r = 255, .g = 140, .b = 60 } }, theme.bg_editor, false, false);
                    const msg = self.status_message[0..self.status_len];
                    if (msg.len > 0) {
                        ren.drawText(ox + 2, oy + 3, msg, theme.fg_secondary, theme.bg_editor, false, false);
                    }
                    ren.drawText(ox + 2, oy + 5, "[ Press any key or click to close ]", theme.fg_secondary, theme.bg_editor, false, false);
                },
                .idle => {},
            }
        }
    }

    pub fn handleMouse(self: *MasonWidget, m: input.MouseEvent, screen_w: u16, screen_h: u16, rpc: *RpcClient) bool {
        if (!self.is_open) return false;

        const modal = primitives.Modal.centered(screen_w, screen_h, 84, 30, 2);
        const x = modal.rect.x;
        const y = modal.rect.y;
        const w = modal.rect.w;
        const h = modal.rect.h;

        if (!primitives.usable(modal, 40, 15)) {
            if (m.action == .press) self.is_open = false;
            return true;
        }

        // If status overlay is showing, any click dismisses it
        if (self.install_status == .success or self.install_status == .err) {
            if (m.action == .press) {
                self.install_status = .idle;
                self.is_open = false;
            }
            return true;
        }

        if (modal.contains(m.col, m.row)) {
            // Close button
            if (m.action == .press and primitives.containsRect(modal.closeButton(), m.col, m.row)) {
                self.is_open = false;
                return true;
            }

            // Scroll wheel
            if (m.button == .wheel_up) {
                var tab_total: usize = 0;
                for (self.packages.items) |pkg| if (pkg.tabs.contains(self.selected_tab) and self.matchesSearch(pkg)) {
                    tab_total += 1;
                };
                var list = primitives.ListViewport{ .rect = .{ .x = x + 1, .y = y + 8, .w = w -| 2, .h = h -| 10 }, .item_count = tab_total, .offset = self.scroll_offset };
                list.scroll(-1);
                self.scroll_offset = list.offset;
                return true;
            } else if (m.button == .wheel_down) {
                var tab_total: usize = 0;
                for (self.packages.items) |pkg| if (pkg.tabs.contains(self.selected_tab) and self.matchesSearch(pkg)) {
                    tab_total += 1;
                };
                var list = primitives.ListViewport{ .rect = .{ .x = x + 1, .y = y + 8, .w = w -| 2, .h = h -| 10 }, .item_count = tab_total, .offset = self.scroll_offset };
                list.scroll(1);
                self.scroll_offset = list.offset;
                return true;
            }

            if (m.action == .press) {
                // Tab bar click
                const tab_y = y + 2;
                if (m.row == tab_y) {
                    var ttx: u16 = x + 2;
                    inline for (std.meta.tags(MasonTab)) |tab_enum| {
                        const label_len = tab_enum.label().len;
                        if (m.col >= ttx and m.col < ttx + label_len) {
                            self.selected_tab = tab_enum;
                            self.scroll_offset = 0;
                            self.ensureSelectionValid();
                            return true;
                        }
                        ttx += @as(u16, @intCast(label_len)) + 1;
                    }
                }

                // List item click — toggle selection
                const list_y = tab_y + 3;
                const visible_items = h -| 10;
                if (m.row >= list_y and m.row < list_y + visible_items) {
                    const click_row = m.row - list_y;
                    var current_row: u16 = 0;
                    var skipped: usize = 0;
                    for (self.packages.items, 0..) |*pkg, i| {
                        if (!pkg.tabs.contains(self.selected_tab) or !self.matchesSearch(pkg.*)) continue;
                        if (skipped < self.scroll_offset) {
                            skipped += 1;
                            continue;
                        }
                        if (current_row == click_row) {
                            self.selected_idx = i;
                            pkg.selected = !pkg.selected;
                            return true;
                        }
                        current_row += 1;
                        if (current_row >= visible_items) break;
                    }
                }

                // "Install & Close" button click
                const footer_y = y + h - 2;
                if (m.row == footer_y) {
                    var btn_buf: [32]u8 = undefined;
                    const pending = self.pendingCount();
                    const btn_label = if (pending > 0)
                        std.fmt.bufPrint(&btn_buf, "Install ({d})", .{pending}) catch "Install"
                    else
                        "Install & Close";
                    const btn_w = @as(u16, @intCast(btn_label.len)) + 2;
                    const install_button = primitives.Button{ .rect = .{ .x = x + w - 2 - btn_w, .y = footer_y, .w = btn_w, .h = 1 } };
                    if (install_button.hit(m.col, m.row)) {
                        self.installAndClose(rpc);
                        return true;
                    }
                }
            }
            return true;
        }
        return false;
    }

    pub fn handleKey(self: *MasonWidget, key: []const u8, rpc: *RpcClient) bool {
        if (!self.is_open) return false;

        // If status overlay showing, any key dismisses it
        if (self.install_status == .success or self.install_status == .err) {
            self.install_status = .idle;
            self.is_open = false;
            return true;
        }

        if (self.is_searching) {
            if (std.mem.eql(u8, key, "<Esc>") or std.mem.eql(u8, key, "<Enter>")) {
                self.is_searching = false;
                return true;
            } else if (std.mem.eql(u8, key, "<BS>")) {
                if (self.search_len > 0) {
                    self.search_len -= 1;
                    self.scroll_offset = 0;
                    self.ensureSelectionValid();
                }
                return true;
            } else if (key.len == 1 and std.ascii.isPrint(key[0])) {
                if (self.search_len < self.search_query.len) {
                    self.search_query[self.search_len] = key[0];
                    self.search_len += 1;
                    self.scroll_offset = 0;
                    self.ensureSelectionValid();
                }
                return true;
            }
        }

        if (std.mem.eql(u8, key, "<Esc>")) {
            self.is_open = false;
            return true;
        } else if (std.mem.eql(u8, key, "/")) {
            self.is_searching = true;
            return true;
        } else if (std.mem.eql(u8, key, "<Down>") or std.mem.eql(u8, key, "j")) {
            var next_idx = self.selected_idx + 1;
            while (next_idx < self.packages.items.len) : (next_idx += 1) {
                if (self.packages.items[next_idx].tabs.contains(self.selected_tab) and self.matchesSearch(self.packages.items[next_idx])) {
                    self.selected_idx = next_idx;
                    self.ensureVisible();
                    break;
                }
            }
            return true;
        } else if (std.mem.eql(u8, key, "<Up>") or std.mem.eql(u8, key, "k")) {
            if (self.selected_idx > 0) {
                var prev_idx = self.selected_idx - 1;
                while (true) : (prev_idx -= 1) {
                    if (self.packages.items[prev_idx].tabs.contains(self.selected_tab) and self.matchesSearch(self.packages.items[prev_idx])) {
                        self.selected_idx = prev_idx;
                        self.ensureVisible();
                        break;
                    }
                    if (prev_idx == 0) break;
                }
            }
            return true;
        } else if (std.mem.eql(u8, key, " ")) {
            // Toggle selection
            if (self.packages.items.len > 0 and self.selected_idx < self.packages.items.len) {
                self.packages.items[self.selected_idx].selected = !self.packages.items[self.selected_idx].selected;
            }
            return true;
        } else if (std.mem.eql(u8, key, "<Enter>")) {
            // Enter = install & close
            self.installAndClose(rpc);
            return true;
        } else if (key.len == 1 and key[0] >= '1' and key[0] <= '6') {
            const tab_idx = key[0] - '1';
            self.selected_tab = @as(MasonTab, @enumFromInt(tab_idx));
            self.scroll_offset = 0;
            self.ensureSelectionValid();
            return true;
        }
        return true;
    }

    fn ensureVisible(self: *MasonWidget) void {
        const visible_items = 18;
        var count_in_tab: usize = 0;
        var idx_in_tab: ?usize = null;
        for (self.packages.items, 0..) |pkg, i| {
            if (!pkg.tabs.contains(self.selected_tab) or !self.matchesSearch(pkg)) continue;
            if (i == self.selected_idx) idx_in_tab = count_in_tab;
            count_in_tab += 1;
        }
        if (idx_in_tab) |it| {
            if (it < self.scroll_offset) {
                self.scroll_offset = it;
            } else if (it >= self.scroll_offset + visible_items) {
                self.scroll_offset = it - visible_items + 1;
            }
        }
    }

    fn installAndClose(self: *MasonWidget, rpc: *RpcClient) void {
        var buf: [16384]u8 = undefined;
        var offset: usize = 0;

        const header =
            \\local ok, registry = pcall(require, 'mason-registry')
            \\if not ok then return "error: mason not available" end
            \\local to_install = {}
            \\local to_uninstall = {}
        ;
        std.mem.copyForwards(u8, buf[offset..], header);
        offset += header.len;

        var count: usize = 0;
        for (self.packages.items) |pkg| {
            if (pkg.selected != pkg.is_installed) {
                count += 1;
                if (pkg.selected) {
                    const line = std.fmt.bufPrint(buf[offset..], "\ntable.insert(to_install, '{s}')", .{pkg.name}) catch continue;
                    offset += line.len;
                } else {
                    const line = std.fmt.bufPrint(buf[offset..], "\ntable.insert(to_uninstall, '{s}')", .{pkg.name}) catch continue;
                    offset += line.len;
                }
            }
        }

        if (count == 0) {
            self.is_open = false;
            return;
        }

        const footer =
            \\
            \\if #to_install > 0 then
            \\    vim.schedule(function()
            \\        vim.cmd('MasonInstall ' .. table.concat(to_install, ' '))
            \\    end)
            \\end
            \\if #to_uninstall > 0 then
            \\    vim.schedule(function()
            \\        vim.cmd('MasonUninstall ' .. table.concat(to_uninstall, ' '))
            \\    end)
            \\end
            \\return 'ok'
        ;
        const footer_written = std.fmt.bufPrint(buf[offset..], "{s}", .{footer}) catch "";
        offset += footer_written.len;

        self.setStatus(.installing, "");

        var cmd_p = self.allocator.alloc(Value, 2) catch {
            self.setStatus(.err, "Out of memory");
            return;
        };
        defer self.allocator.free(cmd_p);
        cmd_p[0] = .{ .string = buf[0..offset] };
        cmd_p[1] = .{ .array = &[_]Value{} };

        if (rpc.isAsyncEnabled()) {
            _ = rpc.requestAsyncWithHandler("nvim_exec_lua", cmd_p, self, asyncInstallComplete) catch {
                self.setStatus(.err, "RPC queue is full");
                return;
            };
            return;
        }

        if (rpc.call("nvim_exec_lua", cmd_p) catch null) |res| {
            defer msgpack.freeValue(res, self.allocator);
            if (res == .string) {
                if (std.mem.startsWith(u8, res.string, "error:")) {
                    const msg = if (res.string.len > 6) res.string[6..] else "unknown error";
                    const copy_len = @min(msg.len, 80);
                    self.setStatus(.err, msg[0..copy_len]);
                } else {
                    // Success — update installed states
                    for (self.packages.items) |*pkg| {
                        pkg.is_installed = pkg.selected;
                    }
                    var msg_buf: [64]u8 = undefined;
                    const msg = std.fmt.bufPrint(&msg_buf, "{d} package(s) processed.", .{count}) catch "";
                    self.setStatus(.success, msg);
                }
            } else {
                // No string return — assume success (Mason ops are async)
                for (self.packages.items) |*pkg| {
                    pkg.is_installed = pkg.selected;
                }
                var msg_buf: [64]u8 = undefined;
                const msg = std.fmt.bufPrint(&msg_buf, "{d} package(s) queued for install.", .{count}) catch "";
                self.setStatus(.success, msg);
            }
        } else {
            self.setStatus(.err, "RPC call failed");
        }
    }

    fn asyncInstallComplete(context: ?*anyopaque, completion: *@import("../../nvim/async_transport.zig").Completion) anyerror!void {
        const self: *MasonWidget = @ptrCast(@alignCast(context.?));
        const response = switch (completion.outcome) {
            .response => |value| value,
            .failed => {
                self.setStatus(.err, "RPC channel closed");
                return;
            },
        };
        if (response.error_value != .nil) {
            self.setStatus(.err, "Neovim RPC error");
            return;
        }
        if (response.result != .string) return;
        if (std.mem.startsWith(u8, response.result.string, "error:")) {
            const message = if (response.result.string.len > 6) response.result.string[6..] else "unknown error";
            self.setStatus(.err, message[0..@min(message.len, 80)]);
            return;
        }
        var count: usize = 0;
        for (self.packages.items) |*pkg| if (pkg.is_installed != pkg.selected) {
            pkg.is_installed = pkg.selected;
            count += 1;
        };
        var buffer: [64]u8 = undefined;
        self.setStatus(.success, std.fmt.bufPrint(&buffer, "{d} package(s) processed.", .{count}) catch "Completed");
    }
};
