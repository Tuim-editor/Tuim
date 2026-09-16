# Using Tuim

[Back to the README](../README.md)

## Workspace basics

TUIM opens with Explorer visible by default. Click **< Workspace** above it to
reach the open-files and tools list.

Normal and IDE use one compact workspace sidebar for open files and tools, with
the current file in the editor header. `F1` opens a searchable command menu;
`F6` and `Shift+F6` move between the editor, sidebar, and terminal. In the
sidebar, use arrows or `j`/`k` and Enter, or click an item. Escape returns from
a tool to the workspace list, then to the editor. At widths below 40 columns,
the sidebar collapses automatically and commands remain available through F1.

Zen hides the sidebar and terminal panel and focuses the editor. Leaving Zen
restores the previous sidebar/terminal focus and keeps the existing terminal
session alive. Its quiet footer provides a clickable return action. Normal's
footer displays Neovim's current editing mode; IDE uses the same design with
an IDE badge and modeless editing.

Terminal scrollback uses Neovim's terminal-normal and Visual modes in both
Normal and IDE workspaces. With the terminal focused, press `Ctrl+\`, then
`Ctrl+N`; move with Vim motions, start a selection with `v`, `V`, or `Ctrl+V`,
and press `y` to copy it. Press `i` or `a` to resume shell input. A left-button
drag selects text the same way, while a click still focuses the live prompt and
the wheel keeps scrolling. If a program has enabled terminal mouse reporting,
Neovim forwards mouse events to that program; use the keyboard route to select
its scrollback. Yanking uses the system clipboard when Neovim can find a
clipboard provider.

To create a file, press **Ctrl+N** and start typing (press `i` first in Normal
mode). When the terminal is focused, use **F1 > New file** or focus the editor
first because `Ctrl+N` belongs to Neovim's terminal mode there. On the first
**Ctrl+S**, enter a filename such as `notes.txt` and press
**Enter**. Relative paths are saved in the current working directory. **Esc**
cancels naming without discarding your text. Later saves use the same name.

In the Git sidebar, use **Up/Down** or **j/k** to select a change, **Enter** to
open it, and **Space** to stage or unstage it. **s/+** stages and **u/-** unstages.
**Home/End** jumps to the first/last change. Press **c** to write a commit message,
then **Enter** to commit or **Esc** to return to the list.

## AI assistants

Open **AI assistants** from the workspace list. Select the assistant name to
change it; the chooser shows which CLIs are installed and which chats are
running. Choose an assistant, then **Open chat** and type your request in its
terminal. Install missing assistant CLIs in your terminal and restart Tuim to
refresh detection.

In the AI sidebar, **Up/Down** or **Tab/Shift+Tab** selects an item and **Enter**
activates it. Click a row or its description for the same action. **Escape**
cancels the assistant chooser; from the main AI panel it returns to Workspace.
Use **F6** to move between regions.

With a chat running, **Send selection** and **Send file** paste code into that
chat for you to use in your next request. **Review changes** sends a request to
review the working-tree diff. **Return to chat** resumes typing, **Stop chat**
ends the process, and **Restart chat** starts a fresh session. Actions only
apply to the assistant whose chat is currently open.

## First run

On its first launch, Tuim explains how to open, edit, and save a file, with
plain-language choices for IDE and Normal (Vim) editing. Press `i` or `n` to
choose a style and start editing. Optional language-server setup is available
with `l`, which opens Tuim's built-in package manager on the LSP tab. Close the guide with Enter, Escape, `q`, Ctrl+C, or by clicking
**Click to close guide** at the top. Closing keeps Tuim open and preserves your current
editing style. Reopen it from the Help page by pressing `o`, or run
`:TuimOnboarding` in Normal mode. The choice and completion marker are stored
only in Tuim's isolated data directory.

## Default Keybindings

### TUI Interface Controls

These keybindings are handled directly by the Tuim TUI layer:

| Action | Keybinding |
| :--- | :--- |
| **Toggle Zen / previous mode** | `F11` |
| **Search commands** | `F1` or click Commands in the header |
| **Next / previous region** | `F6` / `Shift + F6` |
| **Report a bug** | Commands → Report bug (`F12` also in IDE mode) |
| **Toggle workspace sidebar** | `Ctrl + E` |
| **Toggle Terminal Panel** | `Ctrl + T` |
| **Resize Panel Left** | `Alt + ←` |
| **Resize Panel Right** | `Alt + →` |
| **Resize Panel Up** | `Alt + ↑` |
| **Resize Panel Down** | `Alt + ↓` |

### Neovim / Editor Keybindings

These shipped mappings apply primarily in Normal mode (`Leader = Space`). IDE mode intentionally changes editing behavior.

| Action | Keybinding |
| :--- | :--- |
| **Save file** | `Ctrl + S` |
| **Force quit Tuim** | `Ctrl + Q` |
| **Open new buffer** | `Ctrl + N` |
| **Find files (Telescope, with a filename prompt when plugins are unavailable)** | `Space f f` or `Ctrl + P` |
| **Search project text with ripgrep (Telescope)** | `Space f g` or `Alt + G` |
| **Toggle Neo-tree** | `Space e` |
| **Toggle bottom terminal split** | `Space o t` |
| **Toggle vertical terminal split** | `Space o Shift+T` |
| **Create horizontal editor split** | `Ctrl + W`, then `S` |
| **Create vertical editor split** | `Ctrl + W`, then `V` |
| **Move between editor splits** | `Ctrl + W`, then `H`, `J`, `K`, or `L` |
| **Close current editor split** | `Ctrl + W`, then `Q` |
| **Open editor settings** | `Space t h` |
| **Delete without yanking** | `Space d` |
| **Substitute word everywhere** | `Space s` |
| **Paste over selection** | `Space p` (Visual) |
| **Scroll half page down (centered)** | `Ctrl + D` |
| **Scroll half page up (centered)** | `Ctrl + U` |
| **Move lines down** | `J` (Visual) |
| **Move lines up** | `K` (Visual) |

> [!NOTE]
> Core TUI keybindings can be customized in native Settings. Open F1 → Keyboard
> shortcuts, press Right to enter the list, select an action, and press Enter to
> record a key. Duplicate bindings are rejected. Press `r` to reset the selected
> action and `Ctrl+S` to save and close. Existing saved bindings are preserved,
> including an older Ctrl+F mapping for finding files.

In the F1 command menu, select any command and press `F2`, or click its
shortcut column, to assign or replace its shortcut. Press a Ctrl/Alt combination
or function key to save immediately; Escape cancels. Conflicting shortcuts are
rejected. The **Command menu** entry lets you change the F1 binding itself.
**Close buffer** closes the current buffer and asks before discarding unsaved
changes. **Switch buffers** opens a searchable list of open buffers, including
paths and current/modified indicators. Use arrows and Enter, or click a result;
Escape returns to the command menu. Both buffer commands start without a
shortcut so you can assign your preferred keys. The buffer list works without
plugins, including in Zen and narrow terminals.

The shortcut editor also offers `v` for a Vim-safe preset (Alt+E sidebar,
Alt+T terminal, Alt+N new file, Alt+P files, Alt+G project search) and `p` for a familiar IDE preset
(Ctrl+B sidebar, Ctrl+T terminal, Ctrl+N new file, Ctrl+P files). Both use
Ctrl+S to save, F1 for commands, F6 for region focus, and F11 for Zen. Presets
replace the core bindings only when selected; save with Ctrl+S. Neovim's leader
mappings and editor configuration remain available independently. Shell bindings
take precedence, so use the Vim-safe preset to keep Neovim's Ctrl-key motions
and completion commands. While Telescope is open, its local shortcuts take
precedence: Ctrl+N/P moves through results, Enter opens, Tab marks, Alt+P toggles
the preview, and Escape closes in one press. The command-menu and Zen shortcuts
close the picker before changing context. Pickers share a top search prompt,
filename-first results, thin theme-aware borders, and a preview that hides in
narrow windows. The footer also exposes mouse actions.

In IDE mode, Shift+Arrow extends the selection, Ctrl/Cmd+Shift+Left or Right
selects by word, and Ctrl/Cmd+A selects the buffer. Ctrl/Cmd+S, Z, C, X, and V
provide save, undo, copy, cut, and paste; Ctrl+Y or Ctrl/Cmd+Shift+Z redoes.
Ctrl+L selects the current line. Ctrl/Cmd+F opens buffer search and Ctrl+H
(Cmd+R on terminals that report it) opens replace. Home, End, Ctrl+Arrow, mouse
click, and mouse drag use Neovim's terminal-native navigation and selection.
Some terminals cannot distinguish Cmd from Alt or report shifted modifiers;
Tuim keeps the Ctrl form available and uses the terminal capability fallback.
Use the command menu and editor context menu when a terminal does not report
a shortcut distinctly.
Escape and incidental mode changes return editable file buffers to text-entry
mode. Dialogs, terminals, help pages, and plugin-owned utility buffers keep
their native keys and modes so their own escape routes continue to work.

The Editor tab in Settings controls the optional column ruler. It defaults to
Off and provides validated presets for columns 80, 100, 120, and `80,120`.
Changes apply immediately to current and new file windows. Dashboards,
terminals, help, settings, and other non-file buffers never show the ruler.

In Settings > Appearance > Theme, **System (follow desktop)** follows the
current Omarchy palette for editor, syntax, sidebar, and selection colors.
It reads `omarchy/current/theme/colors.toml` under `XDG_STATE_HOME` (normally
`~/.local/state`), with the older `XDG_CONFIG_HOME` location as a fallback.
Changes apply automatically while Tuim is open. The option needs no theme
plugin and keeps `system` as the saved preference. If the palette is missing
or invalid at startup, Tuim reports that it is using default colors and keeps
watching for a valid palette. Choosing another theme stops following the desktop.

### Extensions

Open **Extensions** from the workspace or the F1 command menu. It opens directly
to **Installed**, your offline library of bundled plugins, dependencies,
marketplace additions, and local plugin directories. Switch to **Discover** to
browse the marketplace; choose categories in the sidebar.

The panel shows a searchable plugin list and, on wide terminals, the selected
plugin's details and actions alongside it. Compact terminals open details with
Enter or a click. Use `1` for Installed, `2` for Discover, Tab to switch views,
`c` to cycle discovery categories, `/` to search, and `r` to refresh. Up/Down
select plugins. Settings > Plugins > Installed Plugins opens this same panel.

![Extensions with installed plugins and inline controls](screenshots/extensions.webp)

| Detail action | Key |
| --- | --- |
| Edit configuration | `e` |
| Enable / disable | `d` |
| Uninstall | `u`, then `y` to confirm or `n` to cancel |
| Install / reinstall | Enter |
| Return to list (compact), or return to editor | Escape |

Restart Tuim to apply installation, activation, and removal changes. Disabled
plugins remain on disk. Uninstall removes only the selected plugin on the next
normal startup and preserves its configuration for reinstallation. Dependencies
required by enabled plugins must be kept; disable their dependents first.
Tuim's plugin manager and unmanaged local directories are protected.

Configuration opens as a Lua file under `$XDG_DATA_HOME/tuim/plugin_configs/`
(default `~/.local/share/tuim/plugin_configs/`). Save it and restart. Return a
[lazy.nvim spec override](https://lazy.folke.io/spec), for example:

```lua
return {
  opts = { -- options passed to plugins using automatic setup
    -- plugin-specific values here
  },
}
```

For bundled plugins with a custom setup function, override `config` explicitly:

```lua
return {
  config = function(plugin, opts)
    require("plugin_module").setup(opts or {}) -- use the plugin's documented module
  end,
}
```

An explicit `config` replaces Tuim's setup for that plugin. Repository identity,
dependencies, and enable/disable state stay under the manager's control. Invalid
configuration is reported without aborting the editor. Recovery mode
(`TUIM_DISABLE_PLUGINS=1 tuim`) skips user config execution so you can repair it.
**Settings > Plugins > Plugin Manager** retains Lazy's update and sync tools;
**Mason Settings** manages language servers and formatters separately.

### Language Tools

Tuim detects common project markers for Zig, Lua, Python, Rust,
JavaScript/TypeScript, Go, and C/C++, then recommends only the matching Mason
language servers. Projects without recognized markers remain manual rather
than installing unrelated tools. Open **Workspace > Language tools**, or choose
**Language tools** from the F1 command menu, for the health summary, active
servers, recommended packages, missing executables, and installed
LSP/formatter/linter status. **Settings > Plugins > Mason Settings** opens the
same panel. Missing or failed tooling is also reported through native notices
with details in the Tuim log.

### Accessibility and Terminal Fallbacks

All primary controls are keyboard accessible; sidebar lists show their
navigation keys and focused controls use both color and a visible marker or
inverse background. Tuim supplies text-symbol alternatives when Nerd Fonts are
disabled and keeps keyboard routes available when mouse reporting is absent.
Dialogs show explicit empty, loading, success, and error messages, and compact
terminals receive a resize instruction instead of clipped or unsafe layouts.
The default theme is regression-tested for readable primary, secondary,
status-bar, and focused-control contrast.
