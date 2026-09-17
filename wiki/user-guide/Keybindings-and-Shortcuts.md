# Keybindings & Shortcuts

Tuim features a dual-layer keyboard system:
1. **TUI Interface Layer**: Global hotkeys handled directly by Tuim's Zig frontend (panel toggling, region switching, commands, Zen mode).
2. **Editor Layer**: Text editing mappings handled by the Neovim engine (Vim motions in Normal mode, standard editing keys in IDE mode).

All core TUI shortcuts can be fully customized with an interactive key recorder.

---

## 1. Global TUI Interface Keybindings

These shortcuts are handled by Tuim regardless of the current editor state:

| Action | Default Keybinding | Alternative / Mouse |
| :--- | :--- | :--- |
| **Search Commands** | <kbd>F1</kbd> | Click `[Commands F1]` in header |
| **Toggle Sidebar** | <kbd>Ctrl+E</kbd> | Click `< Workspace` or sidebar icon |
| **Toggle Terminal Panel** | <kbd>Ctrl+T</kbd> | Click terminal status item |
| **Cycle Next Region** | <kbd>F6</kbd> | Direct mouse click on target panel |
| **Cycle Previous Region**| <kbd>Shift+F6</kbd>| Direct mouse click on target panel |
| **Toggle Zen Mode** | <kbd>F11</kbd> | Click footer mode return button |
| **Report a Bug** | <kbd>F12</kbd> (IDE mode) | <kbd>F1</kbd> → **Report bug** |
| **Resize Panel Left** | <kbd>Alt+←</kbd> | Drag split border with mouse |
| **Resize Panel Right** | <kbd>Alt+→</kbd> | Drag split border with mouse |
| **Resize Panel Up** | <kbd>Alt+↑</kbd> | Drag split border with mouse |
| **Resize Panel Down** | <kbd>Alt+↓</kbd> | Drag split border with mouse |

---

## 2. Editor Keybindings (Normal Mode)

When using **Normal Mode**, `<Space>` acts as the leader key:

| Category | Shortcut | Description |
| :--- | :--- | :--- |
| **File Operations** | <kbd>Ctrl+S</kbd> | Save current buffer (prompts for name on new buffer) |
| | <kbd>Ctrl+N</kbd> | Create new empty buffer |
| | <kbd>Ctrl+Q</kbd> | Quit Tuim (with unsaved changes prompt) |
| **Project Search** | <kbd>Ctrl+P</kbd> or `<Space> f f` | Fuzzy find files across project (Telescope) |
| | <kbd>Alt+G</kbd> or `<Space> f g` | Search text across project with ripgrep |
| **Splits & Windows**| <kbd>Ctrl+W s</kbd> | Horizontal editor split |
| | <kbd>Ctrl+W v</kbd> | Vertical editor split |
| | <kbd>Ctrl+W h/j/k/l</kbd> | Move focus between splits (left/down/up/right) |
| | <kbd>Ctrl+W q</kbd> | Close active editor split |
| **Vim Enhancements**| `<Space> d` | Delete text without replacing the default yank buffer |
| | `<Space> s` | Search and replace word under cursor on current line |
| | `<Space> p` (Visual) | Paste over selection without clobbering register |
| | <kbd>K</kbd> / <kbd>J</kbd> (Visual) | Move selected lines up / down |
| | <kbd>Ctrl+D</kbd> / <kbd>Ctrl+U</kbd> | Scroll half page down / up (keeps cursor centered) |

---

## 3. Editor Keybindings (IDE Mode)

In **IDE Mode**, standard desktop editing shortcuts apply to all editable text buffers:

| Action | Shortcut (Linux / Windows) | Shortcut (macOS) |
| :--- | :--- | :--- |
| **Save** | <kbd>Ctrl+S</kbd> | <kbd>Cmd+S</kbd> |
| **Undo** | <kbd>Ctrl+Z</kbd> | <kbd>Cmd+Z</kbd> |
| **Redo** | <kbd>Ctrl+Y</kbd> or <kbd>Ctrl+Shift+Z</kbd> | <kbd>Cmd+Shift+Z</kbd> |
| **Cut** | <kbd>Ctrl+X</kbd> | <kbd>Cmd+X</kbd> |
| **Copy** | <kbd>Ctrl+C</kbd> | <kbd>Cmd+C</kbd> |
| **Paste** | <kbd>Ctrl+V</kbd> | <kbd>Cmd+V</kbd> |
| **Select All** | <kbd>Ctrl+A</kbd> | <kbd>Cmd+A</kbd> |
| **Select Current Line** | <kbd>Ctrl+L</kbd> | <kbd>Ctrl+L</kbd> |
| **Find in Buffer** | <kbd>Ctrl+F</kbd> | <kbd>Cmd+F</kbd> |
| **Replace in Buffer** | <kbd>Ctrl+H</kbd> | <kbd>Cmd+R</kbd> |
| **Select by Character** | <kbd>Shift+←</kbd> / <kbd>Shift+→</kbd> | <kbd>Shift+←</kbd> / <kbd>Shift+→</kbd> |
| **Select by Word** | <kbd>Ctrl+Shift+←</kbd> / <kbd>→</kbd> | <kbd>Cmd+Shift+←</kbd> / <kbd>→</kbd> |

---

## 4. Customizing Shortcuts

Tuim provides an interactive shortcut customization panel:
1. Open the command menu (<kbd>F1</kbd>) and choose **Settings** → **Keyboard shortcuts**.
2. Press <kbd>→</kbd> to enter the actions list.
3. Select an action and press <kbd>Enter</kbd> to enter **Record Mode**.
4. Press the key combination you wish to bind (function keys, Ctrl, Alt, or modifier combos).
5. Conflicting keybindings are automatically detected and rejected.
6. Press <kbd>r</kbd> to reset the selected action to its default, or press <kbd>Ctrl+S</kbd> to save.

### Built-in Keyboard Presets

Inside the Keyboard Shortcuts settings panel, you can switch between preset profiles with a single keypress:

* Press <kbd>v</kbd> for the **Vim-Safe Preset**:
  Moves workspace controls from `Ctrl` keys to `Alt` keys so they do not conflict with Neovim's terminal motions or insert-mode completion:
  * <kbd>Alt+E</kbd>: Sidebar toggle
  * <kbd>Alt+T</kbd>: Terminal toggle
  * <kbd>Alt+N</kbd>: New file
  * <kbd>Alt+P</kbd>: Find file
  * <kbd>Alt+G</kbd>: Search project text
* Press <kbd>p</kbd> for the **IDE Preset**:
  * <kbd>Ctrl+B</kbd>: Sidebar toggle
  * <kbd>Ctrl+T</kbd>: Terminal toggle
  * <kbd>Ctrl+N</kbd>: New file
  * <kbd>Ctrl+P</kbd>: Find file

### Assigning Shortcuts from the Command Palette

You can also assign a shortcut directly from the <kbd>F1</kbd> command menu:
1. Press <kbd>F1</kbd> to open the command palette.
2. Highlight any command.
3. Press <kbd>F2</kbd> (or click the shortcut column).
4. Press the desired key combination to bind it instantly.

---

## Next Steps

Explore file operations, buffers, and project searching in **[File & Buffer Management](File-and-Buffer-Management.md)**.
