const std = @import("std");
const App = @import("app.zig").App;
const Layout = @import("layout.zig").Layout;
const Rect = @import("layout.zig").Rect;
const Value = @import("../nvim/msgpack.zig").Value;
const settings = @import("widgets/settings.zig");

pub const Action = enum { find_file, explorer, terminal, git, problems, ai, extensions, settings, keys, help, save, new_file, split_right, split_down, close_file, zen, next_region, sidebar, report, buffers, commands, terminal_right, search_project };
pub const actions = std.enums.values(Action);
pub const labels = [_][]const u8{ "Find file", "Explorer", "Terminal", "Git", "Problems", "AI assistants", "Extensions", "Settings", "Keyboard shortcuts", "Help", "Save file", "New file", "Split right", "Split down", "Close buffer", "Toggle zen", "Next region", "Toggle sidebar", "Report bug", "Switch buffers", "Command menu", "Open terminal right", "Search project" };
pub const State = struct {
    overview: bool = false,
    selected: usize = 0,
    scroll: usize = 0,
    palette: bool = false,
    buffer_picker: bool = false,
    editing_shortcut: ?Action = null,
    shortcut_message: []const u8 = "",
    query: [96]u8 = @splat(0),
    query_len: usize = 0,
    command_selected: usize = 0,
    command_scroll: usize = 0,
};

pub fn command(a: *App, code: []const u8) void {
    const params = [_]Value{ .{ .string = code }, .{ .array = &.{} } };
    a.rpc.notify("nvim_exec_lua", &params) catch |err| a.notify(.failure, "Command failed: {}", .{err});
}

pub fn openPalette(a: *App) void {
    a.workspace.palette = true;
    a.workspace.buffer_picker = false;
    a.workspace.editing_shortcut = null;
    a.workspace.shortcut_message = "";
    a.workspace.query_len = 0;
    a.workspace.command_selected = 0;
    a.workspace.command_scroll = 0;
    a.invalidations.damageAll();
}

pub fn appendQuery(a: *App, text: []const u8) void {
    if (a.workspace.editing_shortcut != null) return;
    a.workspace.shortcut_message = "";
    for (text) |c| {
        if (c >= 32 and c < 127 and a.workspace.query_len < a.workspace.query.len) {
            a.workspace.query[a.workspace.query_len] = c;
            a.workspace.query_len += 1;
        }
    }
    a.workspace.command_selected = 0;
    a.workspace.command_scroll = 0;
    a.invalidations.damageAll();
}

pub fn matches(query: []const u8, label: []const u8) bool {
    if (query.len == 0) return true;
    var i: usize = 0;
    for (label) |c| {
        if (std.ascii.toLower(c) == std.ascii.toLower(query[i])) i += 1;
        if (i == query.len) return true;
    }
    return false;
}

pub fn filtered(state: *const State, out: *[actions.len]Action) []Action {
    var n: usize = 0;
    for (actions, labels) |action, label| if (matches(state.query[0..state.query_len], label)) {
        out[n] = action;
        n += 1;
    };
    return out[0..n];
}

pub fn paletteRect(layout: Layout) Rect {
    const w = @min(64, layout.total.w);
    const h = @min(14, layout.total.h);
    return .{ .x = (layout.total.w - w) / 2, .y = @min(2, layout.total.h - h), .w = w, .h = h };
}

pub fn selectBuffer(a: *App, index: usize) void {
    if (index >= a.tabs.items.len) return;
    var args = [_]Value{.{ .integer = a.tabs.items[index].bufnr }};
    const params = [_]Value{ .{ .string = "return _G.tuim_select_buffer(...)" }, .{ .array = &args } };
    a.rpc.notify("nvim_exec_lua", &params) catch |err| a.notify(.failure, "Unable to select file: {}", .{err});
    a.sidebar_focus = false;
    a.terminal_focus = false;
    a.invalidations.damageAll();
}

pub fn openBuffers(a: *App) void {
    openPalette(a);
    a.workspace.buffer_picker = true;
    a.workspace.command_selected = @min(a.active_tab, a.tabs.items.len -| 1);
}

fn bufferMatches(a: *App, index: usize) bool {
    const tab = a.tabs.items[index];
    return matches(a.workspace.query[0..a.workspace.query_len], tab.path orelse tab.name);
}

pub fn bufferIndex(a: *App, selected: usize) ?usize {
    var n: usize = 0;
    for (0..a.tabs.items.len) |i| {
        if (!bufferMatches(a, i)) continue;
        if (n == selected) return i;
        n += 1;
    }
    return null;
}

pub fn resultCount(a: *App) usize {
    if (!a.workspace.buffer_picker) {
        var results: [actions.len]Action = undefined;
        return filtered(&a.workspace, &results).len;
    }
    var count: usize = 0;
    for (0..a.tabs.items.len) |i| {
        if (bufferMatches(a, i)) count += 1;
    }
    return count;
}

pub fn bindingField(action: Action) settings.Keybindings.Field {
    return switch (action) {
        .find_file => .find_file,
        .search_project => .search_project,
        .explorer => .project_files,
        .terminal => .toggle_terminal,
        .git => .changes,
        .problems => .problems,
        .ai => .ai_assistants,
        .extensions => .extensions,
        .settings => .settings,
        .keys => .keyboard_shortcuts,
        .help => .help,
        .save => .save_file,
        .new_file => .new_file,
        .split_right => .split_right,
        .terminal_right => .terminal_right,
        .split_down => .split_down,
        .close_file => .close_buffer,
        .zen => .toggle_zen,
        .next_region => .focus_next,
        .sidebar => .toggle_explorer,
        .report => .report_bug,
        .buffers => .switch_buffers,
        .commands => .commands,
    };
}

pub fn editShortcut(a: *App, action: Action) void {
    a.workspace.editing_shortcut = action;
    a.workspace.shortcut_message = "";
}

pub fn recordShortcut(a: *App, key: []const u8) void {
    const action = a.workspace.editing_shortcut orelse return;
    if (std.mem.eql(u8, key, "<Esc>")) {
        a.workspace.editing_shortcut = null;
        a.workspace.shortcut_message = "Shortcut unchanged";
        return;
    }
    if (!std.mem.startsWith(u8, key, "<C-") and !std.mem.startsWith(u8, key, "<M-") and !std.mem.startsWith(u8, key, "<F")) {
        a.workspace.shortcut_message = "Use Ctrl, Alt or a function key; Esc cancels";
        return;
    }
    if (std.mem.eql(u8, key, "<F12>") and action != .report) {
        a.workspace.shortcut_message = "Reserved shortcut; choose another key";
        return;
    }
    const widget = a.settings_widget;
    widget.config.saveBinding(widget.allocator, widget.settings_path, bindingField(action), key) catch |err| {
        a.workspace.shortcut_message = if (err == error.DuplicateShortcut) "Shortcut already in use; choose another key" else "Could not save shortcut; retry or Esc to cancel";
        return;
    };
    widget.needs_apply = true;
    a.workspace.editing_shortcut = null;
    a.workspace.shortcut_message = "Shortcut saved";
}

pub fn itemRow(index: usize, files: usize) usize {
    const offset: usize = if (index < files) 1 else if (index < files + 5) 3 else 5;
    return index + offset;
}

pub fn ensureSelection(a: *App, rect: Rect) void {
    a.workspace.selected = @min(a.workspace.selected, a.tabs.items.len + 8 - 1);
    const row = itemRow(a.workspace.selected, a.tabs.items.len);
    if (row < a.workspace.scroll) a.workspace.scroll = row;
    if (rect.h > 0 and row >= a.workspace.scroll + rect.h) a.workspace.scroll = row - rect.h + 1;
}

fn section(a: *App, rect: Rect, row: usize, text: []const u8) void {
    if (rect.w < 4 or row < a.workspace.scroll or row - a.workspace.scroll >= rect.h) return;
    const chrome = a.active_theme.chrome();
    const t = &chrome;
    const y = rect.y + @as(u16, @intCast(row - a.workspace.scroll));
    a.ren.drawRect(.{ .x = rect.x, .y = y, .w = rect.w - 1, .h = 1 }, "─", t.border_color, t.bg_sidebar);
    const label_w: u16 = @intCast(@min(text.len, rect.w -| 5));
    a.ren.drawTextClipped(rect.x + 1, y, 1, "[", t.border_color, t.bg_sidebar, false, false);
    a.ren.drawTextClipped(rect.x + 2, y, label_w, text, t.fg_secondary, t.bg_sidebar, true, false);
    a.ren.drawTextClipped(rect.x + 2 + label_w, y, 1, "]", t.border_color, t.bg_sidebar, false, false);
}

pub fn drawSidebar(a: *App, layout: Layout) void {
    const rect = layout.file_tree;
    if (rect.w == 0) return;
    const chrome = a.active_theme.chrome();
    const t = &chrome;
    a.ren.drawRect(.{ .x = 0, .y = 0, .w = rect.w, .h = @min(2, layout.total.h) }, " ", t.fg_primary, t.bg_sidebar);
    var title: [160]u8 = undefined;
    const project = if (a.git_panel.current_branch) |branch| std.fmt.bufPrint(&title, "tuim / {s}", .{branch}) catch "tuim" else "tuim";
    a.ren.drawTextClipped(1, 0, rect.w -| 2, project, t.fg_accent, t.bg_sidebar, true, false);
    if (layout.total.h > 1) a.ren.drawButtonText(1, 1, rect.w -| 2, if (a.workspace.overview) "WORKSPACE" else "< Workspace [Esc]", t.fg_secondary, t.bg_sidebar, false, false);
    if (!a.workspace.overview) return;
    a.ren.drawRect(rect, " ", t.fg_primary, t.bg_sidebar);
    const files = a.tabs.items.len;
    const total = files + 8;
    if (a.sidebar_focus) ensureSelection(a, rect);
    const max_scroll = (itemRow(total - 1, files) + 1) -| rect.h;
    a.workspace.scroll = @min(a.workspace.scroll, max_scroll);
    section(a, rect, 0, "OPEN FILES");
    section(a, rect, files + 2, "PROJECT");
    section(a, rect, files + 9, "TOOLS");
    for (0..total) |index| {
        const row = itemRow(index, files);
        if (row < a.workspace.scroll or row - a.workspace.scroll >= rect.h or rect.w < 6) continue;
        const y = rect.y + @as(u16, @intCast(row - a.workspace.scroll));
        const label = if (index < files) a.tabs.items[index].name else labels[index - files];
        const focused = (a.sidebar_focus and index == a.workspace.selected) or a.ren.isHovered(.{ .x = rect.x, .y = y, .w = rect.w -| 1, .h = 1 });
        const current_file = index < files and index == a.active_tab;
        const bg = if (focused or current_file) t.bg_tab_inactive else t.bg_sidebar;
        const fg = @import("theme.zig").readableForeground(t.fg_primary, bg, 4.5);
        if (focused or current_file) a.ren.drawRect(.{ .x = rect.x + 1, .y = y, .w = rect.w - 3, .h = 1 }, " ", fg, bg);
        // The rail marks the current file even while focus moves to a tool.
        if (current_file) a.ren.drawTextClipped(rect.x, y, 1, "▎", t.fg_accent, t.bg_sidebar, true, false);
        if (focused or current_file) {
            a.ren.drawTextClipped(rect.x + 1, y, 1, "[", if (focused) t.fg_primary else t.border_color, bg, false, false);
            a.ren.drawTextClipped(rect.x + rect.w - 2, y, 1, "]", if (focused) t.fg_primary else t.border_color, bg, false, false);
        }
        a.ren.drawTextClipped(rect.x + 3, y, rect.w - 6, label, fg, bg, focused or current_file, false);
        if (index < files and a.tabs.items[index].modified) {
            a.ren.drawTextClipped(rect.x + rect.w - 3, y, 1, "*", fg, t.bg_sidebar, true, false);
        } else if (index >= files) {
            a.ren.drawTextClipped(rect.x + rect.w - 3, y, 1, ">", t.fg_secondary, t.bg_sidebar, false, false);
        }
    }
    var y: u16 = 0;
    while (y < rect.h) : (y += 1) a.ren.drawTextClipped(rect.x + rect.w - 1, rect.y + y, 1, "│", if (a.sidebar_focus) t.fg_accent else t.border_color, t.bg_sidebar, false, false);
}

pub fn shortcut(a: *App, action: Action) []const u8 {
    return a.settings_widget.config.keybindings.get(bindingField(action));
}

pub fn drawChrome(a: *App, layout: Layout) void {
    const chrome = a.active_theme.chrome();
    const t = &chrome;
    const file = if (a.active_tab < a.tabs.items.len) a.tabs.items[a.active_tab].name else "[No file]";
    var hint_buf: [80]u8 = undefined;
    const hint = std.fmt.bufPrint(&hint_buf, "{s} Commands", .{a.settings_widget.config.keybindings.commands}) catch "Commands";
    if (a.mode != .zen and layout.tab_bar.h > 0) {
        const r = layout.tab_bar;
        a.ren.drawRect(r, " ", t.fg_primary, t.bg_editor);
        a.ren.drawTextClipped(r.x + @min(1, r.w), r.y, r.w -| 19, file, t.fg_primary, t.bg_editor, false, false);
        if (r.w >= 18) a.ren.drawButtonText(r.x + r.w - 18, r.y, 18, hint, t.fg_secondary, t.bg_editor, false, false);
    }
    const r = layout.status_bar;
    if (r.h == 0) return;
    a.ren.drawRect(r, " ", t.fg_primary, t.bg_editor);
    if (a.ui_state.native_picker_chrome) {
        if (r.w >= 24) a.ren.drawButtonText(1, r.y, 10, "Enter Open", t.fg_primary, t.bg_editor, true, false);
        if (r.w >= 72) {
            a.ren.drawTextClipped(14, r.y, 12, "Up/Down Move", t.fg_secondary, t.bg_editor, false, false);
            a.ren.drawButtonText(28, r.y, 8, "Tab Mark", t.fg_secondary, t.bg_editor, false, false);
            a.ren.drawButtonText(39, r.y, 13, "Alt+P Preview", t.fg_secondary, t.bg_editor, false, false);
        } else if (r.w >= 48) a.ren.drawButtonText(17, r.y, 13, "Alt+P Preview", t.fg_secondary, t.bg_editor, false, false);
        if (r.w >= 11) a.ren.drawButtonText(r.w - 11, r.y, 10, "Esc Close", t.fg_primary, t.bg_editor, false, false);
        return;
    }
    const editing_mode: []const u8 = switch (a.ui_state.editor_mode) {
        'i' => "INSERT",
        'v' => "VISUAL",
        'r', 'R' => "REPLACE",
        'c' => "COMMAND",
        't' => "TERMINAL",
        else => "NORMAL",
    };
    a.ren.drawTextClipped(1, r.y, r.w -| 1, if (a.mode == .zen) "ZEN" else if (a.mode == .ide) "IDE" else editing_mode, t.fg_accent, t.bg_editor, true, false);
    const focus = if (a.terminal_focus) "Terminal" else if (a.sidebar_focus) "Workspace" else "Editor";
    if (r.w >= 48) a.ren.drawTextClipped(9, r.y, r.w -| 50, if (a.mode == .zen) file else focus, t.fg_secondary, t.bg_editor, false, false);
    if (r.w >= 50) a.ren.drawButtonText(r.w - 36, r.y, 18, hint, t.fg_secondary, t.bg_editor, false, false);
    var footer_buf: [80]u8 = undefined;
    const footer = std.fmt.bufPrint(&footer_buf, "{s} {s}", .{ a.settings_widget.config.keybindings.toggle_zen, if (a.mode == .zen) @as([]const u8, "Return") else "Zen" }) catch "Zen";
    if (r.w >= 16) a.ren.drawButtonText(r.w - 16, r.y, 16, footer, t.fg_secondary, t.bg_editor, false, false);
}

pub const PickerAction = enum { open, mark, preview, close };

pub fn pickerFooterAction(width: u16, column: u16) ?PickerAction {
    if (column >= width) return null;
    if (width >= 24 and column >= 1 and column < 11) return .open;
    if (width >= 72 and column >= 28 and column < 36) return .mark;
    if (width >= 72 and column >= 39 and column < 52) return .preview;
    if (width >= 48 and width < 72 and column >= 17 and column < 30) return .preview;
    if (width >= 11 and column >= width - 11) return .close;
    return null;
}

test "picker footer hit targets follow wide and compact labels" {
    try std.testing.expectEqual(PickerAction.open, pickerFooterAction(100, 4).?);
    try std.testing.expectEqual(PickerAction.mark, pickerFooterAction(100, 30).?);
    try std.testing.expectEqual(PickerAction.preview, pickerFooterAction(100, 42).?);
    try std.testing.expectEqual(PickerAction.preview, pickerFooterAction(50, 20).?);
    try std.testing.expectEqual(PickerAction.close, pickerFooterAction(30, 25).?);
    try std.testing.expect(pickerFooterAction(30, 12) == null);
    try std.testing.expect(pickerFooterAction(0, 0) == null);
}

fn paletteLine(a: *App, r: Rect, index: usize, label: []const u8, detail: []const u8) void {
    if (index < a.workspace.command_scroll or index >= a.workspace.command_scroll + r.h - 3) return;
    const chrome = a.active_theme.chrome();
    const t = &chrome;
    const y = r.y + 2 + @as(u16, @intCast(index - a.workspace.command_scroll));
    const selected = index == a.workspace.command_selected or a.ren.isHovered(.{ .x = r.x + 1, .y = y, .w = r.w -| 2, .h = 1 });
    const bg = if (selected) t.bg_tab_inactive else t.bg_sidebar;
    const fg = @import("theme.zig").readableForeground(t.fg_primary, bg, 4.5);
    a.ren.drawRect(.{ .x = r.x + 1, .y = y, .w = r.w - 2, .h = 1 }, " ", fg, bg);
    a.ren.drawTextClipped(r.x + 2, y, if (r.w >= 44) r.w - 18 else r.w - 4, label, fg, bg, selected, false);
    if (selected) a.ren.drawTextClipped(r.x + 1, y, 1, "▎", t.fg_primary, bg, false, false);
    if (r.w >= 44) a.ren.drawTextClipped(r.x + r.w - 15, y, 14, detail, if (selected) fg else t.fg_secondary, bg, false, false);
}

pub fn drawPalette(a: *App, layout: Layout) void {
    const r = paletteRect(layout);
    if (r.w < 4 or r.h < 4) return;
    const chrome = a.active_theme.chrome();
    const t = &chrome;
    a.ren.drawRect(r, " ", t.fg_primary, t.bg_sidebar);
    a.ren.drawRect(.{ .x = r.x, .y = r.y, .w = r.w, .h = 1 }, "─", t.border_color, t.bg_sidebar);
    a.ren.drawRect(.{ .x = r.x, .y = r.y + r.h - 1, .w = r.w, .h = 1 }, "─", t.border_color, t.bg_sidebar);
    for (0..r.h) |row| {
        const y = r.y + @as(u16, @intCast(row));
        a.ren.drawTextClipped(r.x, y, 1, if (row == 0) "┌" else if (row == r.h - 1) "└" else "│", t.border_color, t.bg_sidebar, false, false);
        a.ren.drawTextClipped(r.x + r.w - 1, y, 1, if (row == 0) "┐" else if (row == r.h - 1) "┘" else "│", t.border_color, t.bg_sidebar, false, false);
    }
    const title = if (a.workspace.editing_shortcut != null) "Set shortcut / press a key" else if (a.workspace.buffer_picker) "Open buffers / type to filter" else "Commands / type to filter";
    a.ren.drawTextClipped(r.x + 1, r.y, r.w - 2, title, t.fg_accent, t.bg_sidebar, true, false);
    const prompt = if (a.workspace.editing_shortcut) |action| labels[@intFromEnum(action)] else a.workspace.query[0..a.workspace.query_len];
    a.ren.drawTextClipped(r.x + 1, r.y + 1, r.w - 2, prompt, t.fg_primary, t.bg_sidebar, false, false);
    const total = resultCount(a);
    const count = r.h - 3;
    a.workspace.command_selected = @min(a.workspace.command_selected, total -| 1);
    if (a.workspace.command_selected < a.workspace.command_scroll) a.workspace.command_scroll = a.workspace.command_selected;
    if (a.workspace.command_selected >= a.workspace.command_scroll + count) a.workspace.command_scroll = a.workspace.command_selected - count + 1;
    if (a.workspace.buffer_picker) {
        var index: usize = 0;
        for (a.tabs.items, 0..) |tab, i| {
            if (!bufferMatches(a, i)) continue;
            var label_buf: [1024]u8 = undefined;
            var detail_buf: [48]u8 = undefined;
            const label = if (tab.path) |path| std.fmt.bufPrint(&label_buf, "{s}  {s}", .{ tab.name, std.fs.path.dirname(path) orelse "" }) catch tab.name else tab.name;
            const detail = std.fmt.bufPrint(&detail_buf, "#{d}{s}{s}", .{ tab.bufnr, if (i == a.active_tab) @as([]const u8, " current") else "", if (tab.modified) @as([]const u8, " *") else "" }) catch "";
            paletteLine(a, r, index, label, detail);
            index += 1;
        }
    } else {
        var results: [actions.len]Action = undefined;
        for (filtered(&a.workspace, &results), 0..) |action, i| {
            const key = shortcut(a, action);
            paletteLine(a, r, i, labels[@intFromEnum(action)], if (key.len == 0) "[Set shortcut]" else key);
        }
    }
    if (total == 0) a.ren.drawTextClipped(r.x + 1, r.y + 2, r.w - 2, if (a.workspace.buffer_picker) "No matching buffers" else "No matching commands", t.fg_secondary, t.bg_sidebar, false, false);
    const footer = if (a.workspace.shortcut_message.len > 0) a.workspace.shortcut_message else if (a.workspace.editing_shortcut != null) "Press shortcut to save / Esc cancels" else if (a.workspace.buffer_picker) "Up/Down select  Enter open  Esc back" else if (r.w < 44) "F2 key  Enter run  Esc back" else "Up/Down select  Enter run  F2 shortcut  Esc back";
    a.ren.drawTextClipped(r.x + 1, r.y + r.h - 1, r.w - 2, footer, t.fg_secondary, t.bg_sidebar, false, false);
}

test "command matching is case insensitive and supports abbreviated searches" {
    try std.testing.expect(matches("kbsh", "Keyboard shortcuts"));
    try std.testing.expect(matches("ZEN", "Toggle zen"));
    try std.testing.expect(!matches("terminal", "Settings"));
    var state = State{};
    var results: [actions.len]Action = undefined;
    try std.testing.expectEqual(actions.len, filtered(&state, &results).len);
    @memcpy(state.query[0..3], "zen");
    state.query_len = 3;
    try std.testing.expectEqualSlices(Action, &.{.zen}, filtered(&state, &results));
}
