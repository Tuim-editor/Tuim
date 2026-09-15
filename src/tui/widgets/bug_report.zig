const std = @import("std");
const builtin = @import("builtin");
const input = @import("../input.zig");
const renderer = @import("../renderer.zig");
const primitives = @import("primitives.zig");
const Rect = @import("../layout.zig").Rect;

const WrappedLineIterator = struct {
    text: []const u8,
    max_width: u16,
    index: usize = 0,
    finished: bool = false,

    fn init(text: []const u8, max_width: u16) WrappedLineIterator {
        return .{ .text = text, .max_width = @max(1, max_width) };
    }

    fn next(self: *WrappedLineIterator) ?[]const u8 {
        if (self.finished) return null;
        if (self.index == self.text.len) {
            self.finished = true;
            return if (self.text.len > 0 and self.text[self.text.len - 1] == '\n')
                self.text[self.text.len..]
            else
                null;
        }

        const start = self.index;
        var end = start;
        var width: u16 = 0;
        while (end < self.text.len) {
            if (self.text[end] == '\n') {
                self.index = end + 1;
                return self.text[start..end];
            }

            const sequence_len = std.unicode.utf8ByteSequenceLength(self.text[end]) catch 1;
            const char_end = @min(self.text.len, end + sequence_len);
            const codepoint = std.unicode.utf8Decode(self.text[end..char_end]) catch @as(u21, self.text[end]);
            const cell_width: u16 = renderer.unicodeCellWidth(codepoint);
            if (cell_width > 0 and width +| cell_width > self.max_width and end > start) {
                self.index = end;
                return self.text[start..end];
            }
            width +|= cell_width;
            end = char_end;
        }

        self.index = end;
        self.finished = true;
        return self.text[start..end];
    }
};

fn wrappedLineCount(text: []const u8, max_width: u16) usize {
    if (text.len == 0) return 0;
    var iterator = WrappedLineIterator.init(text, max_width);
    var count: usize = 0;
    while (iterator.next() != null) count += 1;
    return count;
}

fn wrappedLineSkip(text: []const u8, max_width: u16, visible_rows: u16) usize {
    return wrappedLineCount(text, max_width) -| @as(usize, visible_rows);
}

pub const Category = enum {
    editor,
    terminal,
    git,
    extensions,
    performance,
    other,

    pub fn label(self: Category) []const u8 {
        return switch (self) {
            .editor => "Editor",
            .terminal => "Terminal",
            .git => "Source control",
            .extensions => "Extensions",
            .performance => "Performance",
            .other => "Other",
        };
    }
};

const category_items = [_]Category{ .editor, .terminal, .git, .extensions, .performance, .other };

pub const Stage = enum { form, consent, submitting, success, failure };

pub const BugReportWidget = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    data_dir: []const u8,
    home_dir: []const u8,
    endpoint: []const u8,
    version: []const u8,
    os_version: []const u8,
    kernel: []const u8,
    architecture: []const u8,
    display_server: []const u8,
    desktop: []const u8,
    terminal: []const u8,
    terminal_version: []const u8,
    term: []const u8,
    shell: []const u8,
    is_open: bool = false,
    stage: Stage = .form,
    focus: u8 = 0, // category, summary, description, send
    category: Category = .editor,
    category_menu_open: bool = false,
    category_menu_idx: usize = 0,
    category_menu_scroll: usize = 0,
    summary: std.array_list.Managed(u8),
    description: std.array_list.Managed(u8),
    consent_yes: bool = false,
    issue_url: ?[]u8 = null,
    error_message: ?[]u8 = null,

    const max_summary = 120;
    const max_description = 6000;
    const max_log_bytes = 32 * 1024;

    fn detectDisplayServer(environ: *const std.process.Environ.Map) []const u8 {
        if (environ.get("XDG_SESSION_TYPE")) |session| if (session.len > 0) return session;
        if (environ.get("WAYLAND_DISPLAY")) |display| if (display.len > 0) return "wayland";
        if (environ.get("DISPLAY")) |display| if (display.len > 0) return "x11";
        return switch (builtin.os.tag) {
            .macos => "native macOS",
            else => "tty/headless",
        };
    }

    fn detectTerminal(environ: *const std.process.Environ.Map) []const u8 {
        if (environ.get("TERM_PROGRAM")) |program| if (program.len > 0) return program;
        if (environ.get("KITTY_WINDOW_ID") != null) return "kitty";
        if (environ.get("WEZTERM_PANE") != null) return "WezTerm";
        if (environ.get("GHOSTTY_RESOURCES_DIR") != null) return "Ghostty";
        if (environ.get("ALACRITTY_SOCKET") != null or environ.get("ALACRITTY_LOG") != null) return "Alacritty";
        if (environ.get("KONSOLE_VERSION") != null) return "Konsole";
        if (environ.get("WT_SESSION") != null) return "Windows Terminal";
        if (environ.get("VTE_VERSION") != null) return "VTE terminal";
        return environ.get("TERM") orelse "unknown";
    }

    fn readOsVersion(allocator: std.mem.Allocator) ![]u8 {
        if (builtin.os.tag == .linux) {
            const fd = std.posix.openatZ(std.posix.AT.FDCWD, "/etc/os-release", .{ .ACCMODE = .RDONLY }, 0) catch -1;
            if (fd >= 0) {
                defer _ = std.posix.system.close(fd);
                var buf: [16 * 1024]u8 = undefined;
                const n = std.posix.read(fd, &buf) catch 0;
                var lines = std.mem.splitScalar(u8, buf[0..n], '\n');
                while (lines.next()) |line| {
                    if (std.mem.startsWith(u8, line, "PRETTY_NAME=")) {
                        const value = std.mem.trim(u8, line["PRETTY_NAME=".len..], " \t\"'");
                        if (value.len > 0) return allocator.dupe(u8, value);
                    }
                }
            }
        }
        const uts = std.posix.uname();
        return allocator.dupe(u8, std.mem.sliceTo(&uts.release, 0));
    }

    pub fn init(allocator: std.mem.Allocator, io: std.Io, data_dir: []const u8, home_dir: []const u8, endpoint: []const u8, version: []const u8, environ: *const std.process.Environ.Map) !BugReportWidget {
        const uts = std.posix.uname();
        return .{
            .allocator = allocator,
            .io = io,
            .data_dir = try allocator.dupe(u8, data_dir),
            .home_dir = try allocator.dupe(u8, home_dir),
            .endpoint = try allocator.dupe(u8, endpoint),
            .version = version,
            .os_version = try readOsVersion(allocator),
            .kernel = try allocator.dupe(u8, std.mem.sliceTo(&uts.release, 0)),
            .architecture = try allocator.dupe(u8, @tagName(builtin.cpu.arch)),
            .display_server = try allocator.dupe(u8, detectDisplayServer(environ)),
            .desktop = try allocator.dupe(u8, environ.get("XDG_CURRENT_DESKTOP") orelse "unknown"),
            .terminal = try allocator.dupe(u8, detectTerminal(environ)),
            .terminal_version = try allocator.dupe(u8, environ.get("TERM_PROGRAM_VERSION") orelse "unknown"),
            .term = try allocator.dupe(u8, environ.get("TERM") orelse "unknown"),
            .shell = try allocator.dupe(u8, std.fs.path.basename(environ.get("SHELL") orelse "unknown")),
            .summary = std.array_list.Managed(u8).init(allocator),
            .description = std.array_list.Managed(u8).init(allocator),
        };
    }

    pub fn deinit(self: *BugReportWidget) void {
        self.summary.deinit();
        self.description.deinit();
        self.allocator.free(self.data_dir);
        self.allocator.free(self.home_dir);
        self.allocator.free(self.endpoint);
        self.allocator.free(self.os_version);
        self.allocator.free(self.kernel);
        self.allocator.free(self.architecture);
        self.allocator.free(self.display_server);
        self.allocator.free(self.desktop);
        self.allocator.free(self.terminal);
        self.allocator.free(self.terminal_version);
        self.allocator.free(self.term);
        self.allocator.free(self.shell);
        if (self.issue_url) |v| self.allocator.free(v);
        if (self.error_message) |v| self.allocator.free(v);
    }

    pub fn open(self: *BugReportWidget) void {
        self.is_open = true;
        self.stage = .form;
        self.focus = 0;
        self.closeCategoryMenu(false);
    }

    fn reset(self: *BugReportWidget) void {
        self.summary.clearRetainingCapacity();
        self.description.clearRetainingCapacity();
        self.category = .editor;
        self.focus = 0;
        self.stage = .form;
        self.consent_yes = false;
        self.closeCategoryMenu(false);
        if (self.issue_url) |v| self.allocator.free(v);
        self.issue_url = null;
        if (self.error_message) |v| self.allocator.free(v);
        self.error_message = null;
    }

    fn modal(screen_w: u16, screen_h: u16) primitives.Modal {
        return primitives.Modal.centered(screen_w, screen_h, 76, 23, 2);
    }

    fn palette(theme: anytype) primitives.Palette {
        return .{ .fg = theme.fg_secondary, .bg = theme.bg_sidebar, .accent_fg = theme.fg_primary, .accent_bg = theme.bg_accent, .muted_fg = theme.fg_secondary };
    }

    fn categoryCount() usize {
        return category_items.len;
    }

    fn categoryIndex(cat: Category) usize {
        return @intFromEnum(cat);
    }

    fn categoryVisibleCount() usize {
        return @min(categoryCount(), 4);
    }

    fn syncCategoryMenuScroll(self: *BugReportWidget) void {
        self.category_menu_scroll = primitives.revealSelection(self.category_menu_scroll, self.category_menu_idx, categoryVisibleCount(), categoryCount());
    }

    fn openCategoryMenu(self: *BugReportWidget) void {
        self.category_menu_open = true;
        self.category_menu_idx = categoryIndex(self.category);
        self.category_menu_scroll = 0;
        self.syncCategoryMenuScroll();
    }

    fn closeCategoryMenu(self: *BugReportWidget, commit: bool) void {
        if (commit and self.category_menu_idx < categoryCount()) {
            self.category = category_items[self.category_menu_idx];
        }
        self.category_menu_open = false;
        self.category_menu_scroll = 0;
    }

    fn drawCategoryMenu(self: *const BugReportWidget, ren: *renderer.Renderer, x: u16, y: u16, w: u16, theme: anytype) void {
        const visible = categoryVisibleCount();
        if (!self.category_menu_open or visible == 0 or w < 6) return;

        const menu_h: u16 = @as(u16, @intCast(visible + 2));
        const menu_rect = Rect{ .x = x, .y = y, .w = w, .h = menu_h };
        primitives.drawModalFrame(ren, .{ .rect = menu_rect }, .rounded, theme.fg_primary, theme.bg_sidebar, theme.border_color, theme.bg_editor);

        const inner_x = menu_rect.x + 1;
        const inner_y = menu_rect.y + 1;
        const inner_w = menu_rect.w -| 2;
        const inner_h = menu_rect.h -| 2;
        var row: usize = 0;
        while (row < visible) : (row += 1) {
            const idx = self.category_menu_scroll + row;
            if (idx >= categoryCount()) break;
            const item_y = inner_y + @as(u16, @intCast(row));
            defer ren.highlightHover(.{ .x = inner_x, .y = item_y, .w = inner_w, .h = 1 }, theme.bg_sidebar, theme.fg_primary);
            const selected = idx == self.category_menu_idx;
            const row_bg = if (selected) theme.bg_accent else theme.bg_sidebar;
            const row_fg = if (selected) theme.fg_primary else theme.fg_secondary;
            ren.drawRect(.{ .x = inner_x, .y = item_y, .w = inner_w, .h = 1 }, " ", row_fg, row_bg);
            if (selected) ren.drawText(inner_x, item_y, "▌", theme.fg_accent, row_bg, true, false);
            ren.drawTextClipped(inner_x + 2, item_y, inner_w -| 3, category_items[idx].label(), row_fg, row_bg, selected, false);
        }

        if (categoryCount() > visible and inner_h > 0 and inner_w > 1) {
            const track_x = menu_rect.x + menu_rect.w - 2;
            const track_y = inner_y;
            const track_h = inner_h;
            var i: u16 = 0;
            while (i < track_h) : (i += 1) {
                ren.drawText(track_x, track_y + i, "│", theme.border_color, theme.bg_sidebar, false, false);
            }
            const max_scroll = categoryCount() - visible;
            const thumb_h_raw: usize = (@as(usize, track_h) * visible) / categoryCount();
            const thumb_h: u16 = @max(@as(u16, 1), @as(u16, @intCast(thumb_h_raw)));
            const thumb_range = track_h -| thumb_h;
            const thumb_y = track_y + @as(u16, @intCast((self.category_menu_scroll * @as(usize, thumb_range)) / max_scroll));
            var t: u16 = 0;
            while (t < thumb_h and thumb_y + t < track_y + track_h) : (t += 1) {
                ren.drawText(track_x, thumb_y + t, "█", theme.fg_accent, theme.bg_sidebar, false, false);
            }
        }
    }

    pub fn draw(self: *const BugReportWidget, ren: *renderer.Renderer, screen_w: u16, screen_h: u16, theme: anytype) void {
        const m = modal(screen_w, screen_h);
        if (!primitives.usable(m, 42, 16)) {
            primitives.drawSizeWarning(ren, "Report a bug", theme.fg_primary, theme.bg_sidebar);
            return;
        }
        primitives.drawModalFrame(ren, m, .rounded, theme.fg_primary, theme.bg_sidebar, theme.border_color, theme.bg_editor);
        const r = m.rect;
        ren.drawText(r.x + 2, r.y, " Report a bug ", theme.fg_accent, theme.bg_sidebar, true, false);
        ren.drawControlText(r.x + r.w - 4, r.y, " x ", .{ .rgb = .{ .r = 255, .g = 85, .b = 85 } }, theme.bg_sidebar, false, false);

        switch (self.stage) {
            .form => self.drawForm(ren, r, theme),
            .consent => self.drawConsent(ren, r, theme),
            .submitting => {
                ren.drawText(r.x + 3, r.y + 5, "Creating your GitHub issue...", theme.fg_primary, theme.bg_sidebar, true, false);
                ren.drawText(r.x + 3, r.y + 7, "This normally takes only a few seconds.", theme.fg_secondary, theme.bg_sidebar, false, false);
            },
            .success => {
                ren.drawText(r.x + 3, r.y + 4, "Bug report sent", theme.fg_accent, theme.bg_sidebar, true, false);
                ren.drawText(r.x + 3, r.y + 6, "Thank you — a GitHub issue was created.", theme.fg_primary, theme.bg_sidebar, false, false);
                if (self.issue_url) |url| ren.drawTextClipped(r.x + 3, r.y + 8, r.w - 6, url, theme.fg_secondary, theme.bg_sidebar, false, false);
                (primitives.Button{ .rect = .{ .x = r.x + r.w - 14, .y = r.y + r.h - 3, .w = 10, .h = 1 }, .state = .focused }).draw(ren, "Close", palette(theme));
            },
            .failure => {
                ren.drawText(r.x + 3, r.y + 4, "Report could not be sent", .{ .rgb = .{ .r = 255, .g = 100, .b = 100 } }, theme.bg_sidebar, true, false);
                if (self.error_message) |msg| ren.drawTextClipped(r.x + 3, r.y + 6, r.w - 6, msg, theme.fg_primary, theme.bg_sidebar, false, false);
                ren.drawText(r.x + 3, r.y + 8, "Your text is still here. Press Enter to try again.", theme.fg_secondary, theme.bg_sidebar, false, false);
                (primitives.Button{ .rect = .{ .x = r.x + 3, .y = r.y + r.h - 3, .w = 12, .h = 1 }, .state = .focused }).draw(ren, "Try again", palette(theme));
            },
        }

        if (self.stage == .form and self.category_menu_open) {
            const x = r.x + 3;
            const w = r.w - 6;
            self.drawCategoryMenu(ren, x, r.y + 4, w, theme);
        }
    }

    fn drawForm(self: *const BugReportWidget, ren: *renderer.Renderer, r: Rect, theme: anytype) void {
        const x = r.x + 3;
        const w = r.w - 6;
        defer {
            if (!self.category_menu_open) {
                ren.highlightHover(.{ .x = x, .y = r.y + 3, .w = w, .h = 1 }, theme.bg_sidebar, theme.fg_primary);
                ren.highlightHover(.{ .x = x, .y = r.y + 6, .w = w, .h = 1 }, theme.bg_sidebar, theme.fg_primary);
                ren.highlightHover(.{ .x = x, .y = r.y + 9, .w = w, .h = 7 }, theme.bg_sidebar, theme.fg_primary);
            }
        }
        ren.drawText(x, r.y + 2, "Category", theme.fg_secondary, theme.bg_sidebar, false, false);
        const category_bg = if (self.focus == 0) theme.bg_accent else theme.bg_editor;
        ren.drawRect(.{ .x = x, .y = r.y + 3, .w = w, .h = 1 }, " ", theme.fg_primary, category_bg);
        const category_label = if (self.category_menu_open) category_items[self.category_menu_idx].label() else self.category.label();
        ren.drawTextClipped(x + 1, r.y + 3, w - 4, category_label, theme.fg_primary, category_bg, self.focus == 0, false);
        ren.drawTextClipped(x + w - 3, r.y + 3, 2, if (self.category_menu_open) "▴" else "▾", theme.fg_secondary, category_bg, false, false);

        ren.drawText(x, r.y + 5, "Short summary", theme.fg_secondary, theme.bg_sidebar, false, false);
        const summary_bg = if (self.focus == 1) theme.bg_accent else theme.bg_editor;
        ren.drawRect(.{ .x = x, .y = r.y + 6, .w = w, .h = 1 }, " ", theme.fg_primary, summary_bg);
        const summary_text = if (self.summary.items.len == 0) "What went wrong?" else self.summary.items;
        ren.drawTextClipped(x + 1, r.y + 6, w - 2, summary_text, if (self.summary.items.len == 0) theme.fg_secondary else theme.fg_primary, summary_bg, false, false);

        ren.drawText(x, r.y + 8, "Description", theme.fg_secondary, theme.bg_sidebar, false, false);
        const desc_bg = if (self.focus == 2) theme.bg_accent else theme.bg_editor;
        ren.drawRect(.{ .x = x, .y = r.y + 9, .w = w, .h = 7 }, " ", theme.fg_primary, desc_bg);
        if (self.description.items.len == 0) {
            ren.drawTextClipped(x + 1, r.y + 10, w - 2, "Steps to reproduce, expected result, and what happened...", theme.fg_secondary, desc_bg, false, false);
        } else {
            const line_width = w -| 2;
            const visible_rows: u16 = 5;
            var lines = WrappedLineIterator.init(self.description.items, line_width);
            var skip = wrappedLineSkip(self.description.items, line_width, visible_rows);
            while (skip > 0) : (skip -= 1) _ = lines.next();
            var row: u16 = 0;
            while (row < visible_rows) : (row += 1) {
                const line = lines.next() orelse break;
                ren.drawTextClipped(x + 1, r.y + 10 + row, w - 2, line, theme.fg_primary, desc_bg, false, false);
            }
        }
        ren.drawText(x, r.y + r.h - 4, "Tab moves between fields • Esc closes", theme.fg_secondary, theme.bg_sidebar, false, false);
        (primitives.Button{ .rect = .{ .x = r.x + r.w - 14, .y = r.y + r.h - 3, .w = 10, .h = 1 }, .state = if (self.focus == 3) .focused else .normal }).draw(ren, "Send", palette(theme));
    }

    fn drawConsent(self: *const BugReportWidget, ren: *renderer.Renderer, r: Rect, theme: anytype) void {
        ren.drawText(r.x + 3, r.y + 4, "Include debug logs?", theme.fg_primary, theme.bg_sidebar, true, false);
        ren.drawText(r.x + 3, r.y + 6, "TUIM can attach up to the last 32 KB of tuim.log.", theme.fg_secondary, theme.bg_sidebar, false, false);
        ren.drawText(r.x + 3, r.y + 7, "Likely tokens, passwords, and your home path are redacted.", theme.fg_secondary, theme.bg_sidebar, false, false);
        ren.drawText(r.x + 3, r.y + 9, "The report is sent only after you choose below.", theme.fg_secondary, theme.bg_sidebar, false, false);
        ren.drawText(r.x + 3, r.y + 10, "TUIM and basic system environment are included either way.", theme.fg_secondary, theme.bg_sidebar, false, false);
        const p = palette(theme);
        (primitives.Button{ .rect = .{ .x = r.x + 3, .y = r.y + r.h - 4, .w = 20, .h = 1 }, .state = if (self.consent_yes) .focused else .normal }).draw(ren, "Include logs", p);
        (primitives.Button{ .rect = .{ .x = r.x + 26, .y = r.y + r.h - 4, .w = 22, .h = 1 }, .state = if (!self.consent_yes) .focused else .normal }).draw(ren, "Send without logs", p);
    }

    fn cycleCategory(self: *BugReportWidget, backwards: bool) void {
        const count = categoryCount();
        const current: usize = if (self.category_menu_open) self.category_menu_idx else categoryIndex(self.category);
        const next = if (backwards) (current + count - 1) % count else (current + 1) % count;
        if (self.category_menu_open) {
            self.category_menu_idx = next;
            self.syncCategoryMenuScroll();
        } else {
            self.category = category_items[next];
        }
    }

    pub fn handleKey(self: *BugReportWidget, key: []const u8) bool {
        if (!self.is_open) return false;
        if (std.mem.eql(u8, key, "<Esc>")) {
            if (self.stage == .consent or self.stage == .failure) self.stage = .form else if (self.stage != .submitting) self.is_open = false;
            return true;
        }
        switch (self.stage) {
            .form => {
                if (self.category_menu_open) {
                    if (std.mem.eql(u8, key, "<Up>") or std.mem.eql(u8, key, "<Left>")) {
                        self.cycleCategory(true);
                        return true;
                    }
                    if (std.mem.eql(u8, key, "<Down>") or std.mem.eql(u8, key, "<Right>")) {
                        self.cycleCategory(false);
                        return true;
                    }
                    if (std.mem.eql(u8, key, "<Enter>")) {
                        self.closeCategoryMenu(true);
                        return true;
                    }
                }
                if (std.mem.eql(u8, key, "<Tab>")) {
                    self.focus = (self.focus + 1) % 4;
                    self.closeCategoryMenu(false);
                    return true;
                }
                if (std.mem.eql(u8, key, "<S-Tab>")) {
                    self.focus = (self.focus + 3) % 4;
                    self.closeCategoryMenu(false);
                    return true;
                }
                if (self.focus == 0 and !self.category_menu_open and (std.mem.eql(u8, key, "<Left>") or std.mem.eql(u8, key, "<Up>"))) {
                    self.cycleCategory(true);
                    return true;
                }
                if (self.focus == 0 and !self.category_menu_open and (std.mem.eql(u8, key, "<Right>") or std.mem.eql(u8, key, "<Down>"))) {
                    self.cycleCategory(false);
                    return true;
                }
                if (self.focus == 0 and std.mem.eql(u8, key, "<Enter>")) {
                    if (self.category_menu_open) self.closeCategoryMenu(true) else self.openCategoryMenu();
                    return true;
                }
                if (std.mem.eql(u8, key, "<BS>")) {
                    if (self.focus == 1 and self.summary.items.len > 0) _ = self.summary.pop();
                    if (self.focus == 2 and self.description.items.len > 0) _ = self.description.pop();
                    return true;
                }
                if (std.mem.eql(u8, key, "<Enter>")) {
                    if (self.focus == 2 and self.description.items.len < max_description) self.description.append('\n') catch {} else if (self.focus == 3) self.requestConsent();
                    return true;
                }
                if (key.len == 1 and key[0] >= 0x20 and key[0] != 0x7f) {
                    if (self.focus == 1 and self.summary.items.len < max_summary) self.summary.append(key[0]) catch {};
                    if (self.focus == 2 and self.description.items.len < max_description) self.description.append(key[0]) catch {};
                    return true;
                }
            },
            .consent => {
                if (std.mem.eql(u8, key, "<Left>") or std.mem.eql(u8, key, "<Right>") or std.mem.eql(u8, key, "<Tab>")) self.consent_yes = !self.consent_yes;
                if (std.mem.eql(u8, key, "<Enter>")) self.submit(self.consent_yes) catch |err| self.fail(@errorName(err));
                return true;
            },
            .success => {
                if (std.mem.eql(u8, key, "<Enter>")) {
                    self.is_open = false;
                    self.reset();
                }
                return true;
            },
            .failure => {
                if (std.mem.eql(u8, key, "<Enter>")) self.stage = .consent;
                return true;
            },
            .submitting => return true,
        }
        return true;
    }

    pub fn handlePaste(self: *BugReportWidget, text: []const u8) bool {
        if (!self.is_open or self.stage != .form or (self.focus != 1 and self.focus != 2)) return false;
        const target = if (self.focus == 1) &self.summary else &self.description;
        const limit: usize = if (self.focus == 1) max_summary else max_description;
        for (text) |c| {
            if (target.items.len >= limit) break;
            if (c >= 0x20 or (c == '\n' and self.focus == 2)) target.append(c) catch break;
        }
        return true;
    }

    fn requestConsent(self: *BugReportWidget) void {
        if (std.mem.trim(u8, self.summary.items, " \t\r\n").len == 0 or std.mem.trim(u8, self.description.items, " \t\r\n").len == 0) return;
        self.stage = .consent;
        self.consent_yes = false;
    }

    pub fn handleMouse(self: *BugReportWidget, m: input.MouseEvent, screen_w: u16, screen_h: u16) bool {
        if (!self.is_open) return false;
        const r = modal(screen_w, screen_h).rect;
        if (primitives.containsRect(.{ .x = r.x + r.w - 4, .y = r.y, .w = 3, .h = 1 }, m.col, m.row) and self.stage != .submitting) {
            self.is_open = false;
            return true;
        }
        if (self.stage == .form) {
            const category_rect: Rect = .{ .x = r.x + 3, .y = r.y + 3, .w = r.w - 6, .h = 1 };
            if (self.category_menu_open) {
                const menu_h: u16 = @as(u16, @intCast(categoryVisibleCount() + 2));
                const menu_rect = Rect{ .x = r.x + 3, .y = r.y + 4, .w = r.w - 6, .h = menu_h };
                if (m.button == .wheel_up or m.button == .wheel_down) {
                    if (m.button == .wheel_up) self.cycleCategory(true) else self.cycleCategory(false);
                    return true;
                }
                if (primitives.containsRect(menu_rect, m.col, m.row)) {
                    const rel_y = m.row - menu_rect.y;
                    if (rel_y >= 1 and rel_y <= menu_rect.h - 2) {
                        const clicked = self.category_menu_scroll + (rel_y - 1);
                        if (clicked < categoryCount()) {
                            self.category_menu_idx = clicked;
                            self.closeCategoryMenu(true);
                        }
                    }
                    return true;
                }
                if (m.button == .wheel_up or m.button == .wheel_down) return true;
                if (m.action == .press) {
                    if (primitives.containsRect(category_rect, m.col, m.row)) {
                        self.closeCategoryMenu(true);
                    } else {
                        self.closeCategoryMenu(false);
                    }
                    return true;
                }
            }
            if (m.row == r.y + 3) {
                self.focus = 0;
                if (primitives.containsRect(category_rect, m.col, m.row)) {
                    if (self.category_menu_open) self.closeCategoryMenu(true) else self.openCategoryMenu();
                }
            } else if (m.row == r.y + 6) self.focus = 1 else if (m.row >= r.y + 9 and m.row < r.y + 16) self.focus = 2;
            if (primitives.containsRect(.{ .x = r.x + r.w - 14, .y = r.y + r.h - 3, .w = 10, .h = 1 }, m.col, m.row)) {
                self.focus = 3;
                self.requestConsent();
            }
        } else if (self.stage == .consent) {
            if (primitives.containsRect(.{ .x = r.x + 3, .y = r.y + r.h - 4, .w = 20, .h = 1 }, m.col, m.row)) {
                self.consent_yes = true;
                self.submit(true) catch |err| self.fail(@errorName(err));
            }
            if (primitives.containsRect(.{ .x = r.x + 26, .y = r.y + r.h - 4, .w = 22, .h = 1 }, m.col, m.row)) {
                self.consent_yes = false;
                self.submit(false) catch |err| self.fail(@errorName(err));
            }
        } else if (self.stage == .success) {
            self.is_open = false;
            self.reset();
        } else if (self.stage == .failure) self.stage = .consent;
        return true;
    }

    fn jsonEscape(out: *std.array_list.Managed(u8), value: []const u8) !void {
        for (value) |c| switch (c) {
            '"' => try out.appendSlice("\\\""),
            '\\' => try out.appendSlice("\\\\"),
            '\n' => try out.appendSlice("\\n"),
            '\r' => try out.appendSlice("\\r"),
            '\t' => try out.appendSlice("\\t"),
            0...8, 11...12, 14...0x1f => {},
            else => try out.append(c),
        };
    }

    fn appendRedacted(self: *BugReportWidget, out: *std.array_list.Managed(u8), source: []const u8) !void {
        const home = self.home_dir;
        var i: usize = 0;
        while (i < source.len) {
            if (home.len > 1 and std.mem.startsWith(u8, source[i..], home)) {
                try out.appendSlice("~");
                i += home.len;
                continue;
            }
            const rest = source[i..];
            const secret_prefixes = [_][]const u8{ "ghp_", "gho_", "ghu_", "ghs_", "github_pat_", "Bearer ", "Basic ", "token=", "token:", "access_token=", "password=", "secret=", "api_key=", "apikey=" };
            var matched = false;
            for (secret_prefixes) |prefix| if (std.ascii.startsWithIgnoreCase(rest, prefix)) {
                try out.appendSlice("[REDACTED]");
                i += prefix.len;
                while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}
                if (i < source.len and (source[i] == '"' or source[i] == '\'')) i += 1;
                while (i < source.len and !std.ascii.isWhitespace(source[i]) and source[i] != '"' and source[i] != '\'') : (i += 1) {}
                matched = true;
                break;
            };
            if (!matched) {
                try out.append(source[i]);
                i += 1;
            }
        }
    }

    fn readLogs(self: *BugReportWidget) ![]u8 {
        const log_file_path = try std.fs.path.join(self.allocator, &.{ self.data_dir, "tuim.log" });
        defer self.allocator.free(log_file_path);
        const path_z = try self.allocator.dupeSentinel(u8, log_file_path, 0);
        defer self.allocator.free(path_z);
        const fd = try std.posix.openatZ(std.posix.AT.FDCWD, path_z, .{ .ACCMODE = .RDONLY }, 0);
        defer _ = std.posix.system.close(fd);
        const end_raw = std.posix.system.lseek(fd, 0, std.posix.SEEK.END);
        const end: i64 = if (std.posix.errno(end_raw) == .SUCCESS) @bitCast(end_raw) else 0;
        const start: i64 = @max(0, end - max_log_bytes);
        _ = std.posix.system.lseek(fd, @bitCast(start), std.posix.SEEK.SET);
        var raw = std.array_list.Managed(u8).init(self.allocator);
        defer raw.deinit();
        while (raw.items.len < max_log_bytes) {
            var buf: [2048]u8 = undefined;
            const n = std.posix.read(fd, &buf) catch break;
            if (n == 0) break;
            try raw.appendSlice(buf[0..@min(n, max_log_bytes - raw.items.len)]);
        }
        var clean = std.array_list.Managed(u8).init(self.allocator);
        errdefer clean.deinit();
        try self.appendRedacted(&clean, raw.items);
        return clean.toOwnedSlice();
    }

    fn path(self: *BugReportWidget, name: []const u8) ![]u8 {
        return std.fs.path.join(self.allocator, &.{ self.data_dir, name });
    }

    fn submit(self: *BugReportWidget, include_logs: bool) !void {
        if (self.endpoint.len == 0) return error.ReportingEndpointNotConfigured;
        errdefer self.cleanupSubmissionFiles();
        const payload_path = try self.path("bug-report-payload.json");
        defer self.allocator.free(payload_path);
        const response_path = try self.path("bug-report-response.json");
        defer self.allocator.free(response_path);
        const status_path = try self.path("bug-report-status");
        defer self.allocator.free(status_path);
        std.Io.Dir.cwd().deleteFile(self.io, response_path) catch {};
        std.Io.Dir.cwd().deleteFile(self.io, status_path) catch {};

        var json = std.array_list.Managed(u8).init(self.allocator);
        defer json.deinit();
        try json.appendSlice("{\"category\":\"");
        try jsonEscape(&json, self.category.label());
        try json.appendSlice("\",\"summary\":\"");
        try jsonEscape(&json, self.summary.items);
        try json.appendSlice("\",\"description\":\"");
        try jsonEscape(&json, self.description.items);
        try json.appendSlice("\",\"metadata\":{\"tuimVersion\":\"");
        try jsonEscape(&json, self.version);
        try json.appendSlice("\",\"os\":\"");
        try jsonEscape(&json, @tagName(builtin.os.tag));
        try json.appendSlice("\",\"osVersion\":\"");
        try jsonEscape(&json, self.os_version);
        try json.appendSlice("\",\"kernel\":\"");
        try jsonEscape(&json, self.kernel);
        try json.appendSlice("\",\"architecture\":\"");
        try jsonEscape(&json, self.architecture);
        try json.appendSlice("\",\"displayServer\":\"");
        try jsonEscape(&json, self.display_server);
        try json.appendSlice("\",\"desktop\":\"");
        try jsonEscape(&json, self.desktop);
        try json.appendSlice("\",\"terminal\":\"");
        try jsonEscape(&json, self.terminal);
        try json.appendSlice("\",\"terminalVersion\":\"");
        try jsonEscape(&json, self.terminal_version);
        try json.appendSlice("\",\"term\":\"");
        try jsonEscape(&json, self.term);
        try json.appendSlice("\",\"shell\":\"");
        try jsonEscape(&json, self.shell);
        try json.appendSlice("\"},\"logs\":");
        if (include_logs) {
            const logs = self.readLogs() catch null;
            if (logs) |value| {
                defer self.allocator.free(value);
                try json.append('"');
                try jsonEscape(&json, value);
                try json.append('"');
            } else try json.appendSlice("null");
        } else try json.appendSlice("null");
        try json.append('}');

        const payload_z = try self.allocator.dupeSentinel(u8, payload_path, 0);
        defer self.allocator.free(payload_z);
        const fd = try std.posix.openatZ(std.posix.AT.FDCWD, payload_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o600);
        defer _ = std.posix.system.close(fd);
        var written: usize = 0;
        while (written < json.items.len) {
            const rc = std.posix.system.write(fd, json.items[written..].ptr, json.items.len - written);
            if (std.posix.errno(rc) != .SUCCESS) return error.WriteFailed;
            written += @intCast(rc);
        }

        const command = "curl -sS --max-time 20 -H 'Content-Type: application/json' --data-binary @\"$2\" -o \"$3\" -w '%{http_code}' \"$1\" >\"$4\" 2>/dev/null &";
        const argv = &[_][]const u8{ "sh", "-c", command, "tuim-bug-report", self.endpoint, payload_path, response_path, status_path };
        var child = try std.process.spawn(self.io, .{ .argv = argv, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore });
        const term = try child.wait(self.io);
        if (term != .exited or term.exited != 0) return error.ReportLaunchFailed;
        self.stage = .submitting;
    }

    fn fail(self: *BugReportWidget, message: []const u8) void {
        if (self.error_message) |v| self.allocator.free(v);
        self.error_message = self.allocator.dupe(u8, message) catch null;
        self.stage = .failure;
    }

    fn cleanupSubmissionFiles(self: *BugReportWidget) void {
        const names = [_][]const u8{ "bug-report-payload.json", "bug-report-response.json", "bug-report-status" };
        for (names) |name| {
            const file_path = self.path(name) catch continue;
            defer self.allocator.free(file_path);
            std.Io.Dir.cwd().deleteFile(self.io, file_path) catch {};
        }
    }

    pub fn poll(self: *BugReportWidget) bool {
        if (self.stage != .submitting) return false;
        const status_path = self.path("bug-report-status") catch return false;
        defer self.allocator.free(status_path);
        const z = self.allocator.dupeSentinel(u8, status_path, 0) catch return false;
        defer self.allocator.free(z);
        const fd = std.posix.openatZ(std.posix.AT.FDCWD, z, .{ .ACCMODE = .RDONLY }, 0) catch return false;
        defer _ = std.posix.system.close(fd);
        var status_buf: [4]u8 = undefined;
        const n = std.posix.read(fd, &status_buf) catch return false;
        if (n < 3) return false;
        const code = std.fmt.parseInt(u16, status_buf[0..3], 10) catch 0;
        if (code != 201) {
            self.fail(if (code == 0) "The reporting service could not be reached." else "The reporting service rejected the report.");
            self.cleanupSubmissionFiles();
            return true;
        }
        defer self.cleanupSubmissionFiles();

        const response_path = self.path("bug-report-response.json") catch {
            self.stage = .success;
            return true;
        };
        defer self.allocator.free(response_path);
        const rz = self.allocator.dupeSentinel(u8, response_path, 0) catch {
            self.stage = .success;
            return true;
        };
        defer self.allocator.free(rz);
        const rfd = std.posix.openatZ(std.posix.AT.FDCWD, rz, .{ .ACCMODE = .RDONLY }, 0) catch {
            self.stage = .success;
            return true;
        };
        defer _ = std.posix.system.close(rfd);
        var buf: [2048]u8 = undefined;
        const rn = std.posix.read(rfd, &buf) catch 0;
        if (std.mem.indexOf(u8, buf[0..rn], "\"issueUrl\":\"")) |start_raw| {
            const start = start_raw + 12;
            if (std.mem.indexOfScalar(u8, buf[start..rn], '"')) |rel_end| self.issue_url = self.allocator.dupe(u8, buf[start .. start + rel_end]) catch null;
        }
        self.stage = .success;
        return true;
    }
};

test "redaction removes credentials and home paths" {
    var environ = std.process.Environ.Map.init(std.testing.allocator);
    defer environ.deinit();
    var widget = try BugReportWidget.init(std.testing.allocator, std.testing.io, "/tmp", "/home/test", "https://example.test", "test", &environ);
    defer widget.deinit();
    var out = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out.deinit();
    try widget.appendRedacted(&out, "Authorization: Bearer secret-value token=another /home/test/private\n");
    try std.testing.expect(std.mem.indexOf(u8, out.items, "secret-value") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "another") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "/home/test") == null);
}

test "bug report category menu keeps selection and scroll aligned" {
    var environ = std.process.Environ.Map.init(std.testing.allocator);
    defer environ.deinit();
    var widget = try BugReportWidget.init(std.testing.allocator, std.testing.io, "/tmp", "/home/test", "https://example.test", "test", &environ);
    defer widget.deinit();
    widget.category = .other;
    widget.openCategoryMenu();
    try std.testing.expect(widget.category_menu_open);
    try std.testing.expectEqual(@as(usize, 5), widget.category_menu_idx);
    try std.testing.expect(widget.category_menu_scroll <= widget.category_menu_idx);
    widget.cycleCategory(true);
    try std.testing.expectEqual(@as(usize, 4), widget.category_menu_idx);
    widget.closeCategoryMenu(true);
    try std.testing.expectEqual(Category.performance, widget.category);
    try std.testing.expect(!widget.category_menu_open);
}

test "bug report detects display and terminal environment without identity data" {
    var environ = std.process.Environ.Map.init(std.testing.allocator);
    defer environ.deinit();
    try environ.put("XDG_SESSION_TYPE", "wayland");
    try environ.put("XDG_CURRENT_DESKTOP", "KDE");
    try environ.put("TERM_PROGRAM", "WezTerm");
    try environ.put("TERM_PROGRAM_VERSION", "2026.1");
    try environ.put("TERM", "xterm-256color");
    try environ.put("SHELL", "/bin/zsh");

    var widget = try BugReportWidget.init(std.testing.allocator, std.testing.io, "/tmp", "/home/test", "https://example.test", "test", &environ);
    defer widget.deinit();
    try std.testing.expectEqualStrings("wayland", widget.display_server);
    try std.testing.expectEqualStrings("KDE", widget.desktop);
    try std.testing.expectEqualStrings("WezTerm", widget.terminal);
    try std.testing.expectEqualStrings("2026.1", widget.terminal_version);
    try std.testing.expectEqualStrings("zsh", widget.shell);
}

test "bug report description wraps long and wide-character lines" {
    var lines = WrappedLineIterator.init("abcdefg\nab界c", 6);
    try std.testing.expectEqualStrings("abcdef", lines.next().?);
    try std.testing.expectEqualStrings("g", lines.next().?);
    try std.testing.expectEqualStrings("ab界c", lines.next().?);
    try std.testing.expect(lines.next() == null);

    var wide_lines = WrappedLineIterator.init("ab界cd", 4);
    try std.testing.expectEqualStrings("ab界", wide_lines.next().?);
    try std.testing.expectEqualStrings("cd", wide_lines.next().?);
    try std.testing.expect(wide_lines.next() == null);
}

test "bug report description keeps the newest wrapped rows visible" {
    const text = "first\nsecond\nthird\nfourth\nfifth\nsixth";
    try std.testing.expectEqual(@as(usize, 6), wrappedLineCount(text, 20));
    try std.testing.expectEqual(@as(usize, 1), wrappedLineSkip(text, 20, 5));

    var trailing_newline = WrappedLineIterator.init("line\n", 20);
    try std.testing.expectEqualStrings("line", trailing_newline.next().?);
    try std.testing.expectEqualStrings("", trailing_newline.next().?);
    try std.testing.expect(trailing_newline.next() == null);
}
