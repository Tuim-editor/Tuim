# Tuim

**Your editor. Your terminal.**

Tuim is a terminal workspace written in Zig, with Neovim as its editing engine.
It brings an Explorer, Git, an integrated shell, settings, and coding-assistant
launchers into one keyboard- and mouse-accessible interface. Tuim uses its own
configuration and plugin environment, separate from your regular Neovim setup.

[Website](https://tuim-editor.github.io/Tuim/) ·
**v0.3.0** · [Release notes](docs/releases/v0.3.0.md) · [Latest release](https://github.com/Rouboufy/tuim/releases/latest) ·
[Usage guide](docs/usage.md) ·
[Issues](https://github.com/Rouboufy/tuim/issues)

[![Tuim editing build.zig with the current Explorer sidebar](docs/screenshots/explorer.webp)](docs/screenshots/explorer.webp)

*Actual terminal capture from the current source build, using a demo project
and portable symbols with the default VS Code Dark Modern theme and Treesitter enabled. Published releases may
differ. See [screenshot capture instructions](docs/screenshots/README.md).*

## The workspace

- **Files and commands:** Explorer opens by default. Click **< Workspace** to
  reach open files and tools, or press **F1** to search commands.
- **Editor:** Vim motions in Normal mode, familiar modeless editing in IDE mode,
  editor splits, mouse selection, and right-click actions.
- **Terminal and Git:** toggle a persistent shell panel; inspect changes, stage
  files, and commit from the Git sidebar.
- **Language tools:** completion, Treesitter, LSP, and diagnostics through the
  bundled Neovim configuration. Treesitter loads at startup; setup installs and
  verifies 19 default parsers. Lazy manages plugins; Mason manages language
  servers and other tools. Open **Workspace → Language tools** or search for
  **Language tools** with **F1** to manage them. Initial installation requires
  network access.
- **Coding assistants:** launch supported, installed CLIs from the AI panel and
  share editor context. Each assistant needs its own installation and authentication.
- **Settings:** change themes, indentation, line numbers, and shortcuts in the
  native settings panel.

### Three editing modes

| Mode | Behavior |
| --- | --- |
| **Normal** | Neovim's modal editing with the Tuim workspace around it. |
| **IDE** | Modeless file editing with familiar selection, clipboard, save, and undo shortcuts. Utility and plugin buffers keep their required modes. |
| **Zen** | The editor fills the viewport except for a small mode/return footer. The sidebar and terminal are hidden. |

Click the footer's mode badge to choose a mode. **F11** toggles Zen and returns
to the previous Normal or IDE mode, preserving the terminal session.

| Workspace | Integrated terminal |
| --- | --- |
| [![Open files and tools](docs/screenshots/normal.webp)](docs/screenshots/normal.webp) | [![Integrated terminal](docs/screenshots/terminal.webp)](docs/screenshots/terminal.webp) |

## Installation

Linux is the primary tested platform. Release packaging targets Linux x86-64
and ARM64, and macOS Intel and Apple Silicon. macOS and WSL workflows still need
broader verification; see [terminal compatibility](docs/terminal-compatibility.md).

### Recommended installer

```bash
curl -fsSL https://raw.githubusercontent.com/Rouboufy/tuim/main/setup.sh | bash
tuim
```

The [installer](setup.sh) downloads the latest matching release bundle, verifies
its SHA-256 checksum, and installs it under Tuim's data directory. It links the
launcher at `~/.local/bin/tuim`. **Release bundles include a private Neovim
runtime; neither a separate Neovim installation nor Zig is needed.**

The installer checks required dependencies and asks before installing missing
system packages. For unattended installation, pipe into `bash -s -- --yes`.
Setup installs missing Python 3, Git, archive tools, ripgrep, a C compiler,
Make, and unzip through apt, pacman, dnf, zypper, or Homebrew. It installs a
private Tree-sitter CLI when the available version is older than 0.26.1, then
waits for plugin and parser installation to finish. A failed download, checksum,
plugin build, or parser check stops setup with an error instead of reporting success.
GitHub downloads and initial plugin setup require network access.

On macOS, Homebrew is required for missing packages. If Apple's Command Line
Tools are absent, setup starts their installer; complete that system dialog and
rerun setup. System clipboard integration is platform-dependent and is not a
prerequisite for editing.

Options: `--dry-run`, `--no-plugins` (skip plugin/parser bootstrap and parser build tools), `--source`, and
`--yes`. Unsupported release targets require an explicit source build; the
installer does not silently fall back to compilation.

If `tuim` is not found, add `~/.local/bin` to your shell's `PATH`. Run
`tuim --version` to print the build version without opening the application.

### Other downloads

- [Native release bundles](https://github.com/Rouboufy/tuim/releases/latest):
  Linux and macOS archives with checksums and bundled Neovim.
- [Linux x86-64 AppImage](https://github.com/Rouboufy/tuim/releases/latest/download/Tuim-linux-x86_64.AppImage):
  a portable package with Neovim included. See [AppImage instructions](docs/appimage.md).

### Build from source

Requires **Zig 0.16.0 exactly**, **Neovim 0.12.0 or newer**, and Git.
Python 3 is needed for the plugin marketplace and installed plugin menu. A Nerd Font is recommended;
icons are enabled by default and can be replaced with portable symbols in Settings.

```bash
git clone https://github.com/Rouboufy/tuim.git
cd tuim
zig build -Doptimize=ReleaseFast
./zig-out/bin/tuim
```

For a user-local source installation, run `bash setup.sh --source --yes` from the
checkout. Setup downloads a checksum-verified private Zig toolchain and Neovim
runtime if compatible versions are missing. Its launcher uses those private
tools without replacing your system executables.

### Update and uninstall

For a release installation, rerun the recommended installer. It preserves
Tuim's settings and plugin data. For a source build, pull the checkout and rebuild:

```bash
git pull --ff-only
zig build -Doptimize=ReleaseFast
```

From a source checkout, `bash uninstall.sh --binary` removes the launcher while
keeping data. `bash uninstall.sh --all` removes Tuim's configuration, plugins,
bundled runtime, cache, and sessions after confirmation. See
`bash uninstall.sh --help` for selective removal options.

## Getting started

First launch offers a simple guide to opening, editing, and saving files,
with a choice of editing style and an easy-to-find close action. Reopen it with
`:TuimOnboarding` in Normal mode.

| Action | Default shortcut |
| --- | --- |
| Search commands | `F1` |
| Toggle workspace sidebar | `Ctrl+E` |
| Toggle terminal panel | `Ctrl+T` |
| Select terminal text | `Ctrl+\`, `Ctrl+N`, then `v` and motions; `y` copies |
| Next / previous region | `F6` / `Shift+F6` |
| Create a file | `Ctrl+N` |
| Save | `Ctrl+S` |
| Find a file | `Ctrl+P` |
| Search project text (ripgrep) | `Alt+G` |
| Toggle Zen / previous mode | `F11` |

To create a file, press **Ctrl+N**, then type (`i` first in Normal mode). On the
first **Ctrl+S**, enter a filename and press **Enter**. Relative paths use the
working directory. **Esc** cancels naming without discarding your text.

In Git, select a change with arrows or `j`/`k`, open it with **Enter**, and
stage or unstage it with **Space**. Press `c` to write a commit message, then
**Enter** to commit or **Esc** to return.

Shortcuts are customizable. The Vim-safe preset moves common workspace controls
to Alt combinations so they do not intercept Neovim's Ctrl bindings. See the
[usage guide](docs/usage.md) for editor mappings, shortcut presets, IDE selection,
language tools, and accessibility behavior.

## Configuration

New installs default to **[VS Code Dark Modern](https://code.visualstudio.com/docs/configure/themes)**; saved theme choices are preserved.
Open **F1 → Settings → Appearance** to select it on an existing installation.
Settings → About shows the running versions and active
settings, data, and log paths. Tuim uses `NVIM_APPNAME=tuim` and the standard XDG
locations, honoring their environment overrides:

| Default directory | Contents |
| --- | --- |
| `~/.config/tuim` | Configuration |
| `~/.local/share/tuim` | Settings, plugins, parsers, private tools, and release runtime |
| `~/.local/state/tuim` | Sessions and runtime state |
| `~/.cache/tuim` | Caches and generated artifacts |

Tuim does not load your Neovim init or modify your standard Neovim directories.
The optional **System** theme can read the Omarchy desktop palette and reuse
installed theme assets without loading your Neovim configuration. Details are
in the [usage guide](docs/usage.md).

## Troubleshooting and limitations

- **Manage plugins:** open Extensions for the Installed and Discover views.
  View bundled plugins and dependencies, search the marketplace, edit
  configuration, enable/disable, and uninstall. Changes apply after restarting;
  disabling keeps plugin files and uninstalling keeps your configuration.
- **Plugins fail to load:** inspect the log path in Settings → About. Retry
  synchronization with `s` in Settings → Plugins → Plugin Manager. For recovery,
  run `TUIM_DISABLE_PLUGINS=1 tuim`; this skips loading plugins without deleting them.
- **Broken icons:** select portable symbols in Settings or use a Nerd Font.
- **Clipboard or shortcuts differ:** clipboard providers, modified-key reporting,
  mouse support, tmux, and SSH depend on the terminal environment. Use F1 and
  mouse-accessible actions when a key combination is unavailable.
- **Source build cannot start:** check the pinned Zig version and that a supported
  `nvim` executable is available. Release bundles use their own Neovim instead.
- **Plugin compatibility:** plugins that require ownership of the outer terminal
  UI may not work in Tuim's embedded interface. Install plugins inside Tuim's
  environment; see [plugin compatibility](docs/plugin-compatibility.md).

## Development

Tuim launches an embedded Neovim editor and a separate lightweight Neovim
frontend for the integrated terminal. The shell starts when its panel is first
opened. The Zig frontend handles input and renders native widgets alongside
Neovim's UI events over MessagePack-RPC.

See [architecture](docs/architecture.md) for component responsibilities and
[usage](docs/usage.md) for the current interface.
[Performance notes](docs/performance.md) contain machine-specific measurements.

```bash
zig build test
zig build
python3 tests/pty_integration.py
python3 tests/site.py
bash tests/setup_plans.sh
python3 tests/setup_install.py
python3 tests/default_runtime.py
```

The [CI workflow](.github/workflows/ci.yml) defines formatting, shell, packaging,
media, link, and platform checks. The website is static HTML/CSS; its
[Pages workflow](.github/workflows/pages.yml) publishes changes from `main`.

Tagged `v*` releases trigger the [release workflow](.github/workflows/release.yml),
which tests and builds native bundles and an AppImage, generates checksums, and
publishes GitHub release assets. Verify target-platform behavior before tagging.

## Acknowledgements

Tuim is built on top of and inspired by an incredible open-source ecosystem. Special credit and gratitude go to:

- **Core Engines & Languages:**
  - [Neovim](https://neovim.io/) — the embedded editing engine, MessagePack-RPC, and terminal runtime.
  - [Tree-sitter](https://tree-sitter.github.io/) — incremental parsing system and grammar generator.
  - [Zig](https://ziglang.org/) — the systems language powering Tuim's frontend, TUI renderer, and event reactor.

- **Bundled Neovim Plugins & Integrations:**
  - [lazy.nvim](https://github.com/folke/lazy.nvim) (by Folke Lemaitre) — plugin management and lifecycle engine.
  - [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) — Treesitter highlights, grammar management, and queries.
  - [mason.nvim](https://github.com/williamboman/mason.nvim) & [mason-lspconfig.nvim](https://github.com/williamboman/mason-lspconfig.nvim) (by William Boman) — LSP, DAP, linter, and formatter package management.
  - [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) — standard LSP client configurations.
  - [blink.cmp](https://github.com/Saghen/blink.cmp) (by Saghen) — high-performance autocompletion engine.
  - [friendly-snippets](https://github.com/rafamadriz/friendly-snippets) (by Rafamadriz) — preconfigured snippet collections.
  - [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) & [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) — interactive fuzzy finder and Lua utility libraries.
  - [alpha-nvim](https://github.com/goolord/alpha-nvim) (by Goolord) — fast dashboard and greeting screen.
  - [Harpoon](https://github.com/ThePrimeagen/harpoon) (by ThePrimeagen) — rapid file navigation and marks.

- **Extension Marketplace:**
  - [store.nvim.crawler](https://github.com/alex-popov-tech/store.nvim.crawler) (by Alex Popov) — plugin catalog data powering the Extensions shop.

- **Color Schemes:**
  - [vscode.nvim](https://github.com/Mofiqul/vscode.nvim) (by Mofiqul) — default VS Code Dark Modern theme.
  - [tokyonight.nvim](https://github.com/folke/tokyonight.nvim) (by Folke Lemaitre)
  - [catppuccin](https://github.com/catppuccin/nvim) (by Catppuccin)
  - [gruvbox.nvim](https://github.com/ellisonleao/gruvbox.nvim) (by Ellison Leão)
  - [nord.nvim](https://github.com/shaunsingh/nord.nvim) (by Shaun Singh)
  - [cyberdream.nvim](https://github.com/scottmckendry/cyberdream.nvim) (by Scott McKendry)
  - [rose-pine](https://github.com/rose-pine/neovim) (by Rosé Pine)
  - [kanagawa.nvim](https://github.com/rebelot/kanagawa.nvim) (by Tommaso Cavazza)
  - [nightfox.nvim](https://github.com/EdenEast/nightfox.nvim) (by EdenEast)
  - [matteblack.nvim](https://github.com/tahayvr/matteblack.nvim) (by Taha Yavuz)

- **System Tools & Assets:**
  - [ripgrep](https://github.com/BurntSushi/ripgrep) (by Andrew Gallant) — fast project text searching.
  - [Git](https://git-scm.com/) — version control engine.
  - [Nerd Fonts](https://www.nerdfonts.com/) — developer icons and glyphs.

## License

[MIT](LICENSE).
