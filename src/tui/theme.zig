const std = @import("std");
const nvim = @import("../nvim/msgpack.zig");

pub const Color = @import("renderer.zig").Color;

pub const Theme = struct {
    pub fn chrome(self: Theme) Theme {
        var result = self;
        result.bg_sidebar = self.bg_editor;
        result.bg_tab_inactive = blend(self.bg_editor, self.fg_primary, 8);
        result.fg_secondary = readableForeground(blend(self.bg_editor, self.fg_primary, 65), self.bg_editor, 4.5);
        result.border_color = blend(self.bg_editor, self.fg_primary, 30);
        result.fg_accent = self.fg_primary;
        return result;
    }
    bg_editor: Color = Color{ .rgb = .{ .r = 30, .g = 30, .b = 30 } },
    bg_sidebar: Color = Color{ .rgb = .{ .r = 37, .g = 37, .b = 38 } },
    bg_tab_active: Color = Color{ .rgb = .{ .r = 30, .g = 30, .b = 30 } },
    bg_tab_inactive: Color = Color{ .rgb = .{ .r = 45, .g = 45, .b = 45 } },
    bg_statusbar: Color = Color{ .rgb = .{ .r = 0, .g = 122, .b = 204 } },
    fg_statusbar: Color = Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } },
    bg_terminal: Color = Color{ .rgb = .{ .r = 30, .g = 30, .b = 30 } },
    bg_accent: Color = Color{ .rgb = .{ .r = 9, .g = 71, .b = 113 } },
    fg_primary: Color = Color{ .rgb = .{ .r = 212, .g = 212, .b = 212 } },
    fg_secondary: Color = Color{ .rgb = .{ .r = 133, .g = 133, .b = 133 } },
    fg_accent: Color = Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } },
    border_color: Color = Color{ .rgb = .{ .r = 60, .g = 60, .b = 60 } },

    pub fn parseHexColor(hex: []const u8) ?Color {
        if (hex.len != 7 or hex[0] != '#') return null;
        const r = std.fmt.parseInt(u8, hex[1..3], 16) catch return null;
        const g = std.fmt.parseInt(u8, hex[3..5], 16) catch return null;
        const b = std.fmt.parseInt(u8, hex[5..7], 16) catch return null;
        return Color{ .rgb = .{ .r = r, .g = g, .b = b } };
    }

    pub fn updateFromConfig(self: *Theme, map: []nvim.Value.KV) void {
        for (map) |kv| {
            if (kv.key == .string and kv.value == .string) {
                const k = kv.key.string;
                const v = kv.value.string;
                if (parseHexColor(v)) |c| {
                    if (std.mem.eql(u8, k, "bg_editor")) self.bg_editor = c;
                    if (std.mem.eql(u8, k, "bg_sidebar")) self.bg_sidebar = c;
                    if (std.mem.eql(u8, k, "bg_tab_active")) self.bg_tab_active = c;
                    if (std.mem.eql(u8, k, "bg_tab_inactive")) self.bg_tab_inactive = c;
                    if (std.mem.eql(u8, k, "bg_statusbar")) self.bg_statusbar = c;
                    if (std.mem.eql(u8, k, "fg_statusbar")) self.fg_statusbar = c;
                    if (std.mem.eql(u8, k, "bg_terminal")) self.bg_terminal = c;
                    if (std.mem.eql(u8, k, "bg_accent")) self.bg_accent = c;
                    if (std.mem.eql(u8, k, "fg_primary")) self.fg_primary = c;
                    if (std.mem.eql(u8, k, "fg_secondary")) self.fg_secondary = c;
                    if (std.mem.eql(u8, k, "fg_accent")) self.fg_accent = c;
                    if (std.mem.eql(u8, k, "border_color")) self.border_color = c;
                }
            }
        }

        // Theme highlight groups are not guaranteed to be readable against
        // the sidebar used by settings and other native Tuim panels. Keep the
        // supplied palette when it is accessible, otherwise move foregrounds
        // toward the higher-contrast endpoint.
        self.fg_primary = readableForeground(self.fg_primary, self.bg_sidebar, 7.0);
        self.fg_secondary = readableForeground(self.fg_secondary, self.bg_sidebar, 4.5);
        self.fg_accent = readableForeground(self.fg_accent, self.bg_sidebar, 4.5);
        self.border_color = readableForeground(self.border_color, self.bg_sidebar, 3.0);
        self.fg_statusbar = readableForeground(self.fg_statusbar, self.bg_statusbar, 4.5);
    }
};

fn blend(background: Color, foreground: Color, percent: u16) Color {
    if (background != .rgb or foreground != .rgb) return foreground;
    const bg = background.rgb;
    const fg = foreground.rgb;
    return .{ .rgb = .{
        .r = @intCast((@as(u16, bg.r) * (100 - percent) + @as(u16, fg.r) * percent) / 100),
        .g = @intCast((@as(u16, bg.g) * (100 - percent) + @as(u16, fg.g) * percent) / 100),
        .b = @intCast((@as(u16, bg.b) * (100 - percent) + @as(u16, fg.b) * percent) / 100),
    } };
}

fn linearChannel(value: u8) f32 {
    const channel = @as(f32, @floatFromInt(value)) / 255.0;
    return if (channel <= 0.04045) channel / 12.92 else std.math.pow(f32, (channel + 0.055) / 1.055, 2.4);
}

fn luminance(color: Color) f32 {
    return switch (color) {
        .rgb => |rgb| 0.2126 * linearChannel(rgb.r) + 0.7152 * linearChannel(rgb.g) + 0.0722 * linearChannel(rgb.b),
        else => 0,
    };
}

fn contrastRatio(a: Color, b: Color) f32 {
    const a_lum = luminance(a);
    const b_lum = luminance(b);
    const lighter = @max(a_lum, b_lum);
    const darker = @min(a_lum, b_lum);
    return (lighter + 0.05) / (darker + 0.05);
}

pub fn readableForeground(foreground: Color, background: Color, minimum_ratio: f32) Color {
    if (contrastRatio(foreground, background) >= minimum_ratio) return foreground;
    const fg = switch (foreground) {
        .rgb => |rgb| rgb,
        else => return foreground,
    };
    const black = Color{ .rgb = .{ .r = 0, .g = 0, .b = 0 } };
    const white = Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } };
    const endpoint: u8 = if (contrastRatio(white, background) >= contrastRatio(black, background)) 255 else 0;

    var step: u16 = 1;
    while (step <= 20) : (step += 1) {
        const amount = step * 5;
        const candidate = Color{ .rgb = .{
            .r = @intCast((@as(u16, fg.r) * (100 - amount) + @as(u16, endpoint) * amount) / 100),
            .g = @intCast((@as(u16, fg.g) * (100 - amount) + @as(u16, endpoint) * amount) / 100),
            .b = @intCast((@as(u16, fg.b) * (100 - amount) + @as(u16, endpoint) * amount) / 100),
        } };
        if (contrastRatio(candidate, background) >= minimum_ratio) return candidate;
    }
    return Color{ .rgb = .{ .r = endpoint, .g = endpoint, .b = endpoint } };
}

test "default theme keeps text and focus contrast readable" {
    const t = Theme{};
    try std.testing.expect(contrastRatio(t.fg_primary, t.bg_editor) >= 7.0);
    try std.testing.expect(contrastRatio(t.fg_secondary, t.bg_sidebar) >= 4.0);
    try std.testing.expect(contrastRatio(t.fg_statusbar, t.bg_statusbar) >= 4.0);
    try std.testing.expect(contrastRatio(t.fg_accent, t.bg_accent) >= 7.0);
}

test "theme update repairs low-contrast settings colors" {
    var t = Theme{};
    var entries = [_]nvim.Value.KV{
        .{ .key = .{ .string = "bg_sidebar" }, .value = .{ .string = "#080808" } },
        .{ .key = .{ .string = "fg_primary" }, .value = .{ .string = "#303030" } },
        .{ .key = .{ .string = "fg_secondary" }, .value = .{ .string = "#4a4a4a" } },
        .{ .key = .{ .string = "border_color" }, .value = .{ .string = "#202020" } },
    };
    t.updateFromConfig(&entries);

    try std.testing.expect(contrastRatio(t.fg_primary, t.bg_sidebar) >= 7.0);
    try std.testing.expect(contrastRatio(t.fg_secondary, t.bg_sidebar) >= 4.5);
    try std.testing.expect(contrastRatio(t.border_color, t.bg_sidebar) >= 3.0);
}

test "notification backgrounds receive readable text" {
    const low_contrast = Color{ .rgb = .{ .r = 150, .g = 120, .b = 70 } };
    const backgrounds = [_]Color{
        .{ .rgb = .{ .r = 0, .g = 122, .b = 204 } },
        .{ .rgb = .{ .r = 145, .g = 105, .b = 20 } },
        .{ .rgb = .{ .r = 140, .g = 45, .b = 50 } },
    };
    for (backgrounds) |background| {
        const text_color = readableForeground(low_contrast, background, 7.0);
        try std.testing.expect(contrastRatio(text_color, background) >= 4.5);
    }
}
