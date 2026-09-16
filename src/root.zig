test "all core modules compile and register their tests" {
    _ = @import("metrics.zig");
    _ = @import("reactor.zig");
    _ = @import("task_runner.zig");
    _ = @import("git_snapshot.zig");
    _ = @import("nvim/msgpack.zig");
    _ = @import("nvim/incremental_decoder.zig");
    _ = @import("nvim/async_transport.zig");
    _ = @import("nvim/call_sites_05c.zig");
    _ = @import("nvim/process.zig");
    _ = @import("nvim/rpc.zig");
    _ = @import("nvim/ui_protocol.zig");
    _ = @import("tui/layout.zig");
    _ = @import("tui/invalidation.zig");
    _ = @import("tui/views.zig");
    _ = @import("tui/workspace.zig");
    _ = @import("tui/input.zig");
    _ = @import("tui/capabilities.zig");
    _ = @import("tui/terminal.zig");
    _ = @import("tui/theme.zig");
    _ = @import("tui/widgets/primitives.zig");
    _ = @import("tui/widgets/git_panel.zig");
    _ = @import("tui/widgets/ai_panel.zig");
    _ = @import("tui/widgets/bug_report.zig");
    _ = @import("tui/widgets/editor_context_menu.zig");
}
