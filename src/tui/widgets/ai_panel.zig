const std = @import("std");
const input = @import("../input.zig");
const renderer = @import("../renderer.zig");
const Rect = @import("../layout.zig").Rect;

const Agent = struct {
    label: []const u8,
    command: []const u8,
    icon: []const u8,
    fallback_icon: []const u8,
    launch: []const u8,
    missing: []const u8,
};

const agents = [_]Agent{
    .{ .label = "Antigravity", .command = "agy", .icon = " ", .fallback_icon = "A ", .launch = "__CMD__:lua _G.OpenAITerminal('agy')", .missing = "__CMD__:lua _G.NotifyAIMissing('agy')" },
    .{ .label = "Claude Code", .command = "claude", .icon = "󰚩 ", .fallback_icon = "C ", .launch = "__CMD__:lua _G.OpenAITerminal('claude')", .missing = "__CMD__:lua _G.NotifyAIMissing('claude')" },
    .{ .label = "Codex", .command = "codex", .icon = "󰧑 ", .fallback_icon = "X ", .launch = "__CMD__:lua _G.OpenAITerminal('codex')", .missing = "__CMD__:lua _G.NotifyAIMissing('codex')" },
    .{ .label = "Gemini", .command = "gemini", .icon = "󰢚 ", .fallback_icon = "G ", .launch = "__CMD__:lua _G.OpenAITerminal('gemini')", .missing = "__CMD__:lua _G.NotifyAIMissing('gemini')" },
    .{ .label = "OpenCode", .command = "opencode", .icon = "󰊤 ", .fallback_icon = "O ", .launch = "__CMD__:lua _G.OpenAITerminal('opencode')", .missing = "__CMD__:lua _G.NotifyAIMissing('opencode')" },
    .{ .label = "Copilot", .command = "copilot", .icon = " ", .fallback_icon = "P ", .launch = "__CMD__:lua _G.OpenAITerminal('copilot')", .missing = "__CMD__:lua _G.NotifyAIMissing('copilot')" },
};

pub const AiPanel = struct {
    available: [agents.len]bool = @splat(false),
    active_agent: ?usize = null,
    chosen: usize = 2,
    session_state: SessionState = .idle,
    sessions: [agents.len]SessionState = @splat(.idle),
    choosing: bool = false,
    selected: usize = 1,
    scroll: usize = 0,
    pub const SessionState = enum { idle, running, stopped };

    pub fn init(allocator: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map) AiPanel {
        var self = AiPanel{};
        for (agents, 0..) |agent, idx| {
            var dirs = std.mem.splitScalar(u8, environ.get("PATH") orelse "", ':');
            while (dirs.next()) |dir| {
                const path = std.fs.path.join(allocator, &.{ if (dir.len == 0) "." else dir, agent.command }) catch continue;
                defer allocator.free(path);
                std.Io.Dir.cwd().access(io, path, .{ .execute = true }) catch continue;
                self.available[idx] = true;
                break;
            }
        }
        for ([_]usize{ 2, 1, 3, 4, 0, 5 }) |idx| {
            if (self.available[idx]) {
                self.chosen = idx;
                break;
            }
        }
        return self;
    }
    pub fn deinit(_: *AiPanel) void {}
    pub fn updateSession(self: *AiPanel, command: []const u8, state: []const u8, active: bool) void {
        const status: SessionState = if (std.mem.eql(u8, state, "running")) .running else if (std.mem.eql(u8, state, "stopped")) .stopped else .idle;
        for (agents, 0..) |agent, idx| {
            if (std.mem.eql(u8, agent.command, command)) {
                self.sessions[idx] = status;
                if (active) {
                    self.active_agent = idx;
                    self.session_state = status;
                }
                break;
            }
        }
    }
    fn itemCount(self: *const AiPanel) usize {
        return if (self.choosing) agents.len + 1 else if (self.active_agent == self.chosen and self.sessions[self.chosen] == .running) 7 else 2;
    }
    fn activate(self: *AiPanel) ?[]const u8 {
        self.selected = @min(self.selected, self.itemCount() - 1);
        if (self.choosing) {
            if (self.selected < agents.len) self.chosen = self.selected;
            self.choosing = false;
            self.selected = 1;
            self.scroll = 0;
            return null;
        }
        switch (self.selected) {
            0 => {
                self.choosing = true;
                self.selected = self.chosen;
                self.scroll = 0;
                return null;
            },
            1 => {
                if (self.available[self.chosen]) return agents[self.chosen].launch;
                self.choosing = true;
                self.selected = self.chosen;
                self.scroll = 0;
                return null;
            },
            2 => return "__CMD__:lua _G.SendSelectionToAI()",
            3 => return "__CMD__:lua _G.SendFileContentToAI()",
            4 => return "__CMD__:lua _G.RunAIAction('review_changes')",
            5 => return "__CMD__:lua _G.RestartAITerminal()",
            6 => return "__CMD__:lua _G.StopAITerminal()",
            else => return null,
        }
    }
    pub fn handleKey(self: *AiPanel, key: []const u8) ?[]const u8 {
        self.selected = @min(self.selected, self.itemCount() - 1);
        if (std.mem.eql(u8, key, "<Esc>")) {
            self.choosing = false;
            self.selected = 0;
            self.scroll = 0;
        } else if (std.mem.eql(u8, key, "<Home>")) {
            self.selected = 0;
        } else if (std.mem.eql(u8, key, "<End>")) {
            self.selected = self.itemCount() - 1;
        } else if (std.mem.eql(u8, key, "j") or std.mem.eql(u8, key, "<Down>") or std.mem.eql(u8, key, "<Tab>")) {
            self.selected = @min(self.selected + 1, self.itemCount() - 1);
        } else if (std.mem.eql(u8, key, "k") or std.mem.eql(u8, key, "<Up>") or std.mem.eql(u8, key, "<S-Tab>")) {
            self.selected -|= 1;
        } else if (std.mem.eql(u8, key, "<Enter>") or std.mem.eql(u8, key, "<Space>") or std.mem.eql(u8, key, "o")) {
            return self.activate();
        }
        return null;
    }
    fn rowHeight(self: *const AiPanel, rect: Rect) usize {
        return if (rect.h >= self.itemCount() * 2 + 6) 2 else 1;
    }
    fn visibleRows(self: *const AiPanel, rect: Rect) usize {
        const footer: usize = if (rect.h >= 8) 3 else 0;
        return @max(1, (rect.h - 3 - footer) / self.rowHeight(rect));
    }
    fn description(self: *const AiPanel, idx: usize) []const u8 {
        if (self.choosing) {
            if (idx == agents.len) return "Keep current assistant";
            if (!self.available[idx]) return "Not installed";
            return switch (self.sessions[idx]) {
                .idle => "Installed - ready",
                .running => "Chat running",
                .stopped => "Chat stopped",
            };
        }
        return switch (idx) {
            0 => "Change assistant",
            1 => if (!self.available[self.chosen]) "Find installed CLI" else switch (self.sessions[self.chosen]) {
                .idle => "Type in the chat",
                .running => "Resume typing",
                .stopped => "Start fresh",
            },
            2 => "Paste selected code",
            3 => "Paste file contents",
            4 => "Review git changes",
            5 => "Restart session",
            6 => "End this session",
            else => "",
        };
    }
    pub fn handleMouse(self: *AiPanel, m: input.MouseEvent, rect: Rect) ?[]const u8 {
        if (rect.w < 12 or rect.h < 5 or m.col < rect.x or m.col >= rect.x + rect.w - 1 or m.row < rect.y or m.row >= rect.y + rect.h) return null;
        if (m.button == .wheel_up) return self.handleKey("<Up>");
        if (m.button == .wheel_down) return self.handleKey("<Down>");
        if (m.button != .left or m.action != .press or m.row < rect.y + 3) return null;
        const row = (m.row - rect.y - 3) / self.rowHeight(rect);
        if (row >= self.visibleRows(rect)) return null;
        const idx = self.scroll + row;
        if (idx >= self.itemCount()) return null;
        self.selected = idx;
        return self.activate();
    }
    pub fn draw(self: *AiPanel, ren: *renderer.Renderer, rect: Rect, colors: anytype) void {
        ren.drawRect(rect, " ", colors.fg_primary, colors.bg_sidebar);
        if (rect.w < 12 or rect.h < 5) return;
        ren.drawTextClipped(rect.x + 2, rect.y, rect.w - 4, if (self.choosing) "CHOOSE AGENT" else "AI CHAT", colors.fg_primary, colors.bg_sidebar, true, false);
        const status = if (!self.available[self.chosen]) "CLI not installed" else switch (self.sessions[self.chosen]) {
            .idle => "Ready to start",
            .running => "Chat open",
            .stopped => "Chat stopped",
        };
        ren.drawTextClipped(rect.x + 2, rect.y + 1, rect.w - 4, if (self.choosing) "Choose an assistant" else status, colors.fg_secondary, colors.bg_sidebar, false, false);
        self.selected = @min(self.selected, self.itemCount() - 1);
        const rows = self.visibleRows(rect);
        const stride = self.rowHeight(rect);
        if (self.selected < self.scroll) self.scroll = self.selected;
        if (self.selected >= self.scroll + rows) self.scroll = self.selected - rows + 1;
        self.scroll = @min(self.scroll, self.itemCount() -| rows);
        const labels = [_][]const u8{ "", "Open chat", "Send selection", "Send file", "Review changes", "Restart chat", "Stop chat" };
        for (0..@min(rows, self.itemCount() - self.scroll)) |row| {
            const idx = row + self.scroll;
            const y = rect.y + 3 + @as(u16, @intCast(row * stride));
            const selected = self.selected == idx;
            const primary = !self.choosing and idx == 1;
            const bg = if (selected) colors.bg_accent else colors.bg_sidebar;
            const fg = @import("../theme.zig").readableForeground(colors.fg_primary, bg, 4.5);
            const item_rect = Rect{ .x = rect.x + 1, .y = y, .w = rect.w - 2, .h = @intCast(stride) };
            ren.drawRect(item_rect, " ", fg, bg);
            var buf: [64]u8 = undefined;
            const label = if (self.choosing)
                (if (idx < agents.len) agents[idx].label else "Cancel")
            else if (idx == 0)
                (std.fmt.bufPrint(&buf, "{s} v", .{agents[self.chosen].label}) catch "")
            else if (idx == 1)
                (if (!self.available[self.chosen]) "Choose assistant" else switch (self.sessions[self.chosen]) {
                    .idle => "Open chat",
                    .running => "Return to chat",
                    .stopped => "Restart chat",
                })
            else
                labels[idx];
            ren.drawTextClipped(rect.x + 3, y, rect.w - 5, label, fg, bg, primary or selected, false);
            if (selected) ren.drawText(rect.x + 1, y, ">", fg, bg, true, false);
            if (stride == 2) {
                const secondary = @import("../theme.zig").readableForeground(colors.fg_secondary, bg, 4.5);
                ren.drawTextClipped(rect.x + 3, y + 1, rect.w - 5, self.description(idx), secondary, bg, false, false);
            }
            ren.highlightHover(item_rect, bg, fg);
        }
        // Keep a next step visible even before a session exists.
        const after_items = 3 + self.itemCount() * stride;
        if (!self.choosing and self.itemCount() == 2 and rect.h >= after_items + 7) {
            const y = rect.y + @as(u16, @intCast(after_items + 1));
            const guidance = if (!self.available[self.chosen])
                [_][]const u8{ "Install a CLI first", "then restart Tuim", "to detect it." }
            else
                [_][]const u8{ if (self.sessions[self.chosen] == .stopped) "1. Restart & type" else "1. Open chat & type", "2. Add file or code", "   with Send actions" };
            for (guidance, 0..) |line, offset| ren.drawTextClipped(rect.x + 2, y + @as(u16, @intCast(offset)), rect.w - 4, line, colors.fg_secondary, colors.bg_sidebar, false, false);
        }
        if (rect.h >= 8) {
            const y = rect.y + rect.h - 3;
            ren.drawTextClipped(rect.x + 2, y, rect.w - 4, self.description(self.selected), colors.fg_primary, colors.bg_sidebar, false, false);
            ren.drawTextClipped(rect.x + 2, y + 1, rect.w - 4, "Up/Down Tab: select", colors.fg_secondary, colors.bg_sidebar, false, false);
            ren.drawTextClipped(rect.x + 2, y + 2, rect.w - 4, if (self.choosing) "Enter pick  Esc back" else "Enter run  Esc back", colors.fg_secondary, colors.bg_sidebar, false, false);
        }
        for (0..rect.h) |row| ren.drawTextClipped(rect.x + rect.w - 1, rect.y + @as(u16, @intCast(row)), 1, "│", colors.border_color, colors.bg_sidebar, false, false);
    }
};

test "AI chooser selects without starting and scopes actions to the open chat" {
    var panel = AiPanel{};
    panel.available[2] = true;
    try std.testing.expectEqualStrings(agents[2].launch, panel.handleKey("<Enter>").?);
    panel.updateSession("codex", "running", true);
    try std.testing.expectEqual(@as(usize, 7), panel.itemCount());
    _ = panel.handleKey("<Up>");
    try std.testing.expect(panel.handleKey("<Enter>") == null);
    _ = panel.handleKey("<Up>");
    try std.testing.expect(panel.handleKey("<Enter>") == null);
    try std.testing.expectEqual(@as(usize, 1), panel.chosen);
    try std.testing.expectEqual(@as(usize, 2), panel.itemCount());
    panel.updateSession("codex", "stopped", false);
    try std.testing.expectEqual(@as(usize, 1), panel.chosen);
}

test "AI chooser cancels without changing assistant and missing CLI offers recovery" {
    var panel = AiPanel{};
    try std.testing.expect(panel.handleKey("<Enter>") == null);
    try std.testing.expect(panel.choosing);
    _ = panel.handleKey("<Up>");
    _ = panel.handleKey("<Esc>");
    try std.testing.expect(!panel.choosing);
    try std.testing.expectEqual(@as(usize, 2), panel.chosen);
    try std.testing.expectEqual(@as(usize, 0), panel.selected);
}

test "AI stopped sessions cannot dispatch stale context or stop actions" {
    var panel = AiPanel{};
    panel.available[2] = true;
    panel.updateSession("codex", "running", true);
    _ = panel.handleKey("<End>");
    panel.updateSession("codex", "stopped", true);
    try std.testing.expectEqual(@as(usize, 2), panel.itemCount());
    try std.testing.expectEqualStrings(agents[2].launch, panel.handleKey("<Enter>").?);
}

test "AI mouse description rows activate their item and footer is inert" {
    var panel = AiPanel{};
    panel.available[2] = true;
    const rect = Rect{ .x = 2, .y = 1, .w = 28, .h = 24 };
    try std.testing.expectEqualStrings(agents[2].launch, panel.handleMouse(.{ .button = .left, .action = .press, .col = 6, .row = 7 }, rect).?);
    try std.testing.expect(panel.handleMouse(.{ .button = .left, .action = .press, .col = 6, .row = 23 }, rect) == null);
}
