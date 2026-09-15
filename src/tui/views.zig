const std = @import("std");
const renderer = @import("renderer.zig");
const Renderer = renderer.Renderer;
const Color = renderer.Color;
const Cell = renderer.Cell;
const Layout = @import("layout.zig").Layout;
const Rect = @import("layout.zig").Rect;
const theme = @import("theme.zig");
const app = @import("app.zig");
const App = app.App;
const workspace = @import("workspace.zig");
const CompositionDamage = @import("invalidation.zig").CompositionDamage;
const Explorer = @import("widgets/explorer.zig").Explorer;

pub const CompositionPlan = struct {
    chrome: bool,
    sidebar: bool,
    editor: bool,
    drawer: bool,
    overlays: bool,

    pub fn init(damage: CompositionDamage, cursor_damage: bool, overlay_visible: bool) CompositionPlan {
        // Overlay movement/closure exposes arbitrary underlying regions, so
        // conservatively rebuild every base layer. Existing visible overlays
        // are then reapplied after any base region they cover.
        const expose_underlay = damage.overlay;
        const any_base = damage.chrome or damage.sidebar or damage.editor or damage.drawer or cursor_damage or expose_underlay;
        return .{
            .chrome = damage.chrome or expose_underlay,
            .sidebar = damage.sidebar or expose_underlay,
            .editor = damage.editor or cursor_damage or expose_underlay,
            // Cursor-only terminal updates (spaces/arrows) must erase the old
            // software cursor even when Neovim sends no changed grid cells.
            .drawer = damage.drawer or cursor_damage or expose_underlay,
            .overlays = overlay_visible and (any_base or damage.overlay),
        };
    }
};

fn clearDamagedRegions(ren: *Renderer, layout: Layout, plan: CompositionPlan, fg: Color, bg: Color) void {
    if (plan.editor) drawRect(ren, layout.editor, " ", fg, bg);
    if (plan.sidebar) {
        drawRect(ren, layout.activity_bar, " ", fg, bg);
        drawRect(ren, layout.file_tree, " ", fg, bg);
    }
    if (plan.chrome) {
        drawRect(ren, layout.tab_bar, " ", fg, bg);
        drawRect(ren, layout.status_bar, " ", fg, bg);
    }
    if (plan.drawer) if (layout.panel) |panel| drawRect(ren, panel, " ", fg, bg);
}

test "composition plan retains unaffected coarse regions" {
    const plan = CompositionPlan.init(.{ .editor = true }, false, false);
    try std.testing.expect(plan.editor);
    try std.testing.expect(!plan.chrome);
    try std.testing.expect(!plan.sidebar);
    try std.testing.expect(!plan.drawer);
    try std.testing.expect(!plan.overlays);
}

test "cursor damage recomposes both cursor surfaces and reapplies visible overlay" {
    const plan = CompositionPlan.init(.{}, true, true);
    try std.testing.expect(plan.editor);
    try std.testing.expect(plan.overlays);
    try std.testing.expect(!plan.chrome);
    try std.testing.expect(!plan.sidebar);
    try std.testing.expect(plan.drawer);
}

test "overlay movement or closure exposes every underlying region" {
    const closed = CompositionPlan.init(.{ .overlay = true }, false, false);
    try std.testing.expect(closed.chrome);
    try std.testing.expect(closed.sidebar);
    try std.testing.expect(closed.editor);
    try std.testing.expect(closed.drawer);
    try std.testing.expect(!closed.overlays);

    const moved = CompositionPlan.init(.{ .overlay = true }, false, true);
    try std.testing.expect(moved.overlays);
}

test "coarse clearing retains unaffected cells and overlay exposure clears all bases" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    var ren = try Renderer.init(std.testing.allocator, 8, 4, &output.writer);
    defer ren.deinit(std.testing.allocator);
    var marker = Cell{};
    marker.setChar("X");
    @memset(ren.buf, marker);
    const layout = Layout{
        .total = .{ .x = 0, .y = 0, .w = 8, .h = 4 },
        .activity_bar = .{ .x = 0, .y = 0, .w = 1, .h = 3 },
        .file_tree = .{ .x = 1, .y = 0, .w = 1, .h = 3 },
        .editor = .{ .x = 2, .y = 1, .w = 4, .h = 2 },
        .tab_bar = .{ .x = 2, .y = 0, .w = 6, .h = 1 },
        .status_bar = .{ .x = 0, .y = 3, .w = 8, .h = 1 },
        .panel = .{ .x = 6, .y = 1, .w = 2, .h = 2 },
    };

    clearDamagedRegions(&ren, layout, CompositionPlan.init(.{ .editor = true }, false, false), .none, .none);
    try std.testing.expectEqual(@as(u8, 'X'), ren.buf[0].char[0]);
    try std.testing.expectEqual(@as(u8, ' '), ren.buf[1 * 8 + 2].char[0]);
    try std.testing.expectEqual(@as(u8, 'X'), ren.buf[1 * 8 + 6].char[0]);

    clearDamagedRegions(&ren, layout, CompositionPlan.init(.{ .overlay = true }, false, false), .none, .none);
    for (ren.buf) |cell| try std.testing.expectEqual(@as(u8, ' '), cell.char[0]);
}

test "overlay closure and drawer shrink leave canonical base cells" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    var ren = try Renderer.init(std.testing.allocator, 6, 3, &output.writer);
    defer ren.deinit(std.testing.allocator);
    var overlay = Cell{};
    overlay.setChar("O");
    @memset(ren.buf, overlay);

    const expanded_editor = Layout{
        .total = .{ .x = 0, .y = 0, .w = 6, .h = 3 },
        .activity_bar = .{ .x = 0, .y = 0, .w = 1, .h = 2 },
        .file_tree = .{ .x = 1, .y = 0, .w = 1, .h = 2 },
        .editor = .{ .x = 2, .y = 1, .w = 4, .h = 1 },
        .tab_bar = .{ .x = 2, .y = 0, .w = 4, .h = 1 },
        .status_bar = .{ .x = 0, .y = 2, .w = 6, .h = 1 },
        .panel = null,
    };
    const expose = CompositionPlan.init(.{ .overlay = true }, false, false);
    clearDamagedRegions(&ren, expanded_editor, expose, .none, .none);

    // Recompose deterministic base markers in z-order. The expanded editor
    // covers the cells formerly owned by a closed/shrunken drawer.
    ren.drawRect(expanded_editor.activity_bar, "S", .none, .none);
    ren.drawRect(expanded_editor.file_tree, "S", .none, .none);
    ren.drawRect(expanded_editor.editor, "E", .none, .none);
    ren.drawRect(expanded_editor.tab_bar, "C", .none, .none);
    ren.drawRect(expanded_editor.status_bar, "C", .none, .none);
    for (ren.buf) |cell| try std.testing.expect(cell.char[0] != 'O');
    try std.testing.expectEqual(@as(u8, 'E'), ren.buf[1 * 6 + 5].char[0]);
}

test "explorer context menu is composed over the sidebar boundary and editor" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    var ren = try Renderer.init(std.testing.allocator, 32, 8, &output.writer);
    defer ren.deinit(std.testing.allocator);

    var explorer = Explorer.init(std.testing.allocator, std.testing.io);
    defer explorer.deinit();
    explorer.show_menu = true;
    explorer.menu_x = 8;
    explorer.menu_y = 1;

    const colors = .{
        .bg_sidebar = Color{ .index = 1 },
        .bg_editor = Color{ .index = 2 },
        .bg_accent = Color{ .index = 3 },
        .fg_primary = Color{ .index = 4 },
        .fg_secondary = Color{ .index = 5 },
        .border_color = Color{ .index = 6 },
        .fg_accent = Color{ .index = 7 },
        .nerd_fonts = false,
    };
    const sidebar = Rect{ .x = 0, .y = 0, .w = 16, .h = 7 };
    explorer.draw(&ren, sidebar, colors);

    // These later base layers used to erase the part of the 16-column menu
    // that extends beyond its x=8 origin and across the x=15 delimiter.
    ren.drawRect(.{ .x = 16, .y = 0, .w = 16, .h = 7 }, "E", .none, .none);
    ren.drawText(15, 1, "│", .none, .none, false, false);
    explorer.drawOverlay(&ren, colors);

    try std.testing.expectEqualStrings("─", ren.buf[1 * ren.width + 16].char[0..3]);
    try std.testing.expectEqual(@as(u8, 'N'), ren.buf[2 * ren.width + 12].char[0]);
}

fn drawRect(ren: *Renderer, rect: Rect, char: []const u8, fg: Color, bg: Color) void {
    ren.drawRect(rect, char, fg, bg);
}

fn drawText(ren: *Renderer, x: u16, y: u16, text: []const u8, fg: Color, bg: Color, bold: bool, italic: bool) void {
    ren.drawText(x, y, text, fg, bg, bold, italic);
}

fn overlayVisible(a: *App) bool {
    return a.ui_state.telescope_rects[0] != null or a.ui_state.telescope_rects[1] != null or
        a.settings_widget.is_open or a.mason_widget.is_open or a.lazy_widget.is_open or
        a.git_detailed_widget.is_open or a.extension_shop.is_open or a.show_split_menu or
        a.activeNotice() != null or a.explorer.show_menu or a.editor_context_menu.is_open or
        a.bug_report.is_open or a.workspace.palette;
}

pub fn drawWorkspace(a: *App, layout: Layout, damage: CompositionDamage, cursor_damage: bool) void {
    const chrome = a.active_theme.chrome();
    const t = &chrome;
    const plan = CompositionPlan.init(damage, cursor_damage, overlayVisible(a));
    const pointer = a.ren.pointer_position;
    defer a.ren.pointer_position = pointer;
    // A modal owns interaction; controls behind it must not respond to hover.
    if (a.workspace.palette or a.settings_widget.is_open or a.mason_widget.is_open or
        a.lazy_widget.is_open or a.git_detailed_widget.is_open or
        a.bug_report.is_open or a.editor_context_menu.is_open)
        a.ren.pointer_position = null;

    clearDamagedRegions(a.ren, layout, plan, t.fg_primary, t.bg_editor);

    // Draw grid 1 (global grid) first for cmdline, messages, and global statusline
    if (plan.editor and a.ui_state.grid.width > 0 and a.ui_state.grid.height > 0) {
        var gy: u16 = 0;
        while (gy < a.ui_state.grid.height) : (gy += 1) {
            const sy_i = @as(i32, @intCast(layout.editor.y)) + @as(i32, @intCast(gy));
            if (sy_i < 0 or sy_i >= @as(i32, @intCast(layout.editor.y + layout.editor.h))) continue;
            const sy = @as(u16, @intCast(sy_i));
            var gx: u16 = 0;
            while (gx < a.ui_state.grid.width) : (gx += 1) {
                const sx_i = @as(i32, @intCast(layout.editor.x)) + @as(i32, @intCast(gx));
                if (sx_i < 0 or sx_i >= @as(i32, @intCast(layout.editor.x + layout.editor.w))) continue;
                const sx = @as(u16, @intCast(sx_i));
                var cell = a.ui_state.grid.cells[@as(usize, gy) * @as(usize, a.ui_state.grid.width) + gx];

                // Only draw if there's actual content or different background
                if (cell.char[0] == ' ' and cell.char[1] == 0 and std.meta.activeTag(cell.bg) == .none) {
                    continue;
                }

                if (std.meta.eql(cell.bg, a.ui_state.default_bg) or std.meta.activeTag(cell.bg) == .none) {
                    cell.bg = t.bg_editor;
                }
                if (std.meta.eql(cell.fg, a.ui_state.default_fg) or std.meta.activeTag(cell.fg) == .none) {
                    cell.fg = t.fg_primary;
                }
                if (cell.reverse) {
                    const tmp = cell.fg;
                    cell.fg = cell.bg;
                    cell.bg = tmp;
                }
                a.ren.setCell(sx, sy, cell);
            }
        }
    }

    // With ext_multigrid, editor content lives on secondary grids (grid 2+).
    // Render regular (non-float) windows first, then floats on top.
    // Two passes: pass 0 = regular windows, pass 1 = floats
    if (plan.editor) {
        for (0..2) |pass| {
            for (a.ui_state.secondary_grids.items) |*entry| {
                const fg = &entry.data;
                // pass 0 = regular windows, pass 1 = floats
                if (pass == 0 and fg.is_float) continue;
                if (pass == 1 and !fg.is_float) continue;
                if (!fg.visible or fg.width == 0 or fg.height == 0) continue;
                var gy: u16 = 0;
                while (gy < fg.height) : (gy += 1) {
                    const sy_i = @as(i32, @intCast(layout.editor.y)) + fg.row + @as(i32, @intCast(gy));
                    if (sy_i < 0 or sy_i >= @as(i32, @intCast(layout.editor.y + layout.editor.h))) continue;
                    const sy = @as(u16, @intCast(sy_i));

                    var gx: u16 = 0;
                    while (gx < fg.width) : (gx += 1) {
                        const sx_i = @as(i32, @intCast(layout.editor.x)) + fg.col + @as(i32, @intCast(gx));
                        if (sx_i < 0 or sx_i >= @as(i32, @intCast(layout.editor.x + layout.editor.w))) continue;
                        const sx = @as(u16, @intCast(sx_i));
                        var cell = fg.cells[@as(usize, gy) * @as(usize, fg.width) + gx];
                        if (std.meta.eql(cell.bg, a.ui_state.default_bg) or std.meta.eql(cell.bg, a.ui_state.normal_bg) or std.meta.eql(cell.bg, a.ui_state.cursorline_bg) or std.meta.eql(cell.bg, t.bg_editor) or std.meta.activeTag(cell.bg) == .none) {
                            cell.bg = t.bg_editor;
                        }
                        if (std.meta.eql(cell.fg, a.ui_state.default_fg) or std.meta.activeTag(cell.fg) == .none) {
                            cell.fg = t.fg_primary;
                        }
                        if (cell.reverse) {
                            const tmp = cell.fg;
                            cell.fg = cell.bg;
                            cell.bg = tmp;
                        }
                        a.ren.setCell(sx, sy, cell);
                    }
                }
            }
        }
    }

    if (a.mode != .zen) {
        if (plan.sidebar or plan.chrome) {
            workspace.drawSidebar(a, layout);
            if (a.show_file_tree and !a.workspace.overview) {
                if (a.activity_bar.active_idx == 0) {
                    a.explorer.draw(a.ren, layout.file_tree, .{
                        .bg_sidebar = t.bg_sidebar,
                        .bg_editor = t.bg_editor,
                        .bg_accent = t.bg_accent,
                        .fg_primary = t.fg_primary,
                        .fg_secondary = t.fg_secondary,
                        .border_color = t.border_color,
                        .fg_accent = t.fg_accent,
                        .nerd_fonts = a.settings_widget.config.nerd_fonts,
                    });
                } else if (a.activity_bar.active_idx == 1) {
                    a.search_panel.draw(a.ren, layout.file_tree, .{
                        .bg_sidebar = t.bg_sidebar,
                        .bg_editor = t.bg_editor,
                        .bg_accent = t.bg_accent,
                        .fg_primary = t.fg_primary,
                        .fg_secondary = t.fg_secondary,
                        .border_color = t.border_color,
                        .fg_accent = t.fg_accent,
                        .nerd_fonts = a.settings_widget.config.nerd_fonts,
                    });
                } else if (a.activity_bar.active_idx == 2) {
                    a.git_panel.draw(a.ren, layout.file_tree, .{
                        .bg_sidebar = t.bg_sidebar,
                        .bg_editor = t.bg_editor,
                        .bg_accent = t.bg_accent,
                        .fg_primary = t.fg_primary,
                        .fg_secondary = t.fg_secondary,
                        .border_color = t.border_color,
                        .fg_accent = t.fg_accent,
                    });
                } else if (a.activity_bar.active_idx == 3) {
                    a.ai_panel.draw(a.ren, layout.file_tree, .{
                        .bg_sidebar = t.bg_sidebar,
                        .bg_editor = t.bg_editor,
                        .bg_accent = t.bg_accent,
                        .fg_primary = t.fg_primary,
                        .fg_secondary = t.fg_secondary,
                        .border_color = t.border_color,
                        .fg_accent = t.fg_accent,
                        .nerd_fonts = a.settings_widget.config.nerd_fonts,
                    });
                } else if (a.activity_bar.active_idx == 4) {
                    a.extension_shop.draw(a.ren, layout.file_tree, .{
                        .bg_sidebar = t.bg_sidebar,
                        .bg_editor = t.bg_editor,
                        .bg_accent = t.bg_accent,
                        .fg_primary = t.fg_primary,
                        .fg_secondary = t.fg_secondary,
                        .border_color = t.border_color,
                        .fg_accent = t.fg_accent,
                        .nerd_fonts = a.settings_widget.config.nerd_fonts,
                    });
                } else {
                    drawRect(a.ren, layout.file_tree, " ", t.fg_primary, t.bg_sidebar);
                }
                if (layout.file_tree.w > 0) {
                    const sidebar_border = if (a.sidebar_focus) t.bg_accent else t.border_color;
                    var y: u16 = 0;
                    while (y < layout.file_tree.h) : (y += 1) {
                        var cell = Cell{ .fg = sidebar_border, .bg = t.bg_sidebar };
                        cell.setChar("│");
                        a.ren.setCell(layout.file_tree.x + layout.file_tree.w - 1, layout.file_tree.y + y, cell);
                    }
                }
            }
        }

        if (plan.drawer) {
            if (layout.panel) |panel| {
                // Draw terminal panel background
                drawRect(a.ren, panel, " ", t.fg_primary, t.bg_terminal);

                var px: u16 = 0;
                while (px < panel.w) : (px += 1) {
                    var cell = Cell{ .fg = t.border_color, .bg = t.bg_sidebar };
                    cell.setChar("─");
                    a.ren.setCell(panel.x + px, panel.y, cell);
                }

                // Draw terminal header
                const term_header_fg = if (a.active_terminal_panel_idx == 0) t.fg_primary else t.fg_secondary;
                const debug_header_fg = if (a.active_terminal_panel_idx == 1) t.fg_primary else t.fg_secondary;
                const output_header_fg = if (a.active_terminal_panel_idx == 2) t.fg_primary else t.fg_secondary;

                if (panel.w >= 40) {
                    a.ren.drawControlText(panel.x + 2, panel.y, "[Terminal]", term_header_fg, if (a.active_terminal_panel_idx == 0) t.bg_editor else t.bg_sidebar, a.active_terminal_panel_idx == 0, false);
                    a.ren.drawControlText(panel.x + 13, panel.y, "[Debug console]", debug_header_fg, if (a.active_terminal_panel_idx == 1) t.bg_editor else t.bg_sidebar, a.active_terminal_panel_idx == 1, false);
                    a.ren.drawControlText(panel.x + 30, panel.y, "[Output]", output_header_fg, if (a.active_terminal_panel_idx == 2) t.bg_editor else t.bg_sidebar, a.active_terminal_panel_idx == 2, false);
                } else if (panel.w >= 23) {
                    a.ren.drawControlText(panel.x + 1, panel.y, "[Term]", term_header_fg, t.bg_sidebar, a.active_terminal_panel_idx == 0, false);
                    a.ren.drawControlText(panel.x + 8, panel.y, "[Debug]", debug_header_fg, t.bg_sidebar, a.active_terminal_panel_idx == 1, false);
                    a.ren.drawControlText(panel.x + 17, panel.y, "[Out]", output_header_fg, t.bg_sidebar, a.active_terminal_panel_idx == 2, false);
                } else {
                    const compact_title = switch (a.active_terminal_panel_idx) {
                        1 => "[Debug]",
                        2 => "[Output]",
                        else => "[Terminal]",
                    };
                    a.ren.drawTextClipped(panel.x + 1, panel.y, panel.w -| 1, compact_title, t.fg_primary, t.bg_sidebar, true, false);
                }

                if (panel.h > 1) {
                    var py: u16 = 0;
                    while (py < panel.h - 1) : (py += 1) {
                        px = 0;
                        while (px < panel.w) : (px += 1) {
                            if (a.active_terminal_panel_idx == 0 and py < a.ui_term.grid.height and px < a.ui_term.grid.width) {
                                var cell = a.ui_term.grid.cells[@as(usize, py) * @as(usize, a.ui_term.grid.width) + px];
                                if (std.meta.eql(cell.bg, a.ui_term.default_bg) or std.meta.activeTag(cell.bg) == .none) {
                                    cell.bg = t.bg_terminal;
                                }
                                if (std.meta.eql(cell.fg, a.ui_term.default_fg) or std.meta.activeTag(cell.fg) == .none) {
                                    cell.fg = t.fg_primary;
                                } else if (std.meta.activeTag(cell.fg) == .rgb) {
                                    const r = cell.fg.rgb.r;
                                    const g = cell.fg.rgb.g;
                                    const b = cell.fg.rgb.b;
                                    if (r < 80 and g < 80 and b > 50) {
                                        cell.fg.rgb.r = 86;
                                        cell.fg.rgb.g = 182;
                                        cell.fg.rgb.b = 194;
                                    } else if (r < 60 and g < 60 and b < 60) {
                                        cell.fg.rgb.r = r +| 100;
                                        cell.fg.rgb.g = g +| 100;
                                        cell.fg.rgb.b = b +| 100;
                                    }
                                }
                                a.ren.setCell(panel.x + px, panel.y + 1 + py, cell);
                            } else if (a.active_terminal_panel_idx == 1 or a.active_terminal_panel_idx == 2) {
                                // Delay rendering slightly, it will be done below
                            } else {
                                a.ren.setCell(panel.x + px, panel.y + 1 + py, Cell{
                                    .char = [_]u8{ ' ', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
                                    .len = 1,
                                    .fg = t.fg_primary,
                                    .bg = t.bg_terminal,
                                });
                            }
                        }
                    }
                }

                if (a.active_terminal_panel_idx == 1) {
                    const content_rect = Rect{ .x = panel.x, .y = panel.y + 1, .w = panel.w, .h = if (panel.h > 0) @max(1, panel.h - 1) else 1 };
                    a.debug_console.draw(a.ren, content_rect, .{ .fg_primary = t.fg_primary, .fg_secondary = t.fg_secondary, .fg_accent = t.fg_accent, .bg_terminal = t.bg_terminal });
                } else if (a.active_terminal_panel_idx == 2) {
                    const content_rect = Rect{ .x = panel.x, .y = panel.y + 1, .w = panel.w, .h = if (panel.h > 0) @max(1, panel.h - 1) else 1 };
                    a.output_panel.draw(a.ren, content_rect, .{ .fg_primary = t.fg_primary, .fg_secondary = t.fg_secondary, .fg_accent = t.fg_accent, .bg_terminal = t.bg_terminal });
                }
            }
        }
        if (plan.overlays and !a.ui_state.native_picker_chrome) {
            for (a.ui_state.telescope_rects, 0..) |rect_opt, idx| {
                if (rect_opt) |rect| {
                    const draw_x = layout.editor.x + rect.x;
                    const draw_y = layout.editor.y + rect.y;

                    const wx = if (draw_x > 0) draw_x - 1 else 0;
                    const wy = if (draw_y > 0) draw_y - 1 else 0;
                    const shadow_color = Color{ .rgb = .{ .r = 10, .g = 10, .b = 10 } };

                    const other_rect_opt = a.ui_state.telescope_rects[1 - idx];
                    const has_other = (other_rect_opt != null);
                    const ox1 = if (has_other) layout.editor.x + other_rect_opt.?.x - 1 else 0;
                    const oy1 = if (has_other) layout.editor.y + other_rect_opt.?.y - 1 else 0;
                    const ox2 = if (has_other) ox1 + other_rect_opt.?.w + 1 else 0;
                    const oy2 = if (has_other) oy1 + other_rect_opt.?.h + 1 else 0;

                    // Draw shadow right
                    var sy: u16 = 1;
                    while (sy <= rect.h + 1) : (sy += 1) {
                        const shadow_y = wy + sy;
                        const shadow_x1 = wx + rect.w + 2;
                        const shadow_x2 = wx + rect.w + 3;

                        if (!has_other or !(shadow_x1 >= ox1 and shadow_x1 <= ox2 and shadow_y >= oy1 and shadow_y <= oy2)) {
                            a.ren.drawText(shadow_x1, shadow_y, " ", t.fg_primary, shadow_color, false, false);
                        }
                        if (!has_other or !(shadow_x2 >= ox1 and shadow_x2 <= ox2 and shadow_y >= oy1 and shadow_y <= oy2)) {
                            a.ren.drawText(shadow_x2, shadow_y, " ", t.fg_primary, shadow_color, false, false);
                        }
                    }
                    // Draw shadow bottom
                    var sx: u16 = 1;
                    while (sx <= rect.w + 3) : (sx += 1) {
                        const shadow_x = wx + sx;
                        const shadow_y = wy + rect.h + 2;
                        if (!has_other or !(shadow_x >= ox1 and shadow_x <= ox2 and shadow_y >= oy1 and shadow_y <= oy2)) {
                            a.ren.drawText(shadow_x, shadow_y, " ", t.fg_primary, shadow_color, false, false);
                        }
                    }

                    // Top border
                    var bw: u16 = 0;
                    while (bw < rect.w + 2) : (bw += 1) {
                        a.ren.drawText(wx + bw, wy, " ", t.fg_primary, t.border_color, false, false);
                        a.ren.drawText(wx + bw, wy + rect.h + 1, " ", t.fg_primary, t.border_color, false, false);
                    }
                    // Side borders
                    var bh: u16 = 0;
                    while (bh < rect.h + 2) : (bh += 1) {
                        a.ren.drawText(wx, wy + bh, " ", t.fg_primary, t.border_color, false, false);
                        a.ren.drawText(wx + rect.w + 1, wy + bh, " ", t.fg_primary, t.border_color, false, false);
                    }

                    if (idx == 0) {
                        // Top bar text
                        if (a.ui_state.widget_title_len > 0) {
                            a.ren.drawText(wx + 5, wy, a.ui_state.widget_title[0..a.ui_state.widget_title_len], t.fg_primary, t.border_color, true, false);
                        } else {
                            a.ren.drawText(wx + 5, wy, " Telescope ", t.fg_primary, t.border_color, true, false);
                        }
                    } else {
                        // Top bar text
                        a.ren.drawText(wx + 5, wy, " Preview ", t.fg_primary, t.border_color, true, false);
                    }

                    // Red cross (Top Right) on both
                    a.ren.drawText(wx + rect.w - 2, wy, " ✖ ", .{ .rgb = .{ .r = 255, .g = 80, .b = 80 } }, t.border_color, true, false);
                }
            }
        }
    }
    if (plan.chrome) workspace.drawChrome(a, layout);
    if (plan.overlays and a.extension_shop.is_open) {
        a.extension_shop.drawPanel(a.ren, layout.editor, .{
            .bg_editor = t.bg_editor,
            .bg_sidebar = t.bg_sidebar,
            .bg_accent = t.bg_accent,
            .fg_primary = t.fg_primary,
            .fg_secondary = t.fg_secondary,
            .border_color = t.border_color,
            .fg_accent = t.fg_accent,
            .nerd_fonts = a.settings_widget.config.nerd_fonts,
        });
    }

    a.ren.pointer_position = pointer;
    if (plan.overlays and a.workspace.palette) workspace.drawPalette(a, layout);
    if (plan.overlays and a.settings_widget.is_open) {
        a.settings_widget.draw(a.ren, a.ren.width, a.ren.height, .{
            .bg_editor = t.bg_editor,
            .bg_sidebar = t.bg_sidebar,
            .bg_accent = t.bg_accent,
            .fg_primary = t.fg_primary,
            .fg_secondary = t.fg_secondary,
            .border_color = t.border_color,
            .fg_accent = t.fg_accent,
        });
    }
    if (plan.overlays and a.mason_widget.is_open) {
        a.mason_widget.draw(a.ren, a.ren.width, a.ren.height, .{
            .bg_editor = t.bg_editor,
            .bg_sidebar = t.bg_sidebar,
            .bg_accent = t.bg_accent,
            .fg_primary = t.fg_primary,
            .fg_secondary = t.fg_secondary,
            .border_color = t.border_color,
            .fg_accent = t.fg_accent,
            .fg_comment = t.fg_secondary,
        });
    }
    if (plan.overlays and a.lazy_widget.is_open) {
        a.lazy_widget.draw(a.ren, a.ren.width, a.ren.height, .{
            .bg_editor = t.bg_editor,
            .bg_sidebar = t.bg_sidebar,
            .bg_accent = t.bg_accent,
            .fg_primary = t.fg_primary,
            .fg_secondary = t.fg_secondary,
            .border_color = t.border_color,
            .fg_accent = t.fg_accent,
            .fg_comment = t.fg_secondary,
        });
    }
    if (plan.overlays and a.git_detailed_widget.is_open) {
        a.git_detailed_widget.draw(a.ren, a.ren.width, a.ren.height, .{
            .bg_editor = t.bg_editor,
            .bg_sidebar = t.bg_sidebar,
            .bg_accent = t.bg_accent,
            .fg_primary = t.fg_primary,
            .fg_secondary = t.fg_secondary,
            .border_color = t.border_color,
            .fg_accent = t.fg_accent,
            .fg_comment = t.fg_secondary,
        });
    }

    // Draw split dropdown menu if open
    if (plan.overlays and a.show_split_menu) {
        const mx = a.split_menu_x;
        const my = a.split_menu_y;
        const mw: u16 = 24;
        const mh: u16 = 6;

        // Draw background shadow / fill
        var sy: u16 = 0;
        while (sy < mh) : (sy += 1) {
            var sx: u16 = 0;
            while (sx < mw) : (sx += 1) {
                a.ren.setCell(mx + sx, my + sy, Cell{
                    .char = [_]u8{ ' ', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
                    .len = 1,
                    .fg = t.fg_primary,
                    .bg = t.bg_sidebar,
                });
            }
        }

        // Draw borders
        var bx: u16 = 1;
        while (bx < mw - 1) : (bx += 1) {
            var top_c = Cell{ .fg = t.border_color, .bg = t.bg_sidebar };
            top_c.setChar("─");
            a.ren.setCell(mx + bx, my, top_c);
            var bot_c = Cell{ .fg = t.border_color, .bg = t.bg_sidebar };
            bot_c.setChar("─");
            a.ren.setCell(mx + bx, my + mh - 1, bot_c);
        }
        var by: u16 = 1;
        while (by < mh - 1) : (by += 1) {
            var left_c = Cell{ .fg = t.border_color, .bg = t.bg_sidebar };
            left_c.setChar("│");
            a.ren.setCell(mx, my + by, left_c);
            var right_c = Cell{ .fg = t.border_color, .bg = t.bg_sidebar };
            right_c.setChar("│");
            a.ren.setCell(mx + mw - 1, my + by, right_c);
        }

        var tl = Cell{ .fg = t.border_color, .bg = t.bg_sidebar };
        tl.setChar("┌");
        a.ren.setCell(mx, my, tl);
        var tr = Cell{ .fg = t.border_color, .bg = t.bg_sidebar };
        tr.setChar("┐");
        a.ren.setCell(mx + mw - 1, my, tr);
        var bl = Cell{ .fg = t.border_color, .bg = t.bg_sidebar };
        bl.setChar("└");
        a.ren.setCell(mx, my + mh - 1, bl);
        var br = Cell{ .fg = t.border_color, .bg = t.bg_sidebar };
        br.setChar("┘");
        a.ren.setCell(mx + mw - 1, my + mh - 1, br);

        // Draw menu items based on split menu direction
        if (a.split_menu_dir == .right) {
            drawText(a.ren, mx + 2, my + 1, "  Terminal (Right)", t.fg_primary, t.bg_sidebar, false, false);
            drawText(a.ren, mx + 2, my + 2, "  Terminal (Left) ", t.fg_primary, t.bg_sidebar, false, false);
            drawText(a.ren, mx + 2, my + 3, "󰝒  Editor (Right)  ", t.fg_primary, t.bg_sidebar, false, false);
            drawText(a.ren, mx + 2, my + 4, "󰝒  Editor (Left)   ", t.fg_primary, t.bg_sidebar, false, false);
        } else {
            drawText(a.ren, mx + 2, my + 1, "  Terminal (Bottom)", t.fg_primary, t.bg_sidebar, false, false);
            drawText(a.ren, mx + 2, my + 2, "  Terminal (Top)   ", t.fg_primary, t.bg_sidebar, false, false);
            drawText(a.ren, mx + 2, my + 3, "󰝒  Editor (Bottom)  ", t.fg_primary, t.bg_sidebar, false, false);
            drawText(a.ren, mx + 2, my + 4, "󰝒  Editor (Top)     ", t.fg_primary, t.bg_sidebar, false, false);
        }
    }

    if (plan.drawer and layout.panel != null and a.terminal_wins.items.len > 1) {
        for (a.terminal_wins.items) |win| {
            if (win.width > 4 and win.height > 1) {
                const w_gx = win.col + win.width - 2;
                const w_gy = win.row;
                var cell = Cell{
                    .char = [_]u8{ 226, 156, 150, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
                    .len = 3,
                    .fg = if (win.active) Color{ .rgb = .{ .r = 255, .g = 80, .b = 80 } } else t.fg_secondary,
                    .bg = t.bg_terminal,
                };
                if (w_gy < a.ui_term.grid.height and w_gx < a.ui_term.grid.width) {
                    const orig = a.ui_term.grid.cells[@as(usize, w_gy) * @as(usize, a.ui_term.grid.width) + w_gx];
                    if (std.meta.activeTag(orig.bg) != .none) {
                        cell.bg = orig.bg;
                    }
                }
                if (layout.panel.?.x + w_gx < a.ren.width and layout.panel.?.y + 1 + w_gy < a.ren.height) {
                    a.ren.setCell(layout.panel.?.x + w_gx, layout.panel.?.y + 1 + w_gy, cell);
                }
            }
        }
    }

    if (plan.overlays and a.mode != .zen) {
        if (a.show_file_tree and a.activity_bar.active_idx == 0) a.explorer.drawOverlay(a.ren, .{
            .bg_editor = t.bg_editor,
            .fg_primary = t.fg_primary,
            .fg_accent = t.fg_accent,
            .nerd_fonts = a.settings_widget.config.nerd_fonts,
        });

        if (a.activeNotice()) |message| {
            const prefix = switch (a.notice_level) {
                .info => "Info: ",
                .warning => "Warning: ",
                .failure => "Error: ",
            };
            const max_w: u16 = @min(60, a.ren.width -| 2);
            if (max_w >= 12 and a.ren.height > 2) {
                const x = a.ren.width - max_w - 1;
                const bg = switch (a.notice_level) {
                    .info => t.bg_accent,
                    .warning => Color{ .rgb = .{ .r = 145, .g = 105, .b = 20 } },
                    .failure => Color{ .rgb = .{ .r = 140, .g = 45, .b = 50 } },
                };
                const notice_fg = theme.readableForeground(t.fg_primary, bg, 7.0);
                drawRect(a.ren, Rect{ .x = x, .y = 1, .w = max_w, .h = 1 }, " ", notice_fg, bg);
                a.ren.drawTextClipped(x + 1, 1, max_w - 2, prefix, notice_fg, bg, true, false);
                const prefix_w: u16 = @intCast(prefix.len);
                if (max_w > prefix_w + 2)
                    a.ren.drawTextClipped(x + 1 + prefix_w, 1, max_w - prefix_w - 2, message, notice_fg, bg, false, false);
            }
        }
    }

    if (plan.overlays) a.editor_context_menu.draw(a.ren, .{
        .bg_editor = t.bg_editor,
        .bg_sidebar = t.bg_sidebar,
        .bg_accent = t.bg_accent,
        .fg_primary = t.fg_primary,
        .fg_secondary = t.fg_secondary,
        .border_color = t.border_color,
        .fg_accent = t.fg_accent,
    });

    // The report dialog is the top-most native surface.
    if (plan.overlays and a.bug_report.is_open) {
        a.bug_report.draw(a.ren, a.ren.width, a.ren.height, .{
            .bg_editor = t.bg_editor,
            .bg_sidebar = t.bg_sidebar,
            .bg_accent = t.bg_accent,
            .fg_primary = t.fg_primary,
            .fg_secondary = t.fg_secondary,
            .border_color = t.border_color,
            .fg_accent = t.fg_accent,
        });
    }
}
