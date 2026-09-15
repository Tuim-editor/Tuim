const std = @import("std");
const RpcClient = @import("rpc.zig").RpcClient;
const msgpack = @import("msgpack.zig");
const Value = msgpack.Value;
const input = @import("../tui/input.zig");
const ui_protocol = @import("ui_protocol.zig");
const UiState = ui_protocol.UiState;
const App = @import("../tui/app.zig").App;
const WinInfo = @import("../tui/app.zig").WinInfo;
const RpcContext = @import("../tui/app.zig").RpcContext;
const theme = @import("../tui/theme.zig");
const Rect = @import("../tui/layout.zig").Rect;
const settings = @import("../tui/widgets/settings.zig");
const metrics = @import("../metrics.zig");

pub fn sendMouseEvent(rpc: *RpcClient, alloc: std.mem.Allocator, m: input.MouseEvent, rel_col: u16, rel_row: u16) void {
    const button_str: []const u8 = switch (m.button) {
        .left => "left",
        .middle => "middle",
        .right => "right",
        .wheel_up => "wheel",
        .wheel_down => "wheel",
        .none => "none",
    };
    if (std.mem.eql(u8, button_str, "none")) return;

    const action_str: []const u8 = switch (m.action) {
        .press => if (m.button == .wheel_up) "up" else if (m.button == .wheel_down) "down" else "press",
        .release => "release",
        .move => "drag",
    };

    var p = alloc.alloc(Value, 6) catch return;
    p[0] = .{ .string = button_str };
    p[1] = .{ .string = action_str };
    p[2] = .{ .string = "" }; // modifier
    p[3] = .{ .integer = 0 }; // grid
    p[4] = .{ .integer = rel_row }; // row
    p[5] = .{ .integer = rel_col }; // col

    rpc.notify("nvim_input_mouse", p) catch {};
    alloc.free(p);
}

pub fn handleNotification(ctx: ?*anyopaque, method: []const u8, params: Value) anyerror!void {
    var state_timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.state_update);
    defer state_timer.stop();
    const rpc_ctx: *RpcContext = @ptrCast(@alignCast(ctx orelse return));
    const ui_state = rpc_ctx.ui_state;
    const app = rpc_ctx.app;

    if (std.mem.eql(u8, method, "redraw") and params == .array) {
        const previous_mode = ui_state.editor_mode;
        const damage = try ui_state.handleRedraw(params.array);
        if (ui_state == app.ui_state and previous_mode != ui_state.editor_mode) app.invalidations.damage(.chrome);
        if (damage.grid or damage.lifecycle or damage.composition_uncertain) {
            // Mapping happens after handleRedraw has applied the whole batch.
            app.invalidations.damage(if (ui_state == app.ui_state) .editor else .drawer);
        }
        if (damage.cursor) app.invalidations.cursor = true;
    } else if (std.mem.eql(u8, method, "tuim_buffers") and ui_state == app.ui_state and params == .array and params.array.len >= 2 and params.array[0] == .array) {
        for (app.tabs.items) |tab| {
            app.allocator.free(tab.name);
            if (tab.path) |path| app.allocator.free(path);
        }
        app.tabs.clearRetainingCapacity();
        var modified_it = app.explorer.neovim_modified.keyIterator();
        while (modified_it.next()) |key| app.allocator.free(key.*);
        app.explorer.neovim_modified.clearRetainingCapacity();

        const active_bufnr = if (params.array[1] == .integer) params.array[1].integer else 0;
        for (params.array[0].array) |entry| {
            if (entry != .map) continue;
            var bufnr: i64 = 0;
            var path: []const u8 = "";
            var relative_path: []const u8 = "";
            var changed = false;
            for (entry.map) |kv| {
                if (kv.key != .string) continue;
                if (std.mem.eql(u8, kv.key.string, "bufnr") and kv.value == .integer) bufnr = kv.value.integer;
                if (std.mem.eql(u8, kv.key.string, "name") and kv.value == .string) path = kv.value.string;
                if (std.mem.eql(u8, kv.key.string, "relative_name") and kv.value == .string) relative_path = kv.value.string;
                if (std.mem.eql(u8, kv.key.string, "changed") and kv.value == .bool) changed = kv.value.bool;
            }
            const display_name = if (path.len == 0) "[No Name]" else std.fs.path.basename(path);
            const name_copy = try app.allocator.dupe(u8, display_name);
            errdefer app.allocator.free(name_copy);
            const path_copy = if (path.len == 0) null else try app.allocator.dupe(u8, path);
            try app.tabs.append(.{ .bufnr = bufnr, .name = name_copy, .path = path_copy, .modified = changed });
            if (changed and relative_path.len > 0) {
                const modified_path = try app.allocator.dupe(u8, relative_path);
                errdefer app.allocator.free(modified_path);
                try app.explorer.neovim_modified.put(modified_path, {});
            }
            if (bufnr == active_bufnr) app.active_tab = app.tabs.items.len - 1;
        }
        if (app.tabs.items.len == 0) app.active_tab = 0;
        app.invalidations.damageAll();
    } else if (std.mem.eql(u8, method, "tuim_telescope_rect")) {
        ui_state.native_picker_chrome = params == .array and params.array.len >= 4 and params.array[3] == .bool and params.array[3].bool;
        app.invalidations.damage(.overlay);
        app.invalidations.damage(.chrome);
        if (params == .array and params.array.len >= 2) {
            for (params.array[0..2], 0..) |p, i| {
                if (p == .array and p.array.len == 4) {
                    const arr = p.array;
                    ui_state.telescope_rects[i] = Rect{
                        .y = @as(u16, @intCast(@max(0, arr[0].integer))),
                        .x = @as(u16, @intCast(@max(0, arr[1].integer))),
                        .w = @as(u16, @intCast(@max(0, arr[2].integer))),
                        .h = @as(u16, @intCast(@max(0, arr[3].integer))),
                    };
                } else {
                    ui_state.telescope_rects[i] = null;
                }
            }
            if (params.array.len >= 3 and params.array[2] == .string) {
                const title = params.array[2].string;
                const len = @min(title.len, 32);
                std.mem.copyForwards(u8, ui_state.widget_title[0..len], title[0..len]);
                ui_state.widget_title_len = len;
            } else {
                ui_state.widget_title_len = 0;
            }
        } else {
            ui_state.telescope_rects[0] = null;
            ui_state.telescope_rects[1] = null;
            ui_state.widget_title_len = 0;
        }
    } else if (std.mem.eql(u8, method, "tuim_open_commands")) {
        app.workspace.palette = true;
        app.workspace.buffer_picker = false;
        app.workspace.editing_shortcut = null;
        app.workspace.shortcut_message = "";
        app.workspace.query_len = 0;
        app.workspace.command_selected = 0;
        app.workspace.command_scroll = 0;
        app.invalidations.damageAll();
    } else if (std.mem.eql(u8, method, "tuim_open_language_tools")) {
        app.settings_widget.is_open = false;
        app.mason_widget.is_open = true;
        app.mason_widget.selected_tab = .lsp;
        app.mason_widget.search_len = 0;
        app.mason_widget.is_searching = false;
        app.mason_widget.selected_idx = 0;
        app.mason_widget.scroll_offset = 0;
        app.mason_widget.refresh(app.rpc);
        app.invalidations.damageAll();
    } else if (std.mem.eql(u8, method, "tuim_toggle_zen")) {
        ui_state.toggle_zen_requested = true;
    } else if (std.mem.eql(u8, method, "tuim_toggle_ide")) {
        ui_state.toggle_ide_requested = true;
    } else if (std.mem.eql(u8, method, "tuim_notice") and params == .array and params.array.len >= 2 and
        params.array[0] == .string and params.array[1] == .string)
    {
        const level: @import("../tui/app.zig").NoticeLevel = if (std.mem.eql(u8, params.array[0].string, "error"))
            .failure
        else if (std.mem.eql(u8, params.array[0].string, "warning"))
            .warning
        else
            .info;
        app.notify(level, "{s}", .{params.array[1].string});
        std.log.info("Neovim notice [{s}]: {s}", .{ params.array[0].string, params.array[1].string });
    } else if (std.mem.eql(u8, method, "tuim_ai_status") and params == .array and params.array.len >= 2 and
        params.array[0] == .string and params.array[1] == .string)
    {
        const active = params.array.len < 3 or params.array[2] != .bool or params.array[2].bool;
        app.ai_panel.updateSession(params.array[0].string, params.array[1].string, active);
        app.invalidations.damageAll();
    } else if (std.mem.eql(u8, method, "tuim_settings_changed")) {
        var old_cfg = app.settings_widget.config;
        if (settings.SettingsConfig.load(app.settings_widget.allocator, app.settings_widget.settings_path)) |new_cfg| {
            app.settings_widget.config = new_cfg;
            old_cfg.deinit(app.settings_widget.allocator);

            if (std.mem.eql(u8, app.settings_widget.config.mode, "zen")) {
                app.mode = .zen;
            } else if (std.mem.eql(u8, app.settings_widget.config.mode, "ide")) {
                app.mode = .ide;
            } else {
                app.mode = .normal;
            }
            if (app.mode != .zen) {
                app.prev_mode = app.mode;
            } else {
                app.settings_widget.is_open = false;
                app.mason_widget.is_open = false;
                app.lazy_widget.is_open = false;
                app.git_detailed_widget.is_open = false;
            }
        } else |err| {
            app.notify(.failure, "Settings reload failed; keeping the current settings.", .{});
            std.log.err("Settings reload failed: {}", .{err});
        }
        app.invalidations.damageAll();
    } else if (std.mem.eql(u8, method, "tuim_win_count") and params == .array and params.array.len > 0) {
        if (params.array[0] == .integer) {
            app.editor_win_count = @as(usize, @intCast(@max(1, params.array[0].integer)));
            app.invalidations.damageAll();
        }
    } else if (std.mem.eql(u8, method, "tuim_win_positions") and params == .array and params.array.len > 0) {
        const wins = if (ui_state == app.ui_state) &app.editor_wins else &app.terminal_wins;
        // Free old name strings before clearing
        for (wins.items) |old_win| {
            if (old_win.name.len > 0) app.allocator.free(old_win.name);
        }
        wins.clearRetainingCapacity();
        const list_val = params.array[0];
        if (list_val == .array) {
            for (list_val.array) |w_val| {
                if (w_val == .map) {
                    var info = WinInfo{ .id = 0, .bufnr = 0, .row = 0, .col = 0, .width = 0, .height = 0, .active = false, .name = "" };
                    for (w_val.map) |kv| {
                        if (kv.key == .string) {
                            const key = kv.key.string;
                            if (std.mem.eql(u8, key, "id") and kv.value == .integer) {
                                info.id = kv.value.integer;
                            } else if (std.mem.eql(u8, key, "bufnr") and kv.value == .integer) {
                                info.bufnr = kv.value.integer;
                            } else if (std.mem.eql(u8, key, "row") and kv.value == .integer) {
                                info.row = @as(u16, @intCast(kv.value.integer));
                            } else if (std.mem.eql(u8, key, "col") and kv.value == .integer) {
                                info.col = @as(u16, @intCast(kv.value.integer));
                            } else if (std.mem.eql(u8, key, "width") and kv.value == .integer) {
                                info.width = @as(u16, @intCast(kv.value.integer));
                            } else if (std.mem.eql(u8, key, "height") and kv.value == .integer) {
                                info.height = @as(u16, @intCast(kv.value.integer));
                            } else if (std.mem.eql(u8, key, "active") and kv.value == .bool) {
                                info.active = kv.value.bool;
                            } else if (std.mem.eql(u8, key, "name") and kv.value == .string) {
                                info.name = app.allocator.dupe(u8, kv.value.string) catch "";
                            }
                        }
                    }
                    wins.append(info) catch {};
                }
            }
        }
        if (ui_state == app.ui_state) {
            app.editor_win_count = app.editor_wins.items.len;
        } else {
            app.terminal_win_count = app.terminal_wins.items.len;
        }

        app.invalidations.damageAll();
    } else if (std.mem.eql(u8, method, "tuim_boundary_hit") and params == .array and params.array.len > 0) {
        if (params.array[0] == .string) {
            const dir = params.array[0].string;
            if (std.mem.eql(u8, dir, "j")) {
                if (app.show_terminal_panel and app.panel_position == .bottom) {
                    app.terminal_focus = true;
                    app.invalidations.damageAll();
                }
            } else if (std.mem.eql(u8, dir, "l")) {
                if (app.show_terminal_panel and app.panel_position == .right) {
                    app.terminal_focus = true;
                    app.invalidations.damageAll();
                }
            } else if (std.mem.eql(u8, dir, "h")) {
                if (app.show_file_tree) {
                    app.sidebar_focus = true;
                    app.invalidations.damageAll();
                }
            }
        }
    } else if (std.mem.eql(u8, method, "tuim_theme_changed") and params == .array and params.array.len > 0) {
        if (params.array[0] == .map) {
            ui_state.theme_changed = true;
            // update theme directly using app.active_theme
            for (params.array[0].map) |kv| {
                if (kv.key == .string and kv.value == .string) {
                    const k = kv.key.string;
                    const v = kv.value.string;
                    if (theme.Theme.parseHexColor(v)) |c| {
                        if (std.mem.eql(u8, k, "bg_editor")) app.active_theme.bg_editor = c;
                        if (std.mem.eql(u8, k, "bg_sidebar")) app.active_theme.bg_sidebar = c;
                        if (std.mem.eql(u8, k, "bg_tab_active")) app.active_theme.bg_tab_active = c;
                        if (std.mem.eql(u8, k, "bg_tab_inactive")) app.active_theme.bg_tab_inactive = c;
                        if (std.mem.eql(u8, k, "bg_statusbar")) app.active_theme.bg_statusbar = c;
                        if (std.mem.eql(u8, k, "fg_statusbar")) app.active_theme.fg_statusbar = c;
                        if (std.mem.eql(u8, k, "bg_terminal")) app.active_theme.bg_terminal = c;
                        if (std.mem.eql(u8, k, "bg_accent")) app.active_theme.bg_accent = c;
                        if (std.mem.eql(u8, k, "fg_primary")) app.active_theme.fg_primary = c;
                        if (std.mem.eql(u8, k, "fg_secondary")) app.active_theme.fg_secondary = c;
                        if (std.mem.eql(u8, k, "fg_accent")) app.active_theme.fg_accent = c;
                        if (std.mem.eql(u8, k, "border_color")) app.active_theme.border_color = c;
                    }
                }
            }
        }
    }
}

pub fn processNvimEvents(rpc: *RpcClient) !bool {
    return try rpc.processNotifications();
}

pub fn openFile(rpc: *RpcClient, allocator: std.mem.Allocator, path: []const u8) !void {
    var params = try allocator.alloc(Value, 2);
    defer allocator.free(params);
    params[0] = .{ .string = "local path = select(1, ...); while #vim.api.nvim_win_get_config(0).relative > 0 do vim.cmd('close') end; vim.cmd('edit ' .. vim.fn.fnameescape(path))" };

    var lua_args = try allocator.alloc(Value, 1);
    defer allocator.free(lua_args);
    lua_args[0] = .{ .string = path };

    params[1] = .{ .array = lua_args };

    try rpc.notify("nvim_exec_lua", params);
}
