const std = @import("std");
const posix = std.posix;

pub var sigwinch_received = std.atomic.Value(bool).init(false);
pub var sigwinch_pipe_write_fd: ?posix.fd_t = null;

pub fn handleSigwinch(sig: posix.SIG) callconv(.c) void {
    _ = sig;
    sigwinch_received.store(true, .monotonic);
    if (sigwinch_pipe_write_fd) |fd| {
        _ = posix.system.write(fd, "W", 1);
    }
}

pub const MouseButton = enum {
    left,
    middle,
    right,
    wheel_up,
    wheel_down,
    none,
};

pub const MouseAction = enum {
    press,
    release,
    move,
};

pub const MouseEvent = struct {
    col: u16,
    row: u16,
    button: MouseButton,
    action: MouseAction,
};

pub const KeyEvent = struct {
    char: u8,
    ctrl: bool = false,
    alt: bool = false,
    raw: []const u8,
};

pub const Event = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,
    paste: []const u8,
    resize: struct { cols: u16, rows: u16 },
    none,
    quit,
};

pub var unget_byte: ?u8 = null;

pub fn hasPendingEvent() bool {
    return unget_byte != null;
}

fn tryReadByte(fd: posix.fd_t) !?u8 {
    if (unget_byte) |b| {
        unget_byte = null;
        return b;
    }
    var buf: [1]u8 = undefined;
    var fds = [1]posix.pollfd{.{ .fd = fd, .events = posix.POLL.IN, .revents = 0 }};
    if ((posix.poll(&fds, 0) catch 0) > 0 and (fds[0].revents & posix.POLL.IN) != 0) {
        if ((posix.read(fd, &buf) catch 0) == 1) return buf[0];
    }
    return null;
}

fn readByteTimeout(fd: posix.fd_t, timeout: i32) !?u8 {
    var buf: [1]u8 = undefined;
    var fds = [1]posix.pollfd{.{
        .fd = fd,
        .events = posix.POLL.IN,
        .revents = 0,
    }};

    const rc = posix.poll(&fds, timeout) catch |err| switch (err) {
        error.SystemResources, error.Unexpected => return err,
        else => return null,
    };

    if (rc > 0 and (fds[0].revents & posix.POLL.IN) != 0) {
        const read_bytes = try posix.read(fd, &buf);
        if (read_bytes > 0) return buf[0];
    }
    return null;
}

fn parseSgrMouse(seq: []const u8) ?MouseEvent {
    if (!std.mem.startsWith(u8, seq, "\x1b[<")) return null;

    const last_char = seq[seq.len - 1];
    if (last_char != 'M' and last_char != 'm') return null;

    const params_str = seq[3 .. seq.len - 1];
    var iter = std.mem.splitScalar(u8, params_str, ';');

    const b_str = iter.next() orelse return null;
    const c_str = iter.next() orelse return null;
    const r_str = iter.next() orelse return null;

    const b = std.fmt.parseInt(u8, b_str, 10) catch return null;
    const col = std.fmt.parseInt(u16, c_str, 10) catch return null;
    const row = std.fmt.parseInt(u16, r_str, 10) catch return null;

    // std.debug.print("\r\n[SGR] b={d} col={d} row={d} last={c}\r\n", .{b, col, row, last_char});

    const action: MouseAction = if (last_char == 'M')
        (if ((b & 32) != 0) .move else .press)
    else
        .release;

    const button: MouseButton = if ((b & 64) != 0) (if ((b & 3) == 0) .wheel_up else .wheel_down) else switch (b & 3) {
        0 => .left,
        1 => .middle,
        2 => .right,
        3 => .none,
        else => .none,
    };

    return MouseEvent{
        .col = if (col > 0) col - 1 else 0,
        .row = if (row > 0) row - 1 else 0,
        .button = button,
        .action = action,
    };
}

test "SGR mouse press uses zero-based coordinates" {
    const event = parseSgrMouse("\x1b[<0;12;7M") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(MouseButton.left, event.button);
    try std.testing.expectEqual(MouseAction.press, event.action);
    try std.testing.expectEqual(@as(u16, 11), event.col);
    try std.testing.expectEqual(@as(u16, 6), event.row);
}

test "SGR mouse handles wheel and release events" {
    const wheel = parseSgrMouse("\x1b[<65;1;1M") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(MouseButton.wheel_down, wheel.button);
    const released = parseSgrMouse("\x1b[<0;2;3m") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(MouseAction.release, released.action);
}

test "SGR mouse rejects malformed and overflowing input" {
    try std.testing.expect(parseSgrMouse("\x1b[<0;12M") == null);
    try std.testing.expect(parseSgrMouse("\x1b[<0;999999;1M") == null);
    try std.testing.expect(parseSgrMouse("not-mouse") == null);
}

pub fn readEvent(fd: posix.fd_t, seq_buf: []u8, allocator: std.mem.Allocator) !Event {
    // First, check if a resize signal was caught
    if (sigwinch_received.swap(false, .monotonic)) {
        var ws: posix.winsize = undefined;
        const rc = posix.system.ioctl(fd, posix.T.IOCGWINSZ, @intFromPtr(&ws));
        if (posix.errno(rc) == .SUCCESS) {
            return Event{ .resize = .{ .cols = ws.col, .rows = ws.row } };
        }
    }

    var first_byte: u8 = undefined;
    if (unget_byte) |b| {
        first_byte = b;
        unget_byte = null;
    } else {
        var first_buf: [1]u8 = undefined;
        const read_bytes = posix.read(fd, &first_buf) catch |err| {
            if (err == error.BlockedBySignal) {
                // Signal received (like SIGWINCH), re-check flag
                if (sigwinch_received.swap(false, .monotonic)) {
                    var ws: posix.winsize = undefined;
                    const rc = posix.system.ioctl(fd, posix.T.IOCGWINSZ, @intFromPtr(&ws));
                    if (posix.errno(rc) == .SUCCESS) {
                        return Event{ .resize = .{ .cols = ws.col, .rows = ws.row } };
                    }
                }
                return Event.none;
            }
            return err;
        };
        if (read_bytes == 0) return Event.none;
        first_byte = first_buf[0];
    }
    seq_buf[0] = first_byte;

    if (first_byte == 0x1b) { // Escape sequence indicator
        // Read remaining bytes
        seq_buf[0] = 0x1b;
        var len: usize = 1;
        while (len < seq_buf.len) {
            if (try readByteTimeout(fd, 20)) |b| {
                seq_buf[len] = b;
                len += 1;
                if (len == 2) {
                    if (b != '[' and b != 'O') break;
                } else if (len >= 3) {
                    if (seq_buf[1] == '[' and seq_buf[2] == '<') {
                        if (b == 'M' or b == 'm') break;
                    } else {
                        if (b >= 64 and b <= 126) break;
                    }
                }
            } else {
                break;
            }
        }

        if (len == 1) { // Just Escape key
            return Event{ .key = .{ .char = 0x1b, .raw = seq_buf[0..1] } };
        }

        const seq = seq_buf[0..len];
        if (std.mem.startsWith(u8, seq, "\x1b[<")) {
            if (parseSgrMouse(seq)) |me| {
                return Event{ .mouse = me };
            }
        }

        if (std.mem.eql(u8, seq, "\x1b[200~")) {
            var paste_buf = std.array_list.Managed(u8).init(allocator);
            errdefer paste_buf.deinit();
            var end_seq_idx: usize = 0;
            const end_seq = "\x1b[201~";
            const MAX_PASTE_SIZE = 2 * 1024 * 1024; // 2MB
            while (true) {
                if (try readByteTimeout(fd, 200)) |b| {
                    if (paste_buf.items.len < MAX_PASTE_SIZE) {
                        try paste_buf.append(b);
                    }
                    if (b == end_seq[end_seq_idx]) {
                        end_seq_idx += 1;
                        if (end_seq_idx == end_seq.len) {
                            if (paste_buf.items.len >= end_seq.len) {
                                paste_buf.shrinkRetainingCapacity(paste_buf.items.len - end_seq.len);
                            }
                            return Event{ .paste = try paste_buf.toOwnedSlice() };
                        }
                    } else {
                        if (b == end_seq[0]) {
                            end_seq_idx = 1;
                        } else {
                            end_seq_idx = 0;
                        }
                    }
                } else {
                    break;
                }
            }
            return Event{ .paste = try paste_buf.toOwnedSlice() };
        }

        // Generic arrow key or function key
        return Event{ .key = .{ .char = 0, .raw = seq } };
    }

    // Ctrl keys mapping (except Ctrl-C which is .quit)
    if (first_byte < 32 and first_byte != 0x1b) {
        return Event{ .key = .{ .char = first_byte, .ctrl = true, .raw = seq_buf[0..1] } };
    }

    // Normal printable key (or unparsed char)
    seq_buf[0] = first_byte;
    var len: usize = 1;

    // Batch more characters if available!
    while (len < seq_buf.len) {
        if (tryReadByte(fd) catch null) |b| {
            if (b == 0x1b or b < 32 or b == 0x7f) {
                // It's a special character, put it back for the next event!
                unget_byte = b;
                break;
            }
            seq_buf[len] = b;
            len += 1;
        } else {
            break;
        }
    }

    return Event{ .key = .{ .char = first_byte, .raw = seq_buf[0..len] } };
}

test "buffered control byte remains dispatchable without fd readiness" {
    unget_byte = '\r';
    defer unget_byte = null;
    try std.testing.expect(hasPendingEvent());
    var sequence: [16]u8 = undefined;
    const event = try readEvent(-1, &sequence, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, '\r'), event.key.char);
    try std.testing.expectEqualStrings("\r", event.key.raw);
    try std.testing.expect(!hasPendingEvent());
}

test "passive SGR motion is distinct from a left button drag" {
    const hover = parseSgrMouse("\x1b[<35;3;2M").?;
    try std.testing.expectEqual(MouseAction.move, hover.action);
    try std.testing.expectEqual(MouseButton.none, hover.button);
    const drag = parseSgrMouse("\x1b[<32;3;2M").?;
    try std.testing.expectEqual(MouseAction.move, drag.action);
    try std.testing.expectEqual(MouseButton.left, drag.button);
}
