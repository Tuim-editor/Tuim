# Custom Plugin Configuration

In Tuim, every plugin—whether bundled or installed from the marketplace—can have its options and setup behavior customized via individual Lua configuration files.

---

## 1. Where Configuration Files Live

Custom plugin configuration files are stored under:
```
~/.local/share/tuim/plugin_configs/<owner>_<repo>.lua
```

For instance, configuring `nvim-telescope/telescope.nvim` uses:
```
~/.local/share/tuim/plugin_configs/nvim-telescope_telescope.nvim.lua
```

> [!TIP]
> You do not need to create these paths manually! Open **Extensions**, highlight any plugin, and press <kbd>e</kbd> to open its configuration override directly in the editor. Tuim handles the exact filename mapping automatically.

---

## 2. Specification Format: lazy.nvim Overrides

Each configuration file returns a Lua table conforming to the [lazy.nvim plugin specification](https://lazy.folke.io/spec).

### Overriding Options (`opts`)

If a plugin supports automatic setup, pass options through `opts`:

```lua
return {
  opts = {
    defaults = {
      file_ignore_patterns = { "%.git/", "zig%-cache/" },
      mappings = {
        i = {
          ["<C-j>"] = "move_selection_next",
          ["<C-k>"] = "move_selection_previous",
        },
      },
    },
  },
}
```

### Overriding Setup Logic (`config`)

If you want complete control over how the plugin is initialized, define an explicit `config` function:

```lua
return {
  config = function(plugin, opts)
    -- Require the plugin's documented Lua module
    local lualine = require("lualine")
    
    lualine.setup({
      options = {
        theme = "auto",
        section_separators = "",
        component_separators = "",
      },
    })
  end,
}
```

> [!IMPORTANT]
> When you provide an explicit `config` function, it completely replaces Tuim's default initialization for that plugin. Repository sources, dependencies, and enabled/disabled states remain managed by Tuim.

---

## 3. Configuration Safety & Error Handling

* **Syntax & Runtime Errors**: If your custom Lua file contains a syntax error or calls a missing module, Tuim will not crash. Instead, the error is caught, logged, and surfaced as an in-app notice, and the editor proceeds to load.
* **Preservation on Uninstall**: If you uninstall a plugin from the Extensions manager, its `.lua` configuration file is intentionally **kept safe** on disk. If you reinstall the plugin later, your configuration is immediately restored.

---

## Next Steps

If a broken configuration prevents Tuim from starting properly, check out **[Recovery Mode](../troubleshooting/Recovery-Mode.md)**.
