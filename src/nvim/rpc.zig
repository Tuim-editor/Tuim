const std = @import("std");
const posix = std.posix;
const NvimProcess = @import("process.zig").NvimProcess;
const msgpack = @import("msgpack.zig");
const Value = msgpack.Value;
const metrics = @import("../metrics.zig");
const incremental = @import("incremental_decoder.zig");
const async_transport = @import("async_transport.zig");

pub const compatibility = struct {
    /// Compatibility switches for startup decoding and interactive transport.
    pub const incremental_decoder = false;
    pub const async_transport_enabled = true;
};

pub const RpcClient = struct {
    pub const default_request_timeout_ns = 30 * std.time.ns_per_s;
    pub const AsyncHandler = *const fn (?*anyopaque, *async_transport.Completion) anyerror!void;
    const HandlerEntry = struct { id: async_transport.RequestId, context: ?*anyopaque, callback: AsyncHandler };
    process: NvimProcess,
    msg_id: u32 = 0,
    allocator: std.mem.Allocator,
    io: std.Io,
    on_notification: ?*const fn (ctx: ?*anyopaque, method: []const u8, params: Value) anyerror!void = null,
    on_notification_ctx: ?*anyopaque = null,
    reader: FdReader,
    incremental_reader: incremental.Decoder,
    transport: async_transport.Transport,
    async_enabled: bool = false,
    async_read_pending: bool = false,
    handlers: [async_transport.max_pending_requests]?HandlerEntry = [_]?HandlerEntry{null} ** async_transport.max_pending_requests,
    handler_len: usize = 0,
    completions_dispatched: bool = false,

    pub fn init(process: NvimProcess, allocator: std.mem.Allocator, io: std.Io) RpcClient {
        return .{
            .process = process,
            .allocator = allocator,
            .io = io,
            .reader = FdReader.init(process.stdout.handle, allocator),
            .incremental_reader = incremental.Decoder.init(allocator),
            .transport = async_transport.Transport.init(allocator),
        };
    }

    pub fn deinit(self: *RpcClient) void {
        self.reader.deinit();
        self.incremental_reader.deinit();
        self.transport.deinit();
    }

    pub fn nextId(self: *RpcClient) u32 {
        self.msg_id += 1;
        return self.msg_id;
    }

    fn send(self: *RpcClient, val: Value) !void {
        var buf = std.Io.Writer.Allocating.init(self.allocator);
        defer buf.deinit();
        try msgpack.encode(&buf.writer, val);
        const data = buf.written();
        var total_written: usize = 0;
        while (total_written < data.len) {
            var fds = [2]posix.pollfd{
                .{ .fd = self.process.stdin.handle, .events = posix.POLL.OUT, .revents = 0 },
                .{ .fd = self.process.stdout.handle, .events = posix.POLL.IN, .revents = 0 },
            };
            const rc_poll = posix.poll(&fds, -1) catch 0;
            if (rc_poll > 0) {
                // Drain exactly one complete inbound frame to prevent a full
                // stdout pipe from deadlocking Neovim while we write. Do not
                // drain-until-empty here: callbacks may enqueue more traffic.
                if ((fds[1].revents & (posix.POLL.IN | posix.POLL.ERR | posix.POLL.HUP)) != 0) {
                    if (!try self.processOneMessage()) return error.Closed;
                }
                if ((fds[0].revents & posix.POLL.OUT) != 0) {
                    const rc = posix.system.write(self.process.stdin.handle, data[total_written..].ptr, data.len - total_written);
                    const err = posix.errno(rc);
                    switch (err) {
                        .SUCCESS => {
                            if (rc > 0) total_written += @as(usize, @intCast(rc)) else return error.Closed;
                        },
                        .INTR => continue,
                        .AGAIN => continue,
                        else => return error.WriteFailed,
                    }
                }
            }
        }
    }

    pub fn call(self: *RpcClient, method: []const u8, params: []const Value) !Value {
        if (self.async_enabled) {
            _ = try self.requestAsync(method, params);
            return .nil;
        }
        var timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.blocking_rpc);
        defer timer.stop();
        const id = self.nextId();
        var req_arr = try self.allocator.alloc(Value, 4);
        defer self.allocator.free(req_arr);
        req_arr[0] = .{ .integer = 0 };
        req_arr[1] = .{ .integer = id };
        req_arr[2] = .{ .string = method };
        const params_dup = try self.allocator.alloc(Value, params.len);
        @memcpy(params_dup, params);
        defer self.allocator.free(params_dup);
        req_arr[3] = .{ .array = params_dup };
        try self.send(.{ .array = req_arr });
        return try self.waitResponse(id);
    }

    pub fn notify(self: *RpcClient, method: []const u8, params: []const Value) !void {
        if (self.async_enabled) return self.transport.queueNotification(method, params);
        var req_arr = try self.allocator.alloc(Value, 3);
        defer self.allocator.free(req_arr);
        req_arr[0] = .{ .integer = 2 };
        req_arr[1] = .{ .string = method };
        const params_dup = try self.allocator.alloc(Value, params.len);
        @memcpy(params_dup, params);
        defer self.allocator.free(params_dup);
        req_arr[2] = .{ .array = params_dup };
        try self.send(.{ .array = req_arr });
    }

    /// Send an error response to a request message received from nvim.
    /// Without this, nvim blocks forever waiting for the response (deadlock).
    /// Uses a direct write (not send()) to avoid recursive processNotifications() calls.
    fn replyError(self: *RpcClient, req_id: i64) void {
        var resp_arr = self.allocator.alloc(Value, 4) catch return;
        resp_arr[0] = .{ .integer = 1 };
        resp_arr[1] = .{ .integer = req_id };
        resp_arr[2] = .{ .string = "method not found" };
        resp_arr[3] = .nil;
        defer self.allocator.free(resp_arr);

        var buf = std.Io.Writer.Allocating.init(self.allocator);
        defer buf.deinit();
        msgpack.encode(&buf.writer, Value{ .array = resp_arr }) catch return;
        const data = buf.written();

        // Direct write without calling processNotifications() recursively.
        var written: usize = 0;
        while (written < data.len) {
            var fds = [1]posix.pollfd{.{ .fd = self.process.stdin.handle, .events = posix.POLL.OUT, .revents = 0 }};
            const rc_poll = posix.poll(&fds, 200) catch break;
            if (rc_poll == 0) break; // timeout, give up
            const rc = posix.system.write(self.process.stdin.handle, data[written..].ptr, data.len - written);
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    if (rc > 0) written += @as(usize, @intCast(rc)) else break;
                },
                .INTR => continue,
                .AGAIN => continue,
                else => break,
            }
        }
    }

    fn waitResponse(self: *RpcClient, id: u32) !Value {
        if (compatibility.incremental_decoder) return self.waitResponseIncremental(id);
        var retries: usize = 0;
        const max_retries = 100;
        while (true) {
            // Read with retry on WouldBlock (non-blocking stdout fd)
            const checkpoint = self.reader.head;
            var decode_timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.rpc_decode);
            const msg = msgpack.decode(&self.reader, self.allocator) catch |err| {
                decode_timer.stop();
                self.reader.head = checkpoint;
                if (err == error.WouldBlock) {
                    if (retries >= max_retries) {
                        return error.Timeout;
                    }
                    retries += 1;
                    // No complete message yet: wait a bit and retry
                    var fds = [1]posix.pollfd{.{ .fd = self.process.stdout.handle, .events = posix.POLL.IN, .revents = 0 }};
                    _ = posix.poll(&fds, 100) catch {};
                    continue;
                }
                return err;
            };
            decode_timer.stop();
            self.reader.discardConsumed();
            retries = 0;
            errdefer msgpack.freeValue(msg, self.allocator);
            if (msg != .array or msg.array.len < 3) {
                return error.InvalidRpcMessage;
            }
            const msg_type = msg.array[0].integer;
            if (msg_type == 0 and msg.array.len >= 4) {
                // nvim sent a request to us — reply with an error to unblock it
                const req_id = msg.array[1].integer;
                self.replyError(req_id);
                msgpack.freeValue(msg, self.allocator);
            } else if (msg_type == 1) {
                const resp_id = msg.array[1].integer;
                if (resp_id == id) {
                    const err_val = msg.array[2];
                    if (err_val != .nil) {
                        if (err_val == .array and err_val.array.len >= 2 and err_val.array[1] == .string) {
                            std.debug.print("Neovim RPC Error: {s}\n", .{err_val.array[1].string});
                        } else {
                            std.debug.print("Unknown Neovim RPC Error\n", .{});
                        }
                        return error.NvimRpcError;
                    }
                    const result = msg.array[3];
                    for (msg.array, 0..) |item, idx| {
                        if (idx != 3) msgpack.freeValue(item, self.allocator);
                    }
                    self.allocator.free(msg.array);
                    return result;
                } else {
                    msgpack.freeValue(msg, self.allocator);
                }
            } else if (msg_type == 2) {
                if (self.on_notification) |cb| {
                    var callback_timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.callback_dispatch);
                    defer callback_timer.stop();
                    const method = msg.array[1].string;
                    const params = msg.array[2];
                    try cb(self.on_notification_ctx, method, params);
                }
                msgpack.freeValue(msg, self.allocator);
            } else {
                msgpack.freeValue(msg, self.allocator);
            }
        }
    }

    fn waitResponseIncremental(self: *RpcClient, id: u32) !Value {
        var retries: usize = 0;
        while (true) {
            const msg = (try self.incremental_reader.next()) orelse blk: {
                const pump = try self.pumpIncrementalOnce();
                if (try self.incremental_reader.next()) |decoded| break :blk decoded;
                if (pump == .eof) return error.EndOfStream;
                if (pump == .progress) {
                    retries = 0;
                    continue;
                }
                if (retries >= 100) return error.Timeout;
                retries += 1;
                var fds = [1]posix.pollfd{.{ .fd = self.process.stdout.handle, .events = posix.POLL.IN, .revents = 0 }};
                _ = posix.poll(&fds, 100) catch {};
                continue;
            };
            retries = 0;
            errdefer msgpack.freeValue(msg, self.allocator);
            if (msg != .array or msg.array.len < 3 or msg.array[0] != .integer) return error.InvalidRpcMessage;
            const msg_type = msg.array[0].integer;
            if (msg_type == 0 and msg.array.len >= 4 and msg.array[1] == .integer) {
                self.replyError(msg.array[1].integer);
                msgpack.freeValue(msg, self.allocator);
            } else if (msg_type == 1 and msg.array.len >= 4 and msg.array[1] == .integer) {
                if (msg.array[1].integer != id) {
                    msgpack.freeValue(msg, self.allocator);
                    continue;
                }
                if (msg.array[2] != .nil) return error.NvimRpcError;
                const result = msg.array[3];
                for (msg.array, 0..) |item, index| if (index != 3) msgpack.freeValue(item, self.allocator);
                self.allocator.free(msg.array);
                return result;
            } else if (msg_type == 2 and msg.array[1] == .string) {
                if (self.on_notification) |callback| try callback(self.on_notification_ctx, msg.array[1].string, msg.array[2]);
                msgpack.freeValue(msg, self.allocator);
            } else {
                msgpack.freeValue(msg, self.allocator);
            }
        }
    }

    pub fn processNotifications(self: *RpcClient) !bool {
        if (self.async_enabled) return self.progressAsyncRead();
        var msg_count: usize = 0;
        const started = monotonicNanoseconds();
        while (self.hasData() and msg_count < 250 and monotonicNanoseconds() - started < 2 * std.time.ns_per_ms) : (msg_count += 1) {
            if (!try self.processOneMessage()) return false;
        }
        if (metrics.global.enabled) {
            metrics.global.queue_depth = @max(metrics.global.queue_depth, msg_count);
            if (msg_count > 1) metrics.global.coalesced_events +|= @intCast(msg_count - 1);
        }
        return true;
    }

    pub fn enableAsyncTransport(self: *RpcClient) void {
        self.async_enabled = true;
    }

    pub fn isAsyncEnabled(self: *const RpcClient) bool {
        return self.async_enabled;
    }

    pub fn wantsAsyncWrite(self: *const RpcClient) bool {
        return self.async_enabled and self.transport.wantsWrite();
    }

    /// A bounded read turn may leave complete frames in the userspace decoder
    /// after the kernel pipe has been drained. Keep the reactor runnable until
    /// nextInbound() confirms that buffered input is exhausted.
    pub fn wantsAsyncReadProgress(self: *const RpcClient) bool {
        return self.async_enabled and self.async_read_pending;
    }

    pub fn requestAsync(self: *RpcClient, method: []const u8, params: []const Value) !async_transport.RequestId {
        return self.requestAsyncWithDeadline(method, params, monotonicNanoseconds() + default_request_timeout_ns);
    }

    pub fn requestAsyncWithDeadline(self: *RpcClient, method: []const u8, params: []const Value, deadline_ns: ?i128) !async_transport.RequestId {
        if (!self.async_enabled) return error.AsyncTransportDisabled;
        return self.transport.queueRequestWithDeadline(method, params, deadline_ns);
    }

    pub fn requestAsyncWithHandler(self: *RpcClient, method: []const u8, params: []const Value, context: ?*anyopaque, callback: AsyncHandler) !async_transport.RequestId {
        if (!self.async_enabled) {
            const result = try self.call(method, params);
            const fallback_id: async_transport.RequestId = @enumFromInt(0);
            var completion = async_transport.Completion{
                .id = fallback_id,
                .outcome = .{ .response = .{ .error_value = .nil, .result = result } },
            };
            defer completion.deinit(self.allocator);
            try callback(context, &completion);
            return fallback_id;
        }
        if (self.handler_len == self.handlers.len) return error.HandlerRegistryFull;
        const id = try self.requestAsync(method, params);
        self.handlers[self.handler_len] = .{ .id = id, .context = context, .callback = callback };
        self.handler_len += 1;
        return id;
    }

    pub fn takeAsyncCompletion(self: *RpcClient) ?async_transport.Completion {
        return self.transport.takeCompletion();
    }

    pub fn takeCompletionsDispatched(self: *RpcClient) bool {
        const dispatched = self.completions_dispatched;
        self.completions_dispatched = false;
        return dispatched;
    }

    pub fn cancelAsync(self: *RpcClient, id: async_transport.RequestId) bool {
        return self.transport.cancel(id);
    }

    pub fn progressAsyncDeadlines(self: *RpcClient, now_ns: i128) !void {
        _ = self.transport.expire(now_ns);
        try self.dispatchQueuedCompletions();
    }

    pub fn progressAsyncDeadlinesNow(self: *RpcClient) !void {
        try self.progressAsyncDeadlines(monotonicNanoseconds());
    }

    pub fn finishAsync(self: *RpcClient, reason: async_transport.FailureReason) !void {
        self.async_read_pending = false;
        self.transport.finishWithReason(reason);
        var first_error: ?anyerror = null;
        while (!self.transport.isEofDrained()) {
            var inbound = self.transport.nextInbound() catch |err| {
                if (first_error == null) first_error = err;
                break;
            } orelse continue;
            defer inbound.deinit(self.allocator);
            switch (inbound) {
                .notification => |message| self.dispatchNotificationOrRequest(message) catch |err| if (first_error == null) {
                    first_error = err;
                },
                .request => {},
                .unknown_response => {},
                .response_completed => self.dispatchQueuedCompletions() catch |err| if (first_error == null) {
                    first_error = err;
                },
            }
        }
        self.dispatchQueuedCompletions() catch |err| if (first_error == null) {
            first_error = err;
        };
        if (first_error) |err| return err;
    }

    pub fn shutdownAsync(self: *RpcClient) !void {
        self.async_read_pending = false;
        self.transport.shutdown();
        try self.dispatchQueuedCompletions();
    }

    pub fn progressAsyncWrite(self: *RpcClient) !void {
        if (!self.async_enabled) return;
        const Writer = struct {
            fn write(fd: posix.fd_t, bytes: []const u8) !usize {
                const rc = posix.system.write(fd, bytes.ptr, bytes.len);
                return switch (posix.errno(rc)) {
                    .SUCCESS => if (rc > 0) @intCast(rc) else error.Closed,
                    .INTR, .AGAIN => 0,
                    else => error.WriteFailed,
                };
            }
        };
        _ = try self.transport.flushOne(self.process.stdin.handle, Writer.write);
    }

    pub fn progressAsyncRead(self: *RpcClient) !bool {
        if (!self.async_enabled) return error.AsyncTransportDisabled;
        self.async_read_pending = false;
        var bytes: [8192]u8 = undefined;
        const rc = posix.system.read(self.process.stdout.handle, &bytes, bytes.len);
        switch (posix.errno(rc)) {
            .SUCCESS => if (rc == 0) {
                self.transport.finish();
            } else try self.transport.feed(bytes[0..@intCast(rc)]),
            .INTR, .AGAIN => {},
            else => return error.ReadFailed,
        }
        const started = monotonicNanoseconds();
        var count: usize = 0;
        var decoder_drained = false;
        while (count < 250 and monotonicNanoseconds() - started < 2 * std.time.ns_per_ms) : (count += 1) {
            var inbound = try self.transport.nextInbound() orelse {
                decoder_drained = true;
                break;
            };
            defer inbound.deinit(self.allocator);
            switch (inbound) {
                .notification => |message| try self.dispatchNotificationOrRequest(message),
                .request => |message| {
                    if (message.array.len >= 2 and message.array[1] == .integer and message.array[1].integer > 0 and message.array[1].integer <= std.math.maxInt(u32)) {
                        // A required reply may never be silently dropped. If
                        // its reserved admission is exhausted, fail this
                        // transport turn explicitly so the owner can close or
                        // restart the channel rather than strand Neovim.
                        try self.transport.queueReply(@enumFromInt(@as(u32, @intCast(message.array[1].integer))), .{ .string = "method not found" }, .nil);
                    }
                },
                .unknown_response => {},
                .response_completed => try self.dispatchQueuedCompletions(),
            }
        }
        self.async_read_pending = !decoder_drained and !self.transport.isEofDrained();
        if (self.transport.isEofDrained()) try self.dispatchQueuedCompletions();
        return !self.transport.isEofDrained();
    }

    fn dispatchQueuedCompletions(self: *RpcClient) !void {
        var first_error: ?anyerror = null;
        while (self.transport.takeCompletion()) |value| {
            var completion = value;
            defer completion.deinit(self.allocator);
            self.dispatchCompletionToHandler(&completion) catch |err| if (first_error == null) {
                first_error = err;
            };
        }
        if (first_error) |err| return err;
    }

    fn dispatchCompletionToHandler(self: *RpcClient, completion: *async_transport.Completion) !void {
        const id = completion.id;
        for (self.handlers[0..self.handler_len], 0..) |entry, index| {
            if (entry.?.id != id) continue;
            const handler = entry.?;
            std.mem.copyForwards(?HandlerEntry, self.handlers[index .. self.handler_len - 1], self.handlers[index + 1 .. self.handler_len]);
            self.handler_len -= 1;
            self.handlers[self.handler_len] = null;
            self.completions_dispatched = true;
            try handler.callback(handler.context, completion);
            return;
        }
        // Unobserved completions are intentionally disposed here.
    }

    fn processOneMessage(self: *RpcClient) !bool {
        if (compatibility.incremental_decoder) return self.processOneIncrementalMessage();
        const checkpoint = self.reader.head;
        var decode_timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.rpc_decode);
        const msg = msgpack.decode(&self.reader, self.allocator) catch |err| {
            decode_timer.stop();
            self.reader.head = checkpoint;
            if (err == error.EndOfStream) return false;
            return err;
        };
        decode_timer.stop();
        self.reader.discardConsumed();
        defer msgpack.freeValue(msg, self.allocator);
        if (msg != .array or msg.array.len < 3 or msg.array[0] != .integer) return true;
        const msg_type = msg.array[0].integer;
        if (msg_type == 0 and msg.array.len >= 4 and msg.array[1] == .integer) {
            self.replyError(msg.array[1].integer);
        } else if (msg_type == 2 and msg.array[1] == .string) {
            if (self.on_notification) |cb| {
                var callback_timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.callback_dispatch);
                defer callback_timer.stop();
                try cb(self.on_notification_ctx, msg.array[1].string, msg.array[2]);
            }
        }
        return true;
    }

    fn processOneIncrementalMessage(self: *RpcClient) !bool {
        const message = (try self.incremental_reader.next()) orelse blk: {
            const pump = try self.pumpIncrementalOnce();
            if (try self.incremental_reader.next()) |decoded| break :blk decoded;
            return pump != .eof;
        };
        defer msgpack.freeValue(message, self.allocator);
        try self.dispatchNotificationOrRequest(message);
        return true;
    }

    /// Result of one bounded compatibility-transport read.
    const PumpResult = enum { progress, would_block, eof };

    fn pumpIncrementalOnce(self: *RpcClient) !PumpResult {
        var temporary: [8192]u8 = undefined;
        while (true) {
            const rc = posix.system.read(self.process.stdout.handle, &temporary, temporary.len);
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    if (rc == 0) {
                        self.incremental_reader.finish();
                        return .eof;
                    }
                    try self.incremental_reader.feed(temporary[0..@intCast(rc)]);
                    return .progress;
                },
                .INTR => continue,
                .AGAIN => return .would_block,
                else => return error.ReadFailed,
            }
        }
    }

    fn dispatchNotificationOrRequest(self: *RpcClient, msg: Value) !void {
        if (msg != .array or msg.array.len < 3 or msg.array[0] != .integer) return;
        const msg_type = msg.array[0].integer;
        if (msg_type == 0 and msg.array.len >= 4 and msg.array[1] == .integer) {
            self.replyError(msg.array[1].integer);
        } else if (msg_type == 2 and msg.array[1] == .string) {
            if (self.on_notification) |cb| {
                var callback_timer = metrics.ScopedTimer.start(&metrics.global, &metrics.global.callback_dispatch);
                defer callback_timer.stop();
                try cb(self.on_notification_ctx, msg.array[1].string, msg.array[2]);
            }
        }
    }

    pub fn hasData(self: *RpcClient) bool {
        if (compatibility.incremental_decoder and self.incremental_reader.bufferedLen() != 0) return true;
        if (self.reader.head < self.reader.buf.items.len) return true;
        var fds = [1]posix.pollfd{.{ .fd = self.process.stdout.handle, .events = posix.POLL.IN, .revents = 0 }};
        const rc = posix.poll(&fds, 0) catch return false;
        return rc > 0 and (fds[0].revents & (posix.POLL.IN | posix.POLL.HUP | posix.POLL.ERR)) != 0;
    }
};

fn monotonicNanoseconds() i128 {
    var now: posix.timespec = undefined;
    _ = posix.system.clock_gettime(posix.CLOCK.MONOTONIC, &now);
    return @as(i128, now.sec) * std.time.ns_per_s + now.nsec;
}

pub const FdReader = struct {
    fd: posix.fd_t,
    buf: std.array_list.Managed(u8),
    head: usize = 0,

    pub fn init(fd: posix.fd_t, allocator: std.mem.Allocator) FdReader {
        return .{ .fd = fd, .buf = std.array_list.Managed(u8).init(allocator) };
    }

    pub fn deinit(self: *FdReader) void {
        self.buf.deinit();
    }

    pub fn discardConsumed(self: *FdReader) void {
        if (self.head == 0) return;
        if (self.head >= self.buf.items.len) {
            self.buf.clearRetainingCapacity();
            self.head = 0;
            return;
        }
        const remaining = self.buf.items.len - self.head;
        std.mem.copyForwards(u8, self.buf.items[0..remaining], self.buf.items[self.head..]);
        self.buf.shrinkRetainingCapacity(remaining);
        self.head = 0;
    }

    fn fill(self: *FdReader) !void {
        var temp: [8192]u8 = undefined;
        while (true) {
            const rc = posix.system.read(self.fd, &temp, temp.len);
            const err = posix.errno(rc);
            switch (err) {
                .SUCCESS => {
                    if (rc == 0) return error.EndOfStream;
                    try self.buf.appendSlice(temp[0..@as(usize, @intCast(rc))]);
                    return;
                },
                .INTR => continue,
                .AGAIN => {
                    // Non-blocking fd: wait up to 50ms for data.
                    // This prevents an infinite hang when only part of a
                    // msgpack message has arrived in the pipe buffer.
                    var fds = [1]posix.pollfd{.{ .fd = self.fd, .events = posix.POLL.IN, .revents = 0 }};
                    const poll_rc = posix.poll(&fds, 50) catch return error.WouldBlock;
                    if (poll_rc == 0) return error.WouldBlock; // timeout
                    continue;
                },
                else => return error.ReadFailed,
            }
        }
    }

    pub fn takeByte(self: *FdReader) !u8 {
        if (self.head >= self.buf.items.len) try self.fill();
        const b = self.buf.items[self.head];
        self.head += 1;
        return b;
    }

    pub fn takeInt(self: *FdReader, comptime T: type, endian: std.builtin.Endian) !T {
        var buf_int: [@sizeOf(T)]u8 = undefined;
        try self.readSliceAll(&buf_int);
        return std.mem.readInt(T, &buf_int, endian);
    }

    pub fn readSliceAll(self: *FdReader, dest: []u8) !void {
        var total_read: usize = 0;
        while (total_read < dest.len) {
            if (self.head >= self.buf.items.len) try self.fill();
            const available = self.buf.items.len - self.head;
            const needed = dest.len - total_read;
            const to_copy = @min(available, needed);
            @memcpy(dest[total_read .. total_read + to_copy], self.buf.items[self.head .. self.head + to_copy]);
            self.head += to_copy;
            total_read += to_copy;
        }
    }
};

test "completion handler dispatch latch is sticky and read once" {
    var client: RpcClient = .{
        .process = undefined,
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .reader = FdReader.init(-1, std.testing.allocator),
        .incremental_reader = incremental.Decoder.init(std.testing.allocator),
        .transport = async_transport.Transport.init(std.testing.allocator),
    };
    defer client.deinit();
    client.enableAsyncTransport();

    const Handler = struct {
        fn record(context: ?*anyopaque, _: *async_transport.Completion) anyerror!void {
            const calls: *usize = @ptrCast(@alignCast(context.?));
            calls.* += 1;
        }
    };

    var calls: usize = 0;
    const handled_id = try client.requestAsyncWithHandler("handled", &.{}, &calls, Handler.record);
    try std.testing.expect(client.cancelAsync(handled_id));
    try client.progressAsyncDeadlines(0);
    try std.testing.expectEqual(@as(usize, 1), calls);

    _ = try client.requestAsyncWithDeadline("unhandled", &.{}, 1);
    try client.progressAsyncDeadlines(1);
    try std.testing.expect(client.takeCompletionsDispatched());
    try std.testing.expect(!client.takeCompletionsDispatched());

    _ = try client.requestAsyncWithDeadline("still-unhandled", &.{}, 2);
    try client.progressAsyncDeadlines(2);
    try std.testing.expect(!client.takeCompletionsDispatched());
}
