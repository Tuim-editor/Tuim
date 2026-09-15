# Architecture

Tuim is a Zig terminal application with an isolated Neovim editor. For product
behavior and shortcuts, see the [usage guide](usage.md).

## Processes and ownership

`src/main.zig` starts two embedded Neovim processes through
`src/nvim/process.zig`. Both use `NVIM_APPNAME=tuim` and `--clean`:

- The editor loads `src/nvim/tuim_init.lua` and owns buffers, windows, text,
  undo, diagnostics, language servers, and plugins.
- The terminal frontend loads `src/nvim/terminal_init.lua`, without the editor
  plugin stack. Its shell starts when the integrated terminal is first opened.

The Zig frontend owns terminal input, application mode, layout, native widgets,
focus, and rendering. `src/tui/app.zig` holds UI state, `events.zig` routes input,
and `views.zig` composites the editor grids and native controls.

## Event loop and background work

`src/reactor.zig` collects readiness for terminal input, resize notifications,
Neovim transports, and task completions. Each cycle progresses through transport
work, normalized event dispatch, state updates, composition, and flushing.
Registration generations prevent stale events from targeting reused descriptors.

The interactive thread owns application state, RPC clients, UI grids, and
rendering. `src/task_runner.zig` handles bounded background work, including Git
refreshes. Commands and results have explicit ownership; owner IDs and
generations reject stale completions. Workers do not access live widget arenas
or Neovim RPC clients. Shutdown reaps owned children and releases queued work.

## RPC and rendering

`src/nvim/msgpack.zig`, `incremental_decoder.zig`, `async_transport.zig`, and
`rpc.zig` implement MessagePack-RPC. Startup uses bounded synchronous requests;
the interactive session uses bounded asynchronous transport and completion
handlers. Result-dependent operations apply state only after their response.

`src/nvim/ui_protocol.zig` consumes Neovim's line-grid, multigrid, and highlight
events. `src/tui/invalidation.zig` separates layout, sizing, and composition
changes. The renderer retains coarse regions, compares cell buffers, and emits
changed terminal row runs rather than repainting the whole screen.

Native dialogs share geometry and hit-test helpers in
`src/tui/widgets/primitives.zig`. The Extensions workspace uses a searchable
list and details pane, with a compact details view in smaller terminals.

## Configuration and plugins

Settings are persisted in Tuim's data directory. Normal and IDE share the
workspace; IDE applies modeless mappings to editable buffers. Zen hides the
workspace while preserving a return footer and the previous editing mode.

`src/nvim/store_search.py` is embedded into the executable and extracted into
the data directory. The Extensions widget invokes it for catalog searches,
offline inventory, and lifecycle changes. Its stdout is a JSON interface.

Plugin state is stored separately from code:

| File or directory in Tuim's data directory | Purpose |
| --- | --- |
| `settings.json` | Native application preferences |
| `user_plugins.json` | Marketplace additions |
| `plugin_states.json` | Desired enabled, disabled, or removed state |
| `plugin_inventory.json` | Generated bundled and runtime inventory |
| `plugin_configs/` | User Lua spec overrides |
| `lazy/` | Installed plugin files |
| `site/` | Parser and query assets |
| `tools/` | Private build and parser tools |

Neovim applies plugin state at startup. Disabled plugins stay on disk; explicitly
removed plugins are cleaned after the new specification loads. Configuration
files survive removal. Recovery mode skips user plugin configuration execution.
See [plugin compatibility](plugin-compatibility.md) for operational details.

## Storage and failure boundaries

Tuim uses its own `tuim` subdirectory under each XDG config, data, state, and
cache location. It does not load the user's regular Neovim configuration.
Normal upgrades preserve settings and plugin data.

Terminal setup is reversed on shutdown. RPC failure, plugin configuration
errors, and background-task failures should surface through native notices and
logs without corrupting the current buffer or reporting unfinished work as
successful. Session reload waits for session-save completion.

## Validation

`zig build test` covers core modules. Python and shell tests under `tests/`
exercise real Neovim sessions, terminal UI, installation, plugin lifecycle, and
release launchers. GitHub Actions builds Linux targets and runs macOS smoke
checks; consult [terminal compatibility](terminal-compatibility.md) for limits.
Use the [performance harness](performance.md) for measured runtime comparisons.
