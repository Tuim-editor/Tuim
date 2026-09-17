# Extensions & Plugins

Tuim provides a dedicated **Extensions** workspace that manages Neovim plugins, marketplace additions, and configuration overrides entirely through the native terminal interface.

---

## 1. Opening Extensions

* From the sidebar: Select **Extensions** in the workspace list.
* From Command Palette: Press <kbd>F1</kbd> → **Extensions**.
* From Settings: Open <kbd>F1</kbd> → **Settings** → **Plugins** → **Installed Plugins**.

The Extensions interface features two main tabs:
1. **Installed**: Your local, offline library of bundled plugins, dependencies, user additions, and local plugin directories.
2. **Discover**: An interactive marketplace to search and explore plugins across curated categories.

---

## 2. Navigating the Extensions Workspace

| Key | Action |
| :--- | :--- |
| <kbd>1</kbd> | Switch to **Installed** tab |
| <kbd>2</kbd> | Switch to **Discover** tab |
| <kbd>Tab</kbd> | Toggle between Installed and Discover |
| <kbd>c</kbd> | Cycle through Discover categories (LSP, Themes, Tools, Git, etc.) |
| <kbd>/</kbd> | Open search bar to filter plugins by name or keyword |
| <kbd>r</kbd> | Refresh plugin catalog |
| <kbd>↑</kbd> / <kbd>↓</kbd> | Select plugin from the list |
| <kbd>Enter</kbd> | Open plugin details (compact terminals) or Install uninstalled plugin |
| <kbd>Esc</kbd> | Return to plugin list, or close Extensions and return to editor |

> [!NOTE]
> On wide terminal screens, the plugin list and detail pane are shown side by side. In compact terminals, selecting a plugin displays a dedicated details view with an <kbd>Esc</kbd> key to return to the list.

---

## 3. Plugin Actions & Lifecycle

When a plugin is selected, you can trigger actions using single keystrokes:

| Key | Action | What Happens |
| :--- | :--- | :--- |
| <kbd>e</kbd> | **Edit Config** | Opens the plugin's Lua configuration spec file in the editor. |
| <kbd>d</kbd> | **Enable / Disable** | Toggles the plugin's active status. Disabled plugins remain stored on disk. |
| <kbd>u</kbd> | **Uninstall** | Marks the plugin for removal upon next restart. Prompts <kbd>y</kbd> to confirm. |
| <kbd>Enter</kbd>| **Install** | Downloads and registers a new plugin from the marketplace. |

> [!IMPORTANT]
> **Restart Required**: Plugin installation, removal, and enable/disable state changes are applied when Tuim restarts.
> **Configuration Safety**: When uninstalling a plugin, its configuration file is preserved under `~/.local/share/tuim/plugin_configs/`. If you reinstall the plugin later, your configuration is restored automatically.
> **Dependency Protection**: Core plugins bundled with Tuim (such as `lazy.nvim`, `nvim-treesitter`, and `mason.nvim`) and active dependencies are protected from accidental removal.

---

## 4. Customizing Plugin Specs (Lua Overrides)

When you press <kbd>e</kbd> on any plugin, Tuim opens a dedicated configuration override file located at:
```
~/.local/share/tuim/plugin_configs/<owner>_<repo>.lua
```

This file returns a [lazy.nvim specification table](https://lazy.folke.io/spec).

### Example A: Overriding Options (`opts`)
For plugins that use automatic setup (e.g., `lualine`, `gitsigns`, `mini.nvim`):

```lua
return {
  opts = {
    options = {
      theme = "auto",
      icons_enabled = false,
    },
  },
}
```

### Example B: Custom Setup Function (`config`)
For plugins that require explicit initialization logic:

```lua
return {
  config = function(plugin, opts)
    -- Custom Lua initialization
    require("telescope").setup({
      defaults = {
        layout_strategy = "horizontal",
      },
    })
  end,
}
```

> [!NOTE]
> Supplying an explicit `config` function replaces Tuim's default setup for that specific plugin. Repository sources, branch tracking, and dependency relationships remain managed by Tuim.

---

## 5. Plugin Storage Architecture

Tuim stores all plugin assets under its isolated XDG data directory:

| Path | Purpose |
| :--- | :--- |
| `~/.local/share/tuim/user_plugins.json` | Marketplace additions and user plugin list |
| `~/.local/share/tuim/plugin_states.json` | Desired enabled, disabled, or removed state |
| `~/.local/share/tuim/plugin_configs/` | User Lua spec override files |
| `~/.local/share/tuim/lazy/` | Cloned Git repositories for installed plugins |
| `~/.local/share/tuim/site/` | Compiled Treesitter grammars and query files |

Tuim's plugin tree is 100% separate from your personal `~/.config/nvim` or `~/.local/share/nvim`.

---

## Next Steps

Learn how Treesitter and Mason deliver code intelligence in **[Language Tools & LSP](Language-Tools-and-LSP.md)**.
