# Configuration Directories

Tuim adheres strictly to the **XDG Base Directory Specification**. It isolates all of its configuration files, plugins, compiled grammars, session state, and caches in dedicated `tuim` subdirectories, ensuring it never collides with or modifies your primary Neovim installation.

---

## 1. Directory Structure Overview

| Standard Path | Environment Variable | Contents |
| :--- | :--- | :--- |
| `~/.config/tuim` | `$XDG_CONFIG_HOME/tuim` | User-defined configuration files. |
| `~/.local/share/tuim` | `$XDG_DATA_HOME/tuim` | Application settings (`settings.json`), active log (`tuim.log`), session files (`tuim_session.vim`, `tuim_handoff_init.lua`), installed plugins (`lazy/`), Treesitter parsers (`site/`), plugin overrides (`plugin_configs/`), marketplace records, and release runtime. |
| `~/.local/state/tuim` | `$XDG_STATE_HOME/tuim` | Runtime state directory checked by desktop themes and targeted by uninstaller cleanups (`uninstall.sh --logs --sessions`). |
| `~/.cache/tuim` | `$XDG_CACHE_HOME/tuim` | Build caches, font symbol caches, and temporary artifacts. |

If custom XDG environment variables (`$XDG_CONFIG_HOME`, `$XDG_DATA_HOME`, etc.) are set in your environment, Tuim respects them.

---

## 2. Key Files in the Data Directory

The `~/.local/share/tuim` directory is where Tuim persists your application state and plugin infrastructure:

```
~/.local/share/tuim/
├── tuim.log                 # Active runtime log file
├── settings.json            # Native application preferences (theme, rulers, keybindings)
├── tuim_session.vim         # Saved editor session state
├── tuim_handoff_init.lua    # Zen mode session handoff script
├── user_plugins.json        # Marketplace plugin list
├── plugin_states.json       # Record of enabled, disabled, and removed plugins
├── plugin_inventory.json    # Auto-generated bundled and runtime plugin inventory
├── plugin_configs/          # Custom Lua spec overrides (<owner>_<repo>.lua)
├── lazy/                    # Directory where lazy.nvim clones installed plugins
├── site/                    # Compiled Tree-sitter parsers and queries
├── tools/                   # Private runtime tools (e.g. private Tree-sitter CLI)
└── nvim/                    # Bundled Neovim runtime assets (on release installs)
```

---

## 3. Total Isolation from System Neovim

Tuim invokes Neovim processes with:
```bash
NVIM_APPNAME=tuim nvim --clean ...
```

**Why this matters:**
* Tuim does **not** load `~/.config/nvim/init.lua` or `init.vim`.
* Tuim does **not** install or tamper with plugins in `~/.local/share/nvim`.
* You can run your existing, customized Neovim setup alongside Tuim without any risk of configuration pollution or version conflicts.

---

## 4. Viewing Active Paths at Runtime

To inspect the exact paths being used by your running Tuim instance:
1. Press <kbd>F1</kbd> to open the command menu.
2. Select **Settings** → **About**.
3. The panel displays the active configuration path, data directory, and the exact file path of the runtime log.

---

## Next Steps

Learn how to configure themes, rulers, and shortcuts via the UI in **[Settings UI](Settings-UI.md)**.
