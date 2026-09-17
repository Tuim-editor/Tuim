# Editing Modes

Tuim provides **three distinct editing modes** catering to different workflows and experience levels. All three modes share the same high-performance Neovim engine under the hood, but alter how input and shortcuts are handled.

---

## 1. Mode Summary

| Mode | Target User | Key Behavior |
| :--- | :--- | :--- |
| **Normal** | Vim / Neovim users | Traditional modal editing (`Normal`, `Insert`, `Visual`, `Command`). Vim motions, text objects, and `<Space>` as the leader key. |
| **IDE** | VS Code / Sublime users | Modeless editing. Type immediately without pressing `i`. Standard clipboard (<kbd>Ctrl+C</kbd>/<kbd>V</kbd>), undo (<kbd>Ctrl+Z</kbd>), and selection (<kbd>Shift+Arrows</kbd>). |
| **Zen** | Focus & writing | Distraction-free full-screen editor. Hides sidebar and terminal panel. Preserves terminal session and previous mode. |

---

## 2. Normal Mode

**Normal Mode** preserves the full power of Neovim's modal editing:
* **Modal Navigation**: Press <kbd>Esc</kbd> to enter Normal mode, <kbd>i</kbd> for Insert mode, <kbd>v</kbd> / <kbd>V</kbd> / <kbd>Ctrl+V</kbd> for Visual modes.
* **Leader Key**: Shipped with `<Space>` as the leader key.
  * `<Space> f f`: Find files (Telescope)
  * `<Space> f g`: Live grep project text (ripgrep)
  * `<Space> e`: Toggle file tree
  * `<Space> d`: Delete without overwriting yank buffer
  * `<Space> s`: Substitute word under cursor on current line
* **Vim Motions**: Standard motions (`w`, `b`, `e`, `ge`, `0`, `$`, `gg`, `G`, `f`, `t`) and operators (`d`, `c`, `y`, `p`).
* **Editor Splits**: Neovim window splitting via <kbd>Ctrl+W s</kbd> (horizontal) and <kbd>Ctrl+W v</kbd> (vertical).

---

## 3. IDE Mode

**IDE Mode** is designed for developers who want the speed and lightness of a terminal editor without having to memorize Vim modal keys:
* **Modeless Editing**: Editable file buffers are always in insert mode. You can click anywhere and start typing immediately.
* **Standard Text Selection**:
  * <kbd>Shift+←</kbd> / <kbd>Shift+→</kbd>: Select text character by character.
  * <kbd>Ctrl+Shift+←</kbd> / <kbd>Ctrl+Shift+→</kbd> (or Cmd on macOS): Select word by word.
  * <kbd>Shift+↑</kbd> / <kbd>Shift+↓</kbd>: Select line by line.
  * <kbd>Ctrl+A</kbd>: Select the entire buffer.
  * <kbd>Ctrl+L</kbd>: Select the current line.
* **Familiar Clipboard & History**:
  * <kbd>Ctrl+C</kbd>: Copy selection to system clipboard.
  * <kbd>Ctrl+X</kbd>: Cut selection.
  * <kbd>Ctrl+V</kbd>: Paste from clipboard.
  * <kbd>Ctrl+Z</kbd>: Undo.
  * <kbd>Ctrl+Y</kbd> or <kbd>Ctrl+Shift+Z</kbd>: Redo.
* **Search & Replace**:
  * <kbd>Ctrl+F</kbd>: Find in current buffer.
  * <kbd>Ctrl+H</kbd> (or <kbd>Cmd+R</kbd>): Replace in buffer.
* **Smart Modal Boundary**:
  While editable file buffers remain modeless, utility buffers (such as Telescope pickers, Lazy plugin manager, Mason, and terminals) preserve their own necessary keys so navigation remains smooth.

---

## 4. Zen Mode

**Zen Mode** eliminates all visual distractions so you can focus entirely on code or prose:
* **Maximized Viewport**: Hides the workspace sidebar, header breadcrumbs, and terminal panel. The editor fills the entire screen.
* **Quiet Return Footer**: A single clean status badge is displayed at the bottom showing your current mode and file. Clicking the return indicator or pressing <kbd>F11</kbd> instantly returns you to your previous layout.
* **State Preservation**: Your background terminal session, running tasks, open splits, and previous mode (Normal or IDE) are fully preserved when entering and exiting Zen mode.

---

## 5. Switching Between Modes

You can switch modes at any time:
1. **Footer Mode Badge**: Click the mode badge (`[NORMAL]` or `[IDE]`) in the bottom statusline to open the mode selector.
2. **Toggle Zen**: Press <kbd>F11</kbd> from anywhere to toggle into Zen mode and press <kbd>F11</kbd> again to return.
3. **Onboarding Guide**: Run `:TuimOnboarding` in Normal mode, or open Help (<kbd>F1</kbd> → **Help**) and press <kbd>o</kbd> to re-trigger the initial mode selection wizard.

---

## Next Steps

Learn how to customize your key combinations and presets in **[Keybindings & Shortcuts](Keybindings-and-Shortcuts.md)**.
