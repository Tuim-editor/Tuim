# Keybindings Cheat Sheet

A comprehensive, printable reference of all keyboard shortcuts available in Tuim across all contexts and editing modes.

---

## 1. Global TUI Interface Controls

| Action | Default Shortcut | Vim-Safe Preset | IDE Preset |
| :--- | :--- | :--- | :--- |
| **Command Palette** | <kbd>F1</kbd> | <kbd>F1</kbd> | <kbd>F1</kbd> |
| **Cycle Next Region** | <kbd>F6</kbd> | <kbd>F6</kbd> | <kbd>F6</kbd> |
| **Cycle Previous Region**| <kbd>Shift+F6</kbd> | <kbd>Shift+F6</kbd> | <kbd>Shift+F6</kbd> |
| **Toggle Sidebar** | <kbd>Ctrl+E</kbd> | <kbd>Alt+E</kbd> | <kbd>Ctrl+B</kbd> |
| **Toggle Terminal Panel**| <kbd>Ctrl+T</kbd> | <kbd>Alt+T</kbd> | <kbd>Ctrl+T</kbd> |
| **Toggle Zen Mode** | <kbd>F11</kbd> | <kbd>F11</kbd> | <kbd>F11</kbd> |
| **Resize Panel Left** | <kbd>Alt+←</kbd> | <kbd>Alt+←</kbd> | <kbd>Alt+←</kbd> |
| **Resize Panel Right**| <kbd>Alt+→</kbd> | <kbd>Alt+→</kbd> | <kbd>Alt+→</kbd> |
| **Resize Panel Up** | <kbd>Alt+↑</kbd> | <kbd>Alt+↑</kbd> | <kbd>Alt+↑</kbd> |
| **Resize Panel Down** | <kbd>Alt+↓</kbd> | <kbd>Alt+↓</kbd> | <kbd>Alt+↓</kbd> |

---

## 2. Editor Controls (Normal Mode, Leader = `<Space>`)

| Action | Shortcut |
| :--- | :--- |
| **Save Buffer** | <kbd>Ctrl+S</kbd> |
| **New Buffer** | <kbd>Ctrl+N</kbd> (in editor) |
| **Quit Tuim** | <kbd>Ctrl+Q</kbd> |
| **Find File (Telescope)** | <kbd>Ctrl+P</kbd> or `<Space> f f` |
| **Search Project Text (Ripgrep)** | <kbd>Alt+G</kbd> or `<Space> f g` |
| **Horizontal Split** | <kbd>Ctrl+W s</kbd> |
| **Vertical Split** | <kbd>Ctrl+W v</kbd> |
| **Move Between Splits** | <kbd>Ctrl+W h/j/k/l</kbd> |
| **Close Split** | <kbd>Ctrl+W q</kbd> |
| **Delete Without Yanking** | `<Space> d` |
| **Substitute Word (Current Line)** | `<Space> s` |
| **Paste Over Selection** | `<Space> p` (Visual) |
| **Move Lines Up / Down** | <kbd>K</kbd> / <kbd>J</kbd> (Visual) |
| **Scroll Half Page (Centered)** | <kbd>Ctrl+D</kbd> / <kbd>Ctrl+U</kbd> |

---

## 3. Editor Controls (IDE Mode)

| Action | Linux / Windows | macOS |
| :--- | :--- | :--- |
| **Save** | <kbd>Ctrl+S</kbd> | <kbd>Cmd+S</kbd> |
| **Undo** | <kbd>Ctrl+Z</kbd> | <kbd>Cmd+Z</kbd> |
| **Redo** | <kbd>Ctrl+Y</kbd> / <kbd>Ctrl+Shift+Z</kbd> | <kbd>Cmd+Shift+Z</kbd> |
| **Cut** | <kbd>Ctrl+X</kbd> | <kbd>Cmd+X</kbd> |
| **Copy** | <kbd>Ctrl+C</kbd> | <kbd>Cmd+C</kbd> |
| **Paste** | <kbd>Ctrl+V</kbd> | <kbd>Cmd+V</kbd> |
| **Select All** | <kbd>Ctrl+A</kbd> | <kbd>Cmd+A</kbd> |
| **Select Current Line** | <kbd>Ctrl+L</kbd> | <kbd>Ctrl+L</kbd> |
| **Find in Buffer** | <kbd>Ctrl+F</kbd> | <kbd>Cmd+F</kbd> |
| **Replace in Buffer** | <kbd>Ctrl+H</kbd> | <kbd>Cmd+R</kbd> |
| **Select by Character** | <kbd>Shift+←</kbd> / <kbd>→</kbd> | <kbd>Shift+←</kbd> / <kbd>→</kbd> |
| **Select by Word** | <kbd>Ctrl+Shift+←</kbd> / <kbd>→</kbd> | <kbd>Cmd+Shift+←</kbd> / <kbd>→</kbd> |

---

## 4. Integrated Terminal Controls

| Action | Shortcut |
| :--- | :--- |
| **Enter Scrollback Mode** | <kbd>Ctrl+\</kbd> followed by <kbd>Ctrl+N</kbd> |
| **Scrollback Navigation** | <kbd>h</kbd>, <kbd>j</kbd>, <kbd>k</kbd>, <kbd>l</kbd>, <kbd>Ctrl+U</kbd>, <kbd>Ctrl+D</kbd>, <kbd>gg</kbd>, <kbd>G</kbd> |
| **Select Text** | <kbd>v</kbd> (char), <kbd>V</kbd> (line), <kbd>Ctrl+V</kbd> (block) |
| **Copy Selected Text** | <kbd>y</kbd> |
| **Resume Shell Input** | <kbd>i</kbd> or <kbd>a</kbd> |
| **Vertical Terminal Split** | <kbd>Alt+V</kbd> (when terminal is focused) |
| **Horizontal Terminal Split** | <kbd>Alt+S</kbd> (when terminal is focused) |
| **Close Terminal Split** | <kbd>Alt+C</kbd> (when terminal is focused) |
| **Cycle Terminal Splits** | <kbd>Alt+O</kbd> (when terminal is focused) |
| **Navigate Splits / Editor** | <kbd>Alt+H</kbd>, <kbd>Alt+J</kbd>, <kbd>Alt+K</kbd>, <kbd>Alt+L</kbd> |

---

## 5. Extensions Workspace Controls

| Action | Shortcut |
| :--- | :--- |
| **Installed View** | <kbd>1</kbd> |
| **Discover View** | <kbd>2</kbd> |
| **Toggle Tabs** | <kbd>Tab</kbd> |
| **Cycle Categories** | <kbd>c</kbd> |
| **Search Plugins** | <kbd>/</kbd> |
| **Refresh Catalog** | <kbd>r</kbd> |
| **Edit Lua Config** | <kbd>e</kbd> |
| **Enable / Disable Plugin** | <kbd>d</kbd> |
| **Uninstall Plugin** | <kbd>u</kbd> (then <kbd>y</kbd>) |
| **Install / Details** | <kbd>Enter</kbd> |

---

## 6. Git Panel Controls

| Action | Shortcut |
| :--- | :--- |
| **Navigate Changes** | <kbd>↑</kbd> / <kbd>↓</kbd> or <kbd>j</kbd> / <kbd>k</kbd> |
| **Open Changed File** | <kbd>Enter</kbd> |
| **Toggle Stage / Unstage** | <kbd>Space</kbd> |
| **Stage File** | <kbd>s</kbd> or <kbd>+</kbd> |
| **Unstage File** | <kbd>u</kbd> or <kbd>-</kbd> |
| **Compose Commit** | <kbd>c</kbd> (then type message + <kbd>Enter</kbd>) |
| **Cancel / Return** | <kbd>Esc</kbd> |
