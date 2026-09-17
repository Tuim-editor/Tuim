# Plugin Compatibility Guide

Tuim is a **Neovim UI client**, not a traditional terminal shell executing Neovim. Plugins run inside an isolated Neovim instance started with `--clean` and `ext_multigrid` enabled, communicating with Tuim's Zig frontend over MessagePack-RPC.

Understanding this architecture is key to knowing which plugins work seamlessly and which require adaptation.

---

## 1. Verified & Shipped Bundled Plugins

The following core plugins are bundled and verified via `scripts/plugin_smoke.sh` and continuous integration:

| Plugin | Verified Role | Notes |
| :--- | :--- | :--- |
| **lazy.nvim** | Plugin lifecycle manager | Automatically bootstrapped. Provides update and sync tools. |
| **nvim-treesitter** | Syntax highlighting & queries | Pinned version; includes 19 precompiled parsers. |
| **mason.nvim** | LSP/DAP/Linter package manager | Registry UI and tool installer. |
| **nvim-lspconfig** | LSP client configurations | Preconfigured client hooks. |
| **blink.cmp** | High-performance completion | Fast popup completion with snippet expansion. |
| **telescope.nvim** | Fuzzy picker & finder | Adapted for Tuim multigrid floating window hooks. |
| **alpha-nvim** | Dashboard UI | Fast dashboard module. |
| **harpoon** | Quick file bookmarks | Mark and jump module. |

---

## 2. Compatible Plugin Categories

Plugins that interact with standard Neovim abstractions generally work out of the box:
* **Buffer & Window Tools**: Formatting tools, linters, comment helpers, text objects, surround plugins (`mini.surround`, `nvim-surround`).
* **LSP & Code Intelligence**: Diagnostic highlighters, signature helpers, code action popups, refactoring engines.
* **Treesitter Extensions**: Context highlighters, text object motions, indentation guides.
* **Floating Window Pickers**: Pickers rendered via standard Neovim floating windows (`nvim_open_win`).
* **Themes & Colorschemes**: Pure Vim/Lua colorschemes that define highlight groups.

---

## 3. Incompatible & Unsupported Plugin Categories

Because Tuim owns the terminal frontend and renders over MessagePack-RPC, the following plugin types are unsupported unless specifically adapted:

| Incompatible Type | Why It Fails |
| :--- | :--- |
| **GUI-Specific Plugins** | Plugins requiring Neovide (`vim.g.neovide`), Goneovim, or VimR APIs. |
| **Direct Terminal Escape Sequences** | Terminal image viewers (Kitty graphics, Sixel, iTerm2 image protocol) that write escape codes directly to `stdout`. In Tuim, Neovim's stdout is the MessagePack-RPC socket. |
| **Terminal Hijackers** | Plugins that attempt to put the outer terminal into raw mode or replace the outer terminal screen. |
| **External Window Manipulators** | Plugins that assume control of outer `tmux` panes or window managers rather than Neovim splits. |
| **System Configuration Polluters** | Plugins that insist on reading or modifying `~/.config/nvim`. Tuim strictly uses `NVIM_APPNAME=tuim`. |

---

## 4. How to Test a New Plugin

When testing a plugin from the marketplace:
1. Search and install the plugin from **Extensions** → **Discover**.
2. Restart Tuim.
3. If the plugin fails or causes an error on boot, start in **Recovery Mode**:
   ```bash
   TUIM_DISABLE_PLUGINS=1 tuim
   ```
4. Open **Extensions** → **Installed**, highlight the plugin, and press <kbd>d</kbd> to disable or <kbd>u</kbd> to uninstall.
