const std = @import("std");
const renderer = @import("../renderer.zig");
const Color = renderer.Color;
const msgpack = @import("../../nvim/msgpack.zig");
const Value = msgpack.Value;
const rpc_mod = @import("../../nvim/rpc.zig");
const RpcClient = rpc_mod.RpcClient;
const input = @import("../input.zig");
const primitives = @import("primitives.zig");

pub const LazyTab = enum {
    all,
    loaded,
    lazy,
    updates,

    pub fn label(self: LazyTab) []const u8 {
        return switch (self) {
            .all => " All ",
            .loaded => " Loaded ",
            .lazy => " Lazy ",
            .updates => " Updates ",
        };
    }
};

pub const PluginInfo = struct {
    name: []const u8,
    full_name: []const u8,
    is_loaded: bool = false,
    commit: []const u8 = "",
    description: []const u8 = "",
};

pub const LazyWidget = struct {
    is_open: bool = false,
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    plugins: std.array_list.Managed(PluginInfo),
    scroll_offset: usize = 0,
    selected_idx: usize = 0,
    selected_tab: LazyTab = .all,

    // Search functionality
    search_query: [64]u8 = @splat(0),
    search_len: usize = 0,
    is_searching: bool = false,

    pub fn init(allocator: std.mem.Allocator) LazyWidget {
        return .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .plugins = std.array_list.Managed(PluginInfo).init(allocator),
        };
    }

    pub fn deinit(self: *LazyWidget) void {
        self.arena.deinit();
        self.plugins.deinit();
    }

    pub fn refresh(self: *LazyWidget, rpc: *RpcClient) void {
        const script =
            \\local has_lazy, config = pcall(require, 'lazy.core.config')
            \\if not has_lazy then return {} end
            \\local res = {}
            \\for _, p in pairs(config.plugins) do
            \\    table.insert(res, {
            \\        name = p.name,
            \\        full_name = p[1] or "",
            \\        loaded = (p._.loaded ~= nil),
            \\        commit = p.commit or "",
            \\        description = p.desc or ""
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
            return;
        }

        if (rpc.call("nvim_exec_lua", params) catch null) |res| {
            defer msgpack.freeValue(res, self.allocator);
            if (res == .array) {
                _ = self.arena.reset(.retain_capacity);
                self.plugins.clearRetainingCapacity();

                for (res.array) |item| {
                    if (item == .map) {
                        var p: PluginInfo = .{ .name = "", .full_name = "" };
                        for (item.map) |kv| {
                            if (kv.key == .string) {
                                if (std.mem.eql(u8, kv.key.string, "name") and kv.value == .string) {
                                    p.name = self.arena.allocator().dupe(u8, kv.value.string) catch "";
                                } else if (std.mem.eql(u8, kv.key.string, "full_name") and kv.value == .string) {
                                    p.full_name = self.arena.allocator().dupe(u8, kv.value.string) catch "";
                                } else if (std.mem.eql(u8, kv.key.string, "loaded") and kv.value == .bool) {
                                    p.is_loaded = kv.value.bool;
                                } else if (std.mem.eql(u8, kv.key.string, "commit") and kv.value == .string) {
                                    p.commit = self.arena.allocator().dupe(u8, kv.value.string) catch "";
                                } else if (std.mem.eql(u8, kv.key.string, "description") and kv.value == .string) {
                                    p.description = self.arena.allocator().dupe(u8, kv.value.string) catch "";
                                }
                            }
                        }
                        if (p.name.len > 0) {
                            self.plugins.append(p) catch {};
                        }
                    }
                }

                // Sort alphabetically
                std.sort.block(PluginInfo, self.plugins.items, {}, struct {
                    fn lessThan(_: void, a: PluginInfo, b: PluginInfo) bool {
                        return std.mem.lessThan(u8, a.name, b.name);
                    }
                }.lessThan);

                self.ensureSelectionValid();
            }
        }
    }

    fn asyncRefreshComplete(context: ?*anyopaque, completion: *@import("../../nvim/async_transport.zig").Completion) anyerror!void {
        const self: *LazyWidget = @ptrCast(@alignCast(context.?));
        const response = switch (completion.outcome) {
            .response => |value| value,
            .failed => return,
        };
        if (response.error_value != .nil) return;
        const res = response.result;
        if (res != .array) return;
        _ = self.arena.reset(.retain_capacity);
        self.plugins.clearRetainingCapacity();
        for (res.array) |item| {
            if (item != .map) continue;
            var plugin: PluginInfo = .{ .name = "", .full_name = "" };
            for (item.map) |kv| {
                if (kv.key != .string) continue;
                if (std.mem.eql(u8, kv.key.string, "name") and kv.value == .string) plugin.name = self.arena.allocator().dupe(u8, kv.value.string) catch "" else if (std.mem.eql(u8, kv.key.string, "full_name") and kv.value == .string) plugin.full_name = self.arena.allocator().dupe(u8, kv.value.string) catch "" else if (std.mem.eql(u8, kv.key.string, "loaded") and kv.value == .bool) plugin.is_loaded = kv.value.bool else if (std.mem.eql(u8, kv.key.string, "commit") and kv.value == .string) plugin.commit = self.arena.allocator().dupe(u8, kv.value.string) catch "" else if (std.mem.eql(u8, kv.key.string, "description") and kv.value == .string) plugin.description = self.arena.allocator().dupe(u8, kv.value.string) catch "";
            }
            if (plugin.name.len > 0) self.plugins.append(plugin) catch {};
        }
        std.sort.block(PluginInfo, self.plugins.items, {}, struct {
            fn lessThan(_: void, a: PluginInfo, b: PluginInfo) bool {
                return std.mem.lessThan(u8, a.name, b.name);
            }
        }.lessThan);
    }

    fn matchesSearch(self: *const LazyWidget, p: PluginInfo) bool {
        if (self.search_len == 0) return true;
        const query = self.search_query[0..self.search_len];
        return std.ascii.findIgnoreCase(p.name, query) != null or
            std.ascii.findIgnoreCase(p.full_name, query) != null;
    }

    fn matchesTab(self: *const LazyWidget, p: PluginInfo) bool {
        return switch (self.selected_tab) {
            .all => true,
            .loaded => p.is_loaded,
            .lazy => !p.is_loaded,
            .updates => false, // placeholder
        };
    }

    fn ensureSelectionValid(self: *LazyWidget) void {
        if (self.plugins.items.len == 0) return;

        if (self.selected_idx < self.plugins.items.len) {
            const p = self.plugins.items[self.selected_idx];
            if (self.matchesTab(p) and self.matchesSearch(p)) return;
        }

        for (self.plugins.items, 0..) |p, i| {
            if (self.matchesTab(p) and self.matchesSearch(p)) {
                self.selected_idx = i;
                return;
            }
        }
    }

    pub fn draw(self: *const LazyWidget, ren: *renderer.Renderer, screen_w: u16, screen_h: u16, theme: anytype) void {
        if (!self.is_open) return;

        const modal = primitives.Modal.centered(screen_w, screen_h, 84, 28, 2);
        const x = modal.rect.x;
        const y = modal.rect.y;
        const w = modal.rect.w;
        const h = modal.rect.h;

        if (!primitives.usable(modal, 40, 15)) {
            primitives.drawSizeWarning(ren, "Plugin Manager", theme.fg_primary, theme.bg_sidebar);
            return;
        }

        primitives.drawModalFrame(ren, modal, .square, theme.fg_primary, theme.bg_sidebar, theme.border_color, theme.bg_editor);

        // Red Close Button Top Right
        ren.drawControlText(x + w - 2, y, "X", .{ .rgb = .{ .r = 255, .g = 0, .b = 0 } }, theme.bg_sidebar, true, false);

        // Header
        const header_text = " LAZY.NVIM ";
        ren.drawText(x + 2, y, header_text, theme.bg_sidebar, theme.fg_accent, true, false);

        // Search Bar
        const search_x = x + 13;
        if (self.is_searching or self.search_len > 0) {
            var search_buf: [80]u8 = undefined;
            const display_query = if (self.search_len > 0) self.search_query[0..self.search_len] else "";
            const search_line = std.fmt.bufPrint(&search_buf, " Search: {s}{s} ", .{ display_query, if (self.is_searching) "_" else "" }) catch "";
            ren.drawControlText(search_x, y, search_line, theme.bg_sidebar, theme.fg_primary, false, false);
        } else {
            ren.drawControlText(search_x, y, " [/] Search ", theme.fg_comment, theme.bg_sidebar, false, false);
        }

        // Stats
        var tab_total: usize = 0;
        for (self.plugins.items) |p| {
            if (self.matchesTab(p) and self.matchesSearch(p)) {
                tab_total += 1;
            }
        }
        var buf: [128]u8 = undefined;
        const stats = std.fmt.bufPrint(&buf, " {d} matches ", .{tab_total}) catch "";
        ren.drawText(x + w - 14 - @as(u16, @intCast(stats.len)), y, stats, theme.bg_sidebar, theme.fg_comment, false, false);

        // Tabs
        const tab_y = y + 2;
        var tx: u16 = x + 2;
        inline for (std.meta.tags(LazyTab)) |tab_enum| {
            const label = tab_enum.label();
            const is_selected = (self.selected_tab == tab_enum);
            const fg = if (is_selected) theme.bg_sidebar else theme.fg_primary;
            const bg = if (is_selected) theme.fg_accent else theme.bg_sidebar;
            ren.drawControlText(tx, tab_y, label, fg, bg, is_selected, false);
            tx += @as(u16, @intCast(label.len)) + 1;
        }

        for (x + 1..x + w - 1) |bx| {
            ren.drawText(@intCast(bx), tab_y + 1, "─", theme.border_color, theme.bg_sidebar, false, false);
        }

        // List
        const list_y = tab_y + 4;
        const visible_items = h - 8;

        var rendered_count: usize = 0;
        var skipped_count: usize = 0;

        for (self.plugins.items, 0..) |p, i| {
            if (!self.matchesTab(p) or !self.matchesSearch(p)) continue;

            if (skipped_count < self.scroll_offset) {
                skipped_count += 1;
                continue;
            }

            if (rendered_count >= visible_items) break;

            const py = list_y + @as(u16, @intCast(rendered_count));
            defer ren.highlightHover(.{ .x = x + 1, .y = py, .w = w - 2, .h = 1 }, theme.bg_sidebar, theme.fg_primary);
            const is_selected = (i == self.selected_idx);
            const bg = if (is_selected) theme.bg_editor else theme.bg_sidebar;
            const fg = if (is_selected) theme.fg_accent else theme.fg_primary;

            if (is_selected) {
                for (x + 1..x + w - 1) |bx| {
                    ren.drawText(@intCast(bx), py, " ", fg, bg, false, false);
                }
            }

            const icon = if (p.is_loaded) "⚡" else "💤";

            const max_name_len = w - 12;
            const display_name = if (p.name.len > max_name_len)
                p.name[0 .. max_name_len - 3]
            else
                p.name;
            const dots = if (p.name.len > max_name_len) "..." else "";

            const line = std.fmt.bufPrint(&buf, "{s} {s} {s}{s}", .{ if (is_selected) "»" else " ", icon, display_name, dots }) catch continue;

            ren.drawText(x + 2, py, line, fg, bg, is_selected, false);

            if (p.commit.len > 0) {
                const c_text = if (p.commit.len > 7) p.commit[0..7] else p.commit;
                ren.drawText(x + w - 4 - @as(u16, @intCast(c_text.len)), py, c_text, theme.fg_comment, bg, false, false);
            }

            rendered_count += 1;
        }

        if (rendered_count == 0) {
            const message = if (self.search_len > 0) "No plugins match this search." else "No plugins loaded. Retry synchronization or inspect the log.";
            ren.drawTextClipped(x + 3, list_y + 1, w -| 6, message, theme.fg_secondary, theme.bg_sidebar, false, false);
        }

        // Scrollbar
        if (tab_total > visible_items) {
            const scroll_h = visible_items - 2;
            const scroll_y = list_y + 1;
            const max_scroll = tab_total - visible_items;
            const pos = @as(u16, @intCast((self.scroll_offset * scroll_h) / (max_scroll + 1)));
            for (0..scroll_h) |si| {
                const char = if (si == pos) "█" else "│";
                ren.drawText(x + w - 2, scroll_y + @as(u16, @intCast(si)), char, theme.fg_comment, theme.bg_sidebar, false, false);
            }
        }

        // Footer
        const footer_y = y + h - 2;
        const footer_text = " [/] search | u: update | s: sync | x: clean | <Esc> close ";
        const display_footer = if (footer_text.len > w - 4) footer_text[0 .. w - 7] else footer_text;
        const footer_dots = if (footer_text.len > w - 4) "..." else "";
        const final_footer = std.fmt.bufPrint(&buf, "{s}{s}", .{ display_footer, footer_dots }) catch footer_text;
        ren.drawText(x + 2, footer_y, final_footer, theme.fg_comment, theme.bg_sidebar, false, false);
    }

    pub fn handleMouse(self: *LazyWidget, m: input.MouseEvent, screen_w: u16, screen_h: u16) bool {
        if (!self.is_open) return false;

        const modal = primitives.Modal.centered(screen_w, screen_h, 84, 28, 2);
        const x = modal.rect.x;
        const y = modal.rect.y;
        const h = modal.rect.h;

        if (!primitives.usable(modal, 40, 15)) {
            if (m.action == .press) self.is_open = false;
            return true;
        }

        if (modal.contains(m.col, m.row)) {
            if (m.action == .press and primitives.containsRect(modal.closeButton(), m.col, m.row)) {
                self.is_open = false;
                return true;
            }

            if (m.button == .wheel_up) {
                var tab_total: usize = 0;
                for (self.plugins.items) |p| if (self.matchesTab(p) and self.matchesSearch(p)) {
                    tab_total += 1;
                };
                var list = primitives.ListViewport{ .rect = .{ .x = x + 1, .y = y + 6, .w = modal.rect.w -| 2, .h = h -| 8 }, .item_count = tab_total, .offset = self.scroll_offset };
                list.scroll(-1);
                self.scroll_offset = list.offset;
                return true;
            } else if (m.button == .wheel_down) {
                var tab_total: usize = 0;
                for (self.plugins.items) |p| if (self.matchesTab(p) and self.matchesSearch(p)) {
                    tab_total += 1;
                };
                var list = primitives.ListViewport{ .rect = .{ .x = x + 1, .y = y + 6, .w = modal.rect.w -| 2, .h = h -| 8 }, .item_count = tab_total, .offset = self.scroll_offset };
                list.scroll(1);
                self.scroll_offset = list.offset;
                return true;
            }

            if (m.action == .press) {
                const tab_y = y + 2;
                if (m.row == tab_y) {
                    var tx: u16 = x + 2;
                    inline for (std.meta.tags(LazyTab)) |tab_enum| {
                        const label_len = tab_enum.label().len;
                        if (m.col >= tx and m.col < tx + label_len) {
                            self.selected_tab = tab_enum;
                            self.scroll_offset = 0;
                            self.ensureSelectionValid();
                            return true;
                        }
                        tx += @as(u16, @intCast(label_len)) + 1;
                    }
                }

                const list_y = tab_y + 4;
                const visible_items = h - 8;
                if (m.row >= list_y and m.row < list_y + visible_items) {
                    const click_row = m.row - list_y;
                    var current_row: u16 = 0;
                    var skipped: usize = 0;
                    for (self.plugins.items, 0..) |_, i| {
                        const p = self.plugins.items[i];
                        if (!self.matchesTab(p) or !self.matchesSearch(p)) continue;
                        if (skipped < self.scroll_offset) {
                            skipped += 1;
                            continue;
                        }
                        if (current_row == click_row) {
                            self.selected_idx = i;
                            return true;
                        }
                        current_row += 1;
                        if (current_row >= visible_items) break;
                    }
                }
            }
            return true;
        }
        return false;
    }

    pub fn handleKey(self: *LazyWidget, key: []const u8, rpc: *RpcClient) bool {
        if (!self.is_open) return false;

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
        } else if (std.mem.eql(u8, key, "<Down>")) {
            var next_idx = self.selected_idx + 1;
            while (next_idx < self.plugins.items.len) : (next_idx += 1) {
                const p = self.plugins.items[next_idx];
                if (self.matchesTab(p) and self.matchesSearch(p)) {
                    self.selected_idx = next_idx;
                    self.ensureVisible();
                    break;
                }
            }
            return true;
        } else if (std.mem.eql(u8, key, "<Up>")) {
            if (self.selected_idx > 0) {
                var prev_idx = self.selected_idx - 1;
                while (true) : (prev_idx -= 1) {
                    const p = self.plugins.items[prev_idx];
                    if (self.matchesTab(p) and self.matchesSearch(p)) {
                        self.selected_idx = prev_idx;
                        self.ensureVisible();
                        break;
                    }
                    if (prev_idx == 0) break;
                }
            }
            return true;
        } else if (std.mem.eql(u8, key, "u")) {
            _ = rpc.call("nvim_command", &[_]Value{.{ .string = "Lazy update" }}) catch null;
            return true;
        } else if (std.mem.eql(u8, key, "s")) {
            rpc.notify("nvim_command", &[_]Value{.{ .string = "lua vim.schedule(function() if vim.g.tuim_plugins_disabled then _G.tuim_retry_plugins() else _G.tuim_native_notice('info', 'Synchronizing plugins...'); vim.cmd('Lazy sync') end end)" }}) catch {};
            return true;
        } else if (std.mem.eql(u8, key, "x")) {
            _ = rpc.call("nvim_command", &[_]Value{.{ .string = "Lazy clean" }}) catch null;
            return true;
        } else if (key.len == 1 and key[0] >= '1' and key[0] <= '4') {
            const tab_idx = key[0] - '1';
            self.selected_tab = @as(LazyTab, @enumFromInt(tab_idx));
            self.scroll_offset = 0;
            self.ensureSelectionValid();
            return true;
        }
        return true;
    }

    fn ensureVisible(self: *LazyWidget) void {
        const visible_items = 20;
        var count_in_view: usize = 0;
        var idx_in_view: ?usize = null;
        for (self.plugins.items, 0..) |p, i| {
            if (!self.matchesTab(p) or !self.matchesSearch(p)) continue;
            if (i == self.selected_idx) {
                idx_in_view = count_in_view;
            }
            count_in_view += 1;
        }

        if (idx_in_view) |iv| {
            if (iv < self.scroll_offset) {
                self.scroll_offset = iv;
            } else if (iv >= self.scroll_offset + visible_items) {
                self.scroll_offset = iv - visible_items + 1;
            }
        }
    }
};
