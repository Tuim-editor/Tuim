# Plugin compatibility

Tuim is a Neovim UI client, not a normal terminal session running Neovim.
Plugins execute inside Tuim's isolated editor process and render through
Neovim's multigrid UI protocol. This boundary matters more than whether a
plugin is written in Lua or Vimscript.

## Plugin ownership

- Bundled plugins are declared in `src/nvim/tuim_init.lua`, installed under
  Tuim's data directory, and tested with the shipped configuration.
- User-installed Tuim plugins are listed in
  `$XDG_DATA_HOME/tuim/user_plugins.json`. Their optional configuration files
  live under `$XDG_DATA_HOME/tuim/plugin_configs/` and return lazy.nvim spec overrides.
- Desired enable/disable/removal state lives in `plugin_states.json` in the same
  data directory. `plugin_inventory.json` is a generated inventory, not a user
  configuration file. The installed menu also scans Tuim's own plugin directories.
- Manage plugins directly in Extensions > Installed. State changes apply
  after restarting; config files are preserved when uninstalling.
- System-Neovim plugins and `~/.config/nvim` are unrelated. Tuim starts Neovim
  with `--clean` and `NVIM_APPNAME=tuim`; it neither loads nor modifies them.

## Tested compatibility

The following bundled modules are covered by `scripts/plugin_smoke.sh`, which
loads the shipped runtime in a disposable XDG environment and verifies that
their public modules load:

| Plugin | Tested surface |
| --- | --- |
| lazy.nvim | manager and shipped plugin specification |
| alpha-nvim | dashboard module |
| telescope.nvim | picker module and Tuim multigrid integration hooks |
| mason.nvim | registry UI module; package downloads are not part of this smoke test |
| blink.cmp | completion module availability |
| Harpoon | mark module |

Treesitter is loaded eagerly and pinned to a tested revision. The default
installer compiles and verifies parsers and highlight queries for Bash, C, C++,
CSS, Go, HTML, JavaScript, JSON, Lua, Markdown (including inline Markdown),
Python, Query, Rust, TSX, TypeScript, Vim, Vimdoc, and Zig. This requires
Neovim 0.12+, a C compiler, and Tree-sitter CLI 0.26.1+; setup provisions the
required tools. `--no-plugins` explicitly skips that bootstrap.

LSP servers, formatters, and Mason packages are separate tools. Treesitter
highlighting does not imply that every language server or formatter is installed.
Run `TUIM_TEST_PLUGIN_DATA=~/.local/share/tuim python3 tests/default_runtime.py`
to verify installed parsers, queries, startup loading, and actual Zig highlighting.

Run the smoke test after bootstrapping plugins:

```bash
scripts/plugin_smoke.sh
```

## Compatibility boundary

Plugins that operate on buffers, windows, diagnostics, completion, or standard
Neovim floating windows are the best fit. Plugins must tolerate `--embed`,
`ext_multigrid`, an external status/tab UI, and Tuim's IDE-mode mappings.

The following categories are unsupported unless tested and adapted:

- GUI-client-specific plugins that require Neovide, Goneovim, or another GUI
  API.
- Terminal graphics plugins that write Kitty, Sixel, or iTerm image escape
  sequences directly to Neovim's stdout. That stdout is Tuim's RPC transport,
  not the user's terminal.
- Plugins that replace or bypass Neovim's UI protocol by writing directly to
  the outer terminal.
- Plugins that assume the user's normal `~/.config/nvim` runtime or mutate
  global system-Neovim plugin directories.
- Terminal-multiplexer integrations that require ownership of the outer tmux
  pane rather than operating through Neovim commands.

An unlisted plugin is unknown, not implicitly compatible. Install it inside
Tuim, keep its configuration isolated, and verify startup, rendering, input,
and shutdown before adding it to the tested table.

If a broken plugin prevents startup, launch Tuim once with
`TUIM_DISABLE_PLUGINS=1 tuim`. This skips lazy.nvim bootstrap and all bundled
and user plugin setup while preserving plugin files, allowing settings or the
plugin state and configuration to be repaired safely.

Open Settings > Plugins > Plugin Manager and press `s` to synchronize. If
bootstrap was interrupted or Tuim started offline, the same action retries
lazy.nvim bootstrap before synchronization. Progress and failures appear as
native notices and detailed Lua errors remain available in Neovim messages and
the Tuim log. User plugins can be removed from the extension shop while in a
recovery session; unrelated system-Neovim plugins are never changed.
