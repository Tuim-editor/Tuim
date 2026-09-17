const std = @import("std");
const nvim = @import("../nvim/msgpack.zig");
const ui = @import("../nvim/ui_protocol.zig");
const renderer = @import("renderer.zig");
const input = @import("input.zig");
const rpc_client = @import("../nvim/rpc.zig");
const theme = @import("theme.zig");
const settings = @import("widgets/settings.zig");
const Layout = @import("layout.zig").Layout;
const SplitNode = @import("layout.zig").SplitNode;
const ActivityBar = @import("widgets/activity_bar.zig").ActivityBar;
const Terminal = @import("terminal.zig").Terminal;
const Explorer = @import("widgets/explorer.zig").Explorer;
const GitPanel = @import("widgets/git_panel.zig").GitPanel;
const SearchPanel = @import("widgets/search_panel.zig").SearchPanel;
const AiPanel = @import("widgets/ai_panel.zig").AiPanel;
const OutputPanel = @import("widgets/output_panel.zig").OutputPanel;
const DebugConsole = @import("widgets/debug_console.zig").DebugConsole;
const MasonWidget = @import("widgets/mason.zig").MasonWidget;
const LazyWidget = @import("widgets/lazy.zig").LazyWidget;
const GitDetailedWidget = @import("widgets/git_detailed.zig").GitDetailedWidget;
const ExtensionShop = @import("widgets/extension_shop.zig").ExtensionShop;
const BugReportWidget = @import("widgets/bug_report.zig").BugReportWidget;
const EditorContextMenu = @import("widgets/editor_context_menu.zig").EditorContextMenu;
const Invalidations = @import("invalidation.zig").Invalidations;

pub const Mode = enum { ide, zen, normal };
pub const PanelPosition = enum { bottom, right };
pub const NoticeLevel = enum { info, warning, failure };

pub const WinInfo = struct {
    id: i64,
    bufnr: i64,
    row: u16,
    col: u16,
    width: u16,
    height: u16,
    active: bool = false,
    name: []const u8 = "",
};

pub const TabInfo = struct {
    bufnr: i64 = 0,
    name: []const u8,
    path: ?[]const u8,
    modified: bool = false,
};

pub const RpcContext = struct {
    app: *App,
    ui_state: *ui.UiState,
};

pub const App = struct {
    allocator: std.mem.Allocator,
    term: *Terminal,
    ren: *renderer.Renderer,
    rpc: *rpc_client.RpcClient,
    rpc_term: *rpc_client.RpcClient,

    ui_state: *ui.UiState,
    ui_term: *ui.UiState,

    active_theme: theme.Theme,
    mode: Mode,
    prev_mode: Mode,

    tabs: std.array_list.Managed(TabInfo),
    active_tab: usize,

    terminal_focus: bool,
    notice_text: [256]u8,
    notice_len: usize,
    notice_level: NoticeLevel,
    notice_deadline: i64,
    show_file_tree: bool,
    show_terminal_panel: bool,

    invalidations: Invalidations,
    terminal_panel_height: u16,
    terminal_panel_width: u16, // For right-side panel
    active_terminal_panel_idx: u8, // 0=Terminal, 1=Debug, 2=Output
    panel_position: PanelPosition,

    settings_widget: *settings.SettingsWidget,
    explorer: *Explorer,
    git_panel: *GitPanel,
    search_panel: *SearchPanel,
    ai_panel: *AiPanel,
    output_panel: *OutputPanel,
    debug_console: *DebugConsole,
    mason_widget: *MasonWidget,
    lazy_widget: *LazyWidget,
    git_detailed_widget: *GitDetailedWidget,
    extension_shop: *ExtensionShop,
    bug_report: *BugReportWidget,
    editor_context_menu: EditorContextMenu = .{},
    activity_bar: ActivityBar,

    // Mouse tracking state
    is_resizing_sidebar: bool = false,
    is_resizing_panel: bool = false,
    last_click_x: u16 = 0,
    last_click_y: u16 = 0,
    file_tree_width: u16 = 24,
    was_settings_open: bool = false,
    last_explorer_refresh: i64 = 0,

    show_split_menu: bool = false,
    split_menu_dir: enum { right, bottom } = .right,
    split_menu_x: u16 = 0,
    split_menu_y: u16 = 0,

    editor_win_count: usize = 1,
    terminal_win_count: usize = 1,
    deferred_exit: @import("../nvim/call_sites_05c.zig").DeferredExit = .none,
    quit_pending: bool = false,

    sidebar_focus: bool = false,
    workspace: @import("workspace.zig").State = .{},
    zen_sidebar_focus: bool = false,
    zen_terminal_focus: bool = false,

    editor_wins: std.array_list.Managed(WinInfo),
    terminal_wins: std.array_list.Managed(WinInfo),

    layout_arena: std.heap.ArenaAllocator,
    root_split: *SplitNode,

    pub fn layout(self: *const App, cols: u16, rows: u16) Layout {
        return if (self.mode != .zen)
            Layout.workspace(cols, rows, self.show_file_tree, self.file_tree_width, self.root_split)
        else
            Layout.compute(cols, rows, self.mode == .zen, self.show_file_tree, self.file_tree_width, self.root_split);
    }

    pub fn init(allocator: std.mem.Allocator, term: *Terminal, ren: *renderer.Renderer, rpc: *rpc_client.RpcClient, rpc_term: *rpc_client.RpcClient, ui_state: *ui.UiState, ui_term: *ui.UiState) App {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const arena_alloc = arena.allocator();

        const editor_node = arena_alloc.create(SplitNode) catch unreachable;
        editor_node.* = .{ .data = .{ .view = .editor } };

        const root_node = editor_node;

        return App{
            .allocator = allocator,
            .term = term,
            .ren = ren,
            .rpc = rpc,
            .rpc_term = rpc_term,
            .ui_state = ui_state,
            .ui_term = ui_term,
            .active_theme = theme.Theme{},
            .mode = .normal,
            .prev_mode = .normal,
            .tabs = std.array_list.Managed(TabInfo).init(allocator),
            .active_tab = 0,
            .terminal_focus = false,
            .notice_text = undefined,
            .notice_len = 0,
            .notice_level = .info,
            .notice_deadline = 0,
            .sidebar_focus = false,
            .show_file_tree = true,
            .show_terminal_panel = false,
            .invalidations = .{},
            .terminal_panel_height = 8,
            .terminal_panel_width = 50,
            .active_terminal_panel_idx = 0,
            .panel_position = .bottom,
            .settings_widget = undefined,
            .explorer = undefined,
            .git_panel = undefined,
            .search_panel = undefined,
            .ai_panel = undefined,
            .output_panel = undefined,
            .debug_console = undefined,
            .mason_widget = undefined,
            .lazy_widget = undefined,
            .git_detailed_widget = undefined,
            .extension_shop = undefined,
            .bug_report = undefined,
            .activity_bar = ActivityBar{ .active_idx = 0 },
            .layout_arena = arena,
            .root_split = root_node,
            .editor_wins = std.array_list.Managed(WinInfo).init(allocator),
            .terminal_wins = std.array_list.Managed(WinInfo).init(allocator),
        };
    }

    pub fn deinit(self: *App) void {
        for (self.editor_wins.items) |win| {
            if (win.name.len > 0) self.allocator.free(win.name);
        }
        for (self.terminal_wins.items) |win| {
            if (win.name.len > 0) self.allocator.free(win.name);
        }
        self.editor_wins.deinit();
        self.terminal_wins.deinit();
        self.layout_arena.deinit();
    }

    pub fn notify(self: *App, level: NoticeLevel, comptime format: []const u8, args: anytype) void {
        const text = std.fmt.bufPrint(&self.notice_text, format, args) catch "Operation failed";
        self.notice_len = text.len;
        self.notice_level = level;
        var ts: std.posix.timespec = undefined;
        _ = std.posix.system.clock_gettime(std.posix.CLOCK.MONOTONIC, &ts);
        self.notice_deadline = ts.sec + 5;
        self.invalidations.damage(.overlay);
    }

    pub fn activeNotice(self: *App) ?[]const u8 {
        if (self.notice_len == 0) return null;
        var ts: std.posix.timespec = undefined;
        _ = std.posix.system.clock_gettime(std.posix.CLOCK.MONOTONIC, &ts);
        if (ts.sec >= self.notice_deadline) {
            self.notice_len = 0;
            self.invalidations.damage(.overlay);
            return null;
        }
        return self.notice_text[0..self.notice_len];
    }

    pub fn updateLayoutTree(self: *App) void {
        _ = self.layout_arena.reset(.retain_capacity);
        const alloc = self.layout_arena.allocator();
        if (self.show_terminal_panel) {
            const editor_node = alloc.create(SplitNode) catch return;
            editor_node.* = .{ .data = .{ .view = .editor } };
            const panel_node = alloc.create(SplitNode) catch return;
            panel_node.* = .{ .data = .{ .view = .panel } };

            const split_node = alloc.create(SplitNode) catch return;
            const total_w = self.ren.width;
            const total_h = self.ren.height;
            const content_h = if (total_h > 2) total_h - 2 else 1;

            if (self.panel_position == .bottom) {
                const panel_h = @as(f32, @floatFromInt(self.terminal_panel_height));
                const content_h_f = @as(f32, @floatFromInt(content_h));
                const ratio = if (content_h_f > panel_h) (content_h_f - panel_h) / content_h_f else 0.7;
                split_node.* = .{ .data = .{ .split = .{
                    .dir = .vertical,
                    .ratio = ratio,
                    .child1 = editor_node,
                    .child2 = panel_node,
                } } };
            } else {
                const content_w = if (self.mode != .zen)
                    Layout.workspace(total_w, total_h, self.show_file_tree, self.file_tree_width, null).editor.w
                else
                    Layout.compute(total_w, total_h, false, self.show_file_tree, self.file_tree_width, null).editor.w;
                const panel_w = @as(f32, @floatFromInt(self.terminal_panel_width));
                const content_w_f = @as(f32, @floatFromInt(content_w));
                const ratio = if (content_w_f > panel_w) (content_w_f - panel_w) / content_w_f else 0.7;
                split_node.* = .{ .data = .{ .split = .{
                    .dir = .horizontal,
                    .ratio = ratio,
                    .child1 = editor_node,
                    .child2 = panel_node,
                } } };
            }

            self.root_split = split_node;
        } else {
            const editor_node = alloc.create(SplitNode) catch return;
            editor_node.* = .{ .data = .{ .view = .editor } };
            self.root_split = editor_node;
        }
    }
};
