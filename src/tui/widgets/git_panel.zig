const std = @import("std");
const renderer = @import("../renderer.zig");
const Color = renderer.Color;
const Rect = @import("../layout.zig").Rect;
const primitives = @import("primitives.zig");
const git_utils = @import("git_utils.zig");
const GitSnapshot = @import("../../git_snapshot.zig").GitSnapshot;

pub const GitItem = struct {
    path: []const u8,
    status: [2]u8, // e.g. "M ", " M", "??", "A "
    is_staged: bool,
};

pub const ActionState = enum { none, committing };

pub const GitPanel = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    arena: std.heap.ArenaAllocator,
    items: std.array_list.Managed(GitItem),

    current_branch: ?[]const u8 = null,
    recent_commits: std.array_list.Managed([]const u8),

    scroll_y: usize = 0,
    selected_idx: ?usize = null,

    is_staged_open: bool = true,
    is_changes_open: bool = true,
    is_commits_open: bool = true,

    commit_buf: [4096]u8 = undefined,
    commit_len: usize = 0,
    is_focus_commit: bool = false,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) GitPanel {
        return GitPanel{
            .allocator = allocator,
            .io = io,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .items = std.array_list.Managed(GitItem).init(allocator),
            .recent_commits = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *GitPanel) void {
        self.items.deinit();
        self.recent_commits.deinit();
        self.arena.deinit();
    }

    pub fn refresh(self: *GitPanel) !void {
        self.items.clearRetainingCapacity();
        self.recent_commits.clearRetainingCapacity();
        _ = self.arena.reset(.retain_capacity);

        // 1. Fetch current branch
        {
            const argv = [_][]const u8{ "git", "branch", "--show-current" };
            if (git_utils.runGitCommand(self.allocator, self.io, &argv)) |stdout| {
                defer self.allocator.free(stdout);
                if (stdout.len > 0) {
                    const clean_branch = std.mem.trim(u8, stdout, " \n\r");
                    self.current_branch = try self.arena.allocator().dupe(u8, clean_branch);
                } else {
                    self.current_branch = null;
                }
            } else |_| {
                self.current_branch = null;
            }
        }

        // 2. Fetch recent commits (Pipeline Graph)
        {
            const argv = [_][]const u8{ "git", "log", "--graph", "--abbrev-commit", "--format=format:%h - %s", "-n", "15" };
            if (git_utils.runGitCommand(self.allocator, self.io, &argv)) |stdout| {
                defer self.allocator.free(stdout);
                var lines = std.mem.splitScalar(u8, stdout, '\n');
                while (lines.next()) |line| {
                    var end: usize = line.len;
                    while (end > 0 and (line[end - 1] == '\r' or line[end - 1] == ' ')) {
                        end -= 1;
                    }
                    const clean_line = line[0..end];
                    if (clean_line.len > 0) {
                        try self.recent_commits.append(try self.arena.allocator().dupe(u8, clean_line));
                    }
                }
            } else |_| {}
        }

        // 3. Fetch status (-z keeps renames and non-ASCII paths intact)
        const argv = [_][]const u8{ "git", "status", "--porcelain=v1", "-z" };
        const stdout_val = git_utils.runGitCommand(self.allocator, self.io, &argv) catch return;
        defer self.allocator.free(stdout_val);
        var snapshot = try GitSnapshot.parse(self.allocator, "", "", stdout_val);
        defer snapshot.deinit();
        for (snapshot.status) |item| try self.items.append(.{
            .path = try self.arena.allocator().dupe(u8, item.path),
            .status = item.code,
            .is_staged = item.staged,
        });
    }

    /// Reactor-thread ownership transfer from the background refresh worker.
    /// Snapshot storage is copied into the panel arena before it is released;
    /// no worker-owned pointer survives this call.
    pub fn applySnapshot(self: *GitPanel, snapshot: *const GitSnapshot) !void {
        self.items.clearRetainingCapacity();
        self.recent_commits.clearRetainingCapacity();
        _ = self.arena.reset(.retain_capacity);
        const owned = self.arena.allocator();
        self.current_branch = if (snapshot.branch) |branch| try owned.dupe(u8, branch) else null;
        for (snapshot.commits) |commit_line| try self.recent_commits.append(try owned.dupe(u8, commit_line));
        for (snapshot.status) |item| try self.items.append(.{
            .path = try owned.dupe(u8, item.path),
            .status = item.code,
            .is_staged = item.staged,
        });
    }

    fn actionRect(rect: Rect, row: u16) Rect {
        // Leave three columns clear before the sidebar edge/resize handle.
        return .{ .x = rect.x + rect.w -| 6, .y = row, .w = if (rect.w >= 12) 3 else 0, .h = 1 };
    }

    pub fn handleMouse(self: *GitPanel, m_col: u16, m_row: u16, rect: Rect) !?[]const u8 {
        if (m_col >= rect.x and m_col < rect.x + rect.w and m_row >= rect.y and m_row < rect.y + rect.h) {
            const rel_y = m_row - rect.y;

            // Header line
            if (rel_y == 0) {
                if (m_col >= rect.x + rect.w - 10) {
                    return "__CMD__:GitWidget";
                }
                return null;
            }

            var cy: u16 = 1;

            // Branch line (no interaction anymore)
            if (rel_y == cy) {
                return null;
            }
            cy += 1;

            // Commit box
            if (rel_y == cy) {
                self.is_focus_commit = true;
                return null;
            } else {
                self.is_focus_commit = false;
            }
            cy += 1;

            // Divider
            cy += 1;

            // Headers and lists
            var i: usize = self.scroll_y;

            var has_staged = false;
            var has_unstaged = false;
            for (self.items.items) |item| {
                if (item.is_staged) has_staged = true;
                if (!item.is_staged) has_unstaged = true;
            }

            if (has_staged) {
                if (cy == rel_y) {
                    self.is_staged_open = !self.is_staged_open;
                    return null;
                }
                cy += 1;
                if (self.is_staged_open) {
                    while (i < self.items.items.len and self.items.items[i].is_staged and cy < rect.h) : ({
                        i += 1;
                        cy += 1;
                    }) {
                        if (cy == rel_y) {
                            self.selected_idx = i;
                            // check action buttons
                            if (primitives.containsRect(actionRect(rect, m_row), m_col, m_row)) {
                                try self.unstageFile(self.items.items[i].path);
                                return null;
                            }
                            return self.items.items[i].path;
                        }
                    }
                } else {
                    while (i < self.items.items.len and self.items.items[i].is_staged) : (i += 1) {}
                }
            }

            if (has_unstaged and cy < rect.h) {
                if (cy == rel_y) {
                    self.is_changes_open = !self.is_changes_open;
                    return null;
                }
                cy += 1;
                if (self.is_changes_open) {
                    while (i < self.items.items.len and !self.items.items[i].is_staged and cy < rect.h) : ({
                        i += 1;
                        cy += 1;
                    }) {
                        if (cy == rel_y) {
                            self.selected_idx = i;
                            // check action buttons
                            if (primitives.containsRect(actionRect(rect, m_row), m_col, m_row)) {
                                try self.stageFile(self.items.items[i].path);
                                return null;
                            }
                            return self.items.items[i].path;
                        }
                    }
                } else {
                    while (i < self.items.items.len and !self.items.items[i].is_staged) : (i += 1) {}
                }
            }

            // Commits
            if (self.recent_commits.items.len > 0 and cy < rect.h) {
                cy += 1;
                if (cy < rect.h) {
                    if (cy == rel_y) {
                        self.is_commits_open = !self.is_commits_open;
                        return null;
                    }
                    cy += 1;
                    if (self.is_commits_open) {
                        for (self.recent_commits.items) |_| {
                            if (cy >= rect.h) break;
                            if (cy == rel_y) return null;
                            cy += 1;
                        }
                    }
                }
            }
        }
        return null;
    }

    pub fn handleScroll(self: *GitPanel, dy: i32) void {
        if (dy < 0) {
            if (self.scroll_y > 0) self.scroll_y -= 1;
        } else if (dy > 0) {
            if (self.scroll_y + 1 < self.items.items.len) {
                self.scroll_y += 1;
            }
        }
    }

    pub fn handleKey(self: *GitPanel, key: []const u8, height: u16) !bool {
        if (self.is_focus_commit) {
            if (std.mem.eql(u8, key, "<Enter>")) {
                if (self.commit_len > 0) {
                    try self.commit();
                }
                return true;
            } else if (std.mem.eql(u8, key, "<Esc>") or (key.len == 1 and key[0] == 0x1b)) {
                self.is_focus_commit = false;
                return true;
            } else if (std.mem.eql(u8, key, "<BS>") or std.mem.eql(u8, key, "\x7f")) {
                // Drop a whole UTF-8 sequence, not just its last byte.
                while (self.commit_len > 0 and self.commit_buf[self.commit_len - 1] & 0xC0 == 0x80) self.commit_len -= 1;
                if (self.commit_len > 0) self.commit_len -= 1;
                return true;
            } else if (key.len > 0 and (key.len == 1 or key[0] != '<')) {
                // Refuse keys that would overflow instead of truncating the message.
                if (self.commit_len + key.len > self.commit_buf.len) return true;
                for (key) |c| {
                    if (c >= 32 and c != 127) {
                        self.commit_buf[self.commit_len] = c;
                        self.commit_len += 1;
                    }
                }
            }
            return true;
        }
        if (std.mem.eql(u8, key, "c")) {
            self.is_focus_commit = true;
            return true;
        }
        const down = std.mem.eql(u8, key, "<Down>") or std.mem.eql(u8, key, "j");
        const up = std.mem.eql(u8, key, "<Up>") or std.mem.eql(u8, key, "k");
        const home = std.mem.eql(u8, key, "<Home>");
        const end = std.mem.eql(u8, key, "<End>");
        const toggle = std.mem.eql(u8, key, " ") or std.mem.eql(u8, key, "<Space>");
        const stage = std.mem.eql(u8, key, "s") or std.mem.eql(u8, key, "+");
        const unstage = std.mem.eql(u8, key, "u") or std.mem.eql(u8, key, "-");
        const open = std.mem.eql(u8, key, "<Enter>");
        if (!(down or up or home or end or toggle or stage or unstage or open)) return false;
        if (self.items.items.len == 0) {
            self.selected_idx = null;
            self.scroll_y = 0;
            return true;
        }
        const had_selection = self.selected_idx != null;
        var idx = @min(self.selected_idx orelse 0, self.items.items.len - 1);
        if (home) idx = 0 else if (end) idx = self.items.items.len - 1 else if (down and had_selection) idx = @min(idx + 1, self.items.items.len - 1) else if (up) idx -|= 1;
        self.selected_idx = idx;
        if (toggle or stage or unstage) {
            const item = self.items.items[idx];
            if (toggle or (stage and !item.is_staged) or (unstage and item.is_staged)) {
                const path = try self.allocator.dupe(u8, item.path);
                defer self.allocator.free(path);
                if (item.is_staged) try self.unstageFile(path) else try self.stageFile(path);
                self.selected_idx = null;
                for (self.items.items, 0..) |next, i| {
                    if (std.mem.eql(u8, next.path, path) and next.is_staged != item.is_staged) {
                        self.selected_idx = i;
                        break;
                    }
                }
                if (self.selected_idx == null and self.items.items.len > 0) self.selected_idx = @min(idx, self.items.items.len - 1);
            }
        }
        // Reveal the selected file even if its section was collapsed by mouse.
        self.is_staged_open = true;
        self.is_changes_open = true;
        if (self.selected_idx) |selected| {
            const visible = @max(1, height -| 7);
            if (selected < self.scroll_y) self.scroll_y = selected;
            if (selected >= self.scroll_y + visible) self.scroll_y = selected - visible + 1;
        }
        return true;
    }

    pub fn selectedPath(self: *const GitPanel) ?[]const u8 {
        const idx = self.selected_idx orelse return null;
        return if (idx < self.items.items.len) self.items.items[idx].path else null;
    }

    fn stageFile(self: *GitPanel, path: []const u8) !void {
        const argv = [_][]const u8{ "git", "add", "--", path };
        if (git_utils.runGitCommand(self.allocator, self.io, &argv)) |res| {
            self.allocator.free(res);
        } else |err| return err;
        try self.refresh();
    }

    fn unstageFile(self: *GitPanel, path: []const u8) !void {
        const argv = [_][]const u8{ "git", "restore", "--staged", "--", path };
        if (git_utils.runGitCommand(self.allocator, self.io, &argv)) |res| {
            self.allocator.free(res);
        } else |err| return err;
        try self.refresh();
    }

    fn commit(self: *GitPanel) !void {
        if (self.commit_len == 0) return;
        const msg = self.commit_buf[0..self.commit_len];
        const argv = [_][]const u8{ "git", "commit", "-m", msg };
        // On failure keep the draft; the caller reports the error.
        self.allocator.free(try git_utils.runGitCommand(self.allocator, self.io, &argv));

        self.commit_len = 0;
        self.is_focus_commit = false;
        try self.refresh();
    }

    /// Length of the longest prefix of `text` ending on a complete UTF-8
    /// character. Input arrives in raw reads, so the last character can still
    /// be missing bytes; decoding those would assert instead of erroring.
    fn completeLen(text: []const u8) usize {
        var seq = text.len;
        while (seq > 0 and text[seq - 1] & 0xC0 == 0x80) seq -= 1;
        if (seq == 0) return 0;
        seq -= 1;
        const need = std.unicode.utf8ByteSequenceLength(text[seq]) catch return text.len;
        return if (text.len - seq < need) seq else text.len;
    }

    /// Byte offset of the longest suffix of `text` that fits in `max_cells`.
    fn tailStart(text: []const u8, max_cells: u16) usize {
        var start = text.len;
        var used: usize = 0;
        while (start > 0) {
            var prev = start - 1;
            while (prev > 0 and text[prev] & 0xC0 == 0x80) prev -= 1;
            const cp = decodeOrReplacement(text[prev..start]);
            used += renderer.unicodeCellWidth(cp);
            if (used > max_cells) break;
            start = prev;
        }
        return start;
    }

    fn decodeOrReplacement(bytes: []const u8) u21 {
        const len = std.unicode.utf8ByteSequenceLength(bytes[0]) catch return 0xFFFD;
        if (len != bytes.len) return 0xFFFD;
        return std.unicode.utf8Decode(bytes) catch 0xFFFD;
    }

    fn drawTextClipped(rend: *renderer.Renderer, x: u16, y: u16, text: []const u8, max_w: u16, fg: Color, bg: Color, bold: bool, italic: bool) void {
        rend.drawTextClipped(x, y, max_w, text, fg, bg, bold, italic);
    }

    fn drawEllipsized(rend: *renderer.Renderer, x: u16, y: u16, text: []const u8, max_w: u16, fg: Color, bg: Color) void {
        const width = @min(max_w, rend.width -| x);
        var iter = (std.unicode.Utf8View.init(text) catch return).iterator();
        var cells: usize = 0;
        while (iter.nextCodepoint()) |cp| cells += renderer.unicodeCellWidth(cp);
        if (cells <= width) {
            rend.drawTextClipped(x, y, width, text, fg, bg, false, false);
            return;
        }
        const dots = @min(width, 3);
        iter = (std.unicode.Utf8View.init(text) catch return).iterator();
        var used: u16 = 0;
        var end: usize = 0;
        while (iter.nextCodepoint()) |cp| {
            const next = renderer.unicodeCellWidth(cp);
            if (used + next > width - dots) break;
            used += next;
            end = iter.i;
        }
        rend.drawTextClipped(x, y, used, text[0..end], fg, bg, false, false);
        rend.drawTextClipped(x + used, y, dots, "...", fg, bg, false, false);
    }

    pub fn draw(self: *GitPanel, rend: *renderer.Renderer, rect: Rect, colors: anytype) void {
        rend.drawRect(rect, " ", colors.fg_primary, colors.bg_sidebar);

        // Draw title
        drawTextClipped(rend, rect.x + 1, rect.y, "SOURCE CONTROL", rect.w - 1, colors.fg_secondary, colors.bg_sidebar, true, false);

        // Detailed widget button
        if (rect.w >= 12) {
            rend.drawControlText(rect.x + rect.w - 10, rect.y, "[ More ]", colors.fg_accent, colors.bg_editor, true, false);
        }

        if (rect.h < 3) return;

        var cy: u16 = 1;

        // Branch Section
        var buf: [256]u8 = undefined;
        const branch_name = self.current_branch orelse "unknown";
        const branch_str = std.fmt.bufPrint(&buf, " {s}", .{branch_name}) catch " unknown";
        drawTextClipped(rend, rect.x + 1, rect.y + cy, branch_str, rect.w - 2, colors.fg_accent, colors.bg_sidebar, true, false);
        cy += 1;

        // Commit Box
        const c_bg = if (self.is_focus_commit) colors.bg_editor else colors.bg_sidebar;
        rend.drawRect(Rect{ .x = rect.x + 1, .y = rect.y + cy, .w = rect.w - 2, .h = 1 }, " ", colors.fg_primary, c_bg);
        var msg_buf: [4097]u8 = undefined;
        const box_w = rect.w -| 4;
        const draft = self.commit_buf[0..completeLen(self.commit_buf[0..self.commit_len])];
        // Show the tail so the cursor stays visible in long messages.
        const shown = if (self.is_focus_commit) draft[tailStart(draft, box_w -| 1)..] else draft;
        const msg = std.fmt.bufPrint(&msg_buf, "{s}{s}", .{ shown, if (self.is_focus_commit) "_" else "" }) catch "";
        if (msg.len > 0) {
            drawTextClipped(rend, rect.x + 2, rect.y + cy, msg, rect.w - 4, colors.fg_primary, c_bg, false, false);
        } else {
            drawTextClipped(rend, rect.x + 2, rect.y + cy, "Message (Enter to commit)", rect.w - 4, colors.fg_secondary, c_bg, false, false);
        }
        cy += 1;
        if (cy >= rect.h) return;

        rend.highlightHover(.{ .x = rect.x + 1, .y = rect.y + cy - 1, .w = rect.w -| 2, .h = 1 }, colors.bg_sidebar, colors.fg_primary);

        // Divider
        var i_w: u16 = 0;
        while (i_w < rect.w) : (i_w += 1) {
            rend.drawText(rect.x + i_w, rect.y + cy, "─", colors.border_color, colors.bg_sidebar, false, false);
        }
        cy += 1;

        var i: usize = self.scroll_y;

        var has_staged = false;
        var has_unstaged = false;
        for (self.items.items) |item| {
            if (item.is_staged) has_staged = true;
            if (!item.is_staged) has_unstaged = true;
        }

        if (has_staged and cy < rect.h) {
            const icon = if (self.is_staged_open) "v" else ">";
            const header = std.fmt.bufPrint(&buf, "{s} Staged Changes", .{icon}) catch "v Staged Changes";
            drawTextClipped(rend, rect.x + 1, rect.y + cy, header, rect.w - 1, colors.fg_secondary, colors.bg_sidebar, true, false);
            rend.highlightHover(.{ .x = rect.x, .y = rect.y + cy, .w = rect.w -| 1, .h = 1 }, colors.bg_sidebar, colors.fg_primary);
            cy += 1;
            if (self.is_staged_open) {
                while (i < self.items.items.len and self.items.items[i].is_staged and cy < rect.h) : ({
                    i += 1;
                    cy += 1;
                }) {
                    const item = self.items.items[i];
                    defer rend.highlightHover(.{ .x = rect.x, .y = rect.y + cy, .w = rect.w -| 1, .h = 1 }, colors.bg_sidebar, colors.fg_primary);
                    const is_sel = (self.selected_idx != null and self.selected_idx.? == i);
                    const bg = if (is_sel) colors.bg_accent else colors.bg_sidebar;
                    const fg = @import("../theme.zig").readableForeground(colors.fg_primary, bg, 4.5);
                    if (is_sel) {
                        rend.drawRect(Rect{ .x = rect.x, .y = rect.y + cy, .w = rect.w -| 1, .h = 1 }, " ", fg, bg);
                        rend.drawText(rect.x, rect.y + cy, ">", fg, bg, true, false);
                    }

                    drawEllipsized(rend, rect.x + 2, rect.y + cy, item.path, rect.w -| 12, fg, bg);
                    const status_str = std.fmt.bufPrint(&buf, "{s}", .{item.status}) catch "";
                    rend.drawText(rect.x + rect.w -| 9, rect.y + cy, status_str, .{ .rgb = .{ .r = 80, .g = 255, .b = 80 } }, bg, false, false);
                    const action = actionRect(rect, rect.y + cy);
                    rend.drawButtonText(action.x, action.y, action.w, " - ", colors.fg_accent, bg, true, false);
                }
            } else {
                while (i < self.items.items.len and self.items.items[i].is_staged) : (i += 1) {}
            }
        }

        if (has_unstaged and cy < rect.h) {
            const icon = if (self.is_changes_open) "v" else ">";
            const header = std.fmt.bufPrint(&buf, "{s} Changes", .{icon}) catch "v Changes";
            drawTextClipped(rend, rect.x + 1, rect.y + cy, header, rect.w - 1, colors.fg_secondary, colors.bg_sidebar, true, false);
            rend.highlightHover(.{ .x = rect.x, .y = rect.y + cy, .w = rect.w -| 1, .h = 1 }, colors.bg_sidebar, colors.fg_primary);
            cy += 1;
            if (self.is_changes_open) {
                while (i < self.items.items.len and !self.items.items[i].is_staged and cy < rect.h) : ({
                    i += 1;
                    cy += 1;
                }) {
                    const item = self.items.items[i];
                    defer rend.highlightHover(.{ .x = rect.x, .y = rect.y + cy, .w = rect.w -| 1, .h = 1 }, colors.bg_sidebar, colors.fg_primary);
                    const is_sel = (self.selected_idx != null and self.selected_idx.? == i);
                    const bg = if (is_sel) colors.bg_accent else colors.bg_sidebar;
                    const fg = @import("../theme.zig").readableForeground(colors.fg_primary, bg, 4.5);
                    if (is_sel) {
                        rend.drawRect(Rect{ .x = rect.x, .y = rect.y + cy, .w = rect.w -| 1, .h = 1 }, " ", fg, bg);
                        rend.drawText(rect.x, rect.y + cy, ">", fg, bg, true, false);
                    }

                    drawEllipsized(rend, rect.x + 2, rect.y + cy, item.path, rect.w -| 12, fg, bg);
                    const status_str = std.fmt.bufPrint(&buf, "{s}", .{item.status}) catch "";
                    rend.drawText(rect.x + rect.w -| 9, rect.y + cy, status_str, .{ .rgb = .{ .r = 255, .g = 80, .b = 80 } }, bg, false, false);
                    const action = actionRect(rect, rect.y + cy);
                    rend.drawButtonText(action.x, action.y, action.w, " + ", colors.fg_accent, bg, true, false);
                }
            } else {
                while (i < self.items.items.len and !self.items.items[i].is_staged) : (i += 1) {}
            }
        }

        // Draw Commits (Pipeline)
        if (self.recent_commits.items.len > 0 and cy < rect.h) {
            cy += 1;
            if (cy < rect.h) {
                const icon = if (self.is_commits_open) "v" else ">";
                const header = std.fmt.bufPrint(&buf, "{s} Pipeline", .{icon}) catch "v Pipeline";
                drawTextClipped(rend, rect.x + 1, rect.y + cy, header, rect.w - 1, colors.fg_secondary, colors.bg_sidebar, true, false);
                rend.highlightHover(.{ .x = rect.x, .y = rect.y + cy, .w = rect.w -| 1, .h = 1 }, colors.bg_sidebar, colors.fg_primary);
                cy += 1;
                if (self.is_commits_open) {
                    for (self.recent_commits.items) |c_line| {
                        if (cy >= rect.h) break;
                        drawEllipsized(rend, rect.x + 2, rect.y + cy, c_line, rect.w -| 4, colors.fg_secondary, colors.bg_sidebar);
                        cy += 1;
                    }
                }
            }
        }
    }
};

test "applySnapshot copies independently owned Git model state" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var panel = GitPanel.init(std.testing.allocator, threaded.io());
    defer panel.deinit();
    var snapshot = try GitSnapshot.parse(std.testing.allocator, "feature\n", "abc - subject\n", "M  staged.zig\x00 M changed.zig\x00");
    try panel.applySnapshot(&snapshot);
    snapshot.deinit();
    try std.testing.expectEqualStrings("feature", panel.current_branch.?);
    try std.testing.expectEqualStrings("abc - subject", panel.recent_commits.items[0]);
    try std.testing.expectEqualStrings("staged.zig", panel.items.items[0].path);
    try std.testing.expectEqualStrings("changed.zig", panel.items.items[1].path);
}

test "Git actions leave the sidebar resize gutter clear" {
    for ([_]u16{ 12, 24, 40, 80 }) |width| {
        const sidebar = Rect{ .x = 5, .y = 2, .w = width, .h = 20 };
        const action = GitPanel.actionRect(sidebar, 7);
        try std.testing.expect(action.x + action.w <= sidebar.x + sidebar.w - 3);
        try std.testing.expect(primitives.containsRect(action, action.x + 1, 7));
        try std.testing.expect(!primitives.containsRect(action, sidebar.x + sidebar.w - 2, 7));
    }
}

test "Git titles ellipsize by cell width without splitting wide glyphs" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    var ren = try renderer.Renderer.init(std.testing.allocator, 12, 3, &output.writer);
    defer ren.deinit(std.testing.allocator);
    GitPanel.drawEllipsized(&ren, 0, 0, "A long commit title", 8, .none, .none);
    for ("A lon...", 0..) |c, i| try std.testing.expectEqual(c, ren.buf[i].char[0]);
    GitPanel.drawEllipsized(&ren, 0, 1, "界界界", 5, .none, .none);
    try std.testing.expectEqualStrings("界", ren.buf[12].char[0..ren.buf[12].len]);
    try std.testing.expect(ren.buf[13].continuation);
    for (14..17) |i| try std.testing.expectEqual(@as(u8, '.'), ren.buf[i].char[0]);
    GitPanel.drawEllipsized(&ren, 0, 2, "short", 5, .none, .none);
    for ("short", 0..) |c, i| try std.testing.expectEqual(c, ren.buf[24 + i].char[0]);
}

test "Git keyboard selection reveals collapsed and offscreen changes" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var panel = GitPanel.init(std.testing.allocator, threaded.io());
    defer panel.deinit();
    try std.testing.expect(try panel.handleKey("<Down>", 10));
    try std.testing.expect(panel.selectedPath() == null);
    for (0..15) |i| try panel.items.append(.{ .path = "file", .status = .{ ' ', 'M' }, .is_staged = i < 5 });
    panel.is_staged_open = false;
    panel.is_changes_open = false;
    _ = try panel.handleKey("<Down>", 10);
    try std.testing.expectEqual(@as(?usize, 0), panel.selected_idx);
    _ = try panel.handleKey("j", 10);
    try std.testing.expectEqual(@as(?usize, 1), panel.selected_idx);
    _ = try panel.handleKey("k", 10);
    try std.testing.expectEqual(@as(?usize, 0), panel.selected_idx);
    _ = try panel.handleKey("<End>", 10);
    try std.testing.expectEqual(@as(?usize, 14), panel.selected_idx);
    try std.testing.expect(panel.scroll_y > 0);
    try std.testing.expect(panel.is_staged_open and panel.is_changes_open);
    _ = try panel.handleKey("<Home>", 10);
    try std.testing.expectEqual(@as(usize, 0), panel.scroll_y);
    _ = try panel.handleKey("c", 10);
    _ = try panel.handleKey("draft message", 10);
    _ = try panel.handleKey("<Esc>", 10);
    try std.testing.expect(!panel.is_focus_commit);
    try std.testing.expectEqualStrings("draft message", panel.commit_buf[0..panel.commit_len]);
}

test "Git commit box keeps UTF-8, refuses overflow and shows the tail" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var panel = GitPanel.init(std.testing.allocator, threaded.io());
    defer panel.deinit();
    _ = try panel.handleKey("c", 10);
    _ = try panel.handleKey("café 日本", 10);
    try std.testing.expectEqualStrings("café 日本", panel.commit_buf[0..panel.commit_len]);
    _ = try panel.handleKey("<BS>", 10);
    try std.testing.expectEqualStrings("café 日", panel.commit_buf[0..panel.commit_len]);
    for (0..5000) |_| _ = try panel.handleKey("x", 10);
    try std.testing.expectEqual(panel.commit_buf.len, panel.commit_len);
    _ = try panel.handleKey("日", 10);
    try std.testing.expectEqual(@as(u8, 'x'), panel.commit_buf[panel.commit_len - 1]);
    try std.testing.expectEqual(@as(usize, 3), GitPanel.tailStart("abcdef", 3));
    try std.testing.expectEqual(@as(usize, 5), GitPanel.tailStart("ab日本", 3));
    try std.testing.expectEqual(@as(usize, 0), GitPanel.tailStart("ab", 10));
    // A character split across two reads renders only once it is complete.
    panel.commit_len = 0;
    _ = try panel.handleKey("a\xe6\x97", 10);
    try std.testing.expectEqual(@as(usize, 1), GitPanel.completeLen(panel.commit_buf[0..panel.commit_len]));
    _ = try panel.handleKey("\xa5", 10);
    try std.testing.expectEqualStrings("a日", panel.commit_buf[0..GitPanel.completeLen(panel.commit_buf[0..panel.commit_len])]);
    try std.testing.expectEqual(@as(usize, 1), GitPanel.tailStart("a日", 2));
}
