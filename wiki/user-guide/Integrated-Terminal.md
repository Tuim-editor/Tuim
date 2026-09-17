# Integrated Terminal

Tuim features a dedicated, persistent integrated terminal docked directly beneath your code editor. Unlike standard subshells that disappear when closed, Tuim's terminal session stays alive in the background while you focus on writing code.

---

## 1. Opening & Closing the Terminal

* **Toggle Shortcut**: Press <kbd>Ctrl+T</kbd> (or <kbd>Alt+T</kbd> in the Vim-safe preset).
* **Focus Cycling**: Press <kbd>F6</kbd> or <kbd>Shift+F6</kbd> to cycle focus directly into and out of the terminal.
* **Persistent Sessions**: Hiding the terminal panel with <kbd>Ctrl+T</kbd> or entering Zen mode (<kbd>F11</kbd>) does **not** terminate running processes. Long-running builds, servers, or CLI tools continue executing seamlessly.

### Terminal Split Controls (When Terminal is Focused)
When your cursor is inside the terminal panel, Tuim provides native terminal split management shortcuts:
* <kbd>Alt+V</kbd>: Create vertical terminal split
* <kbd>Alt+S</kbd>: Create horizontal terminal split
* <kbd>Alt+C</kbd>: Close focused terminal split
* <kbd>Alt+O</kbd>: Cycle focus between open terminal splits
* <kbd>Alt+H</kbd> / <kbd>Alt+J</kbd> / <kbd>Alt+K</kbd> / <kbd>Alt+L</kbd>: Move directional focus between splits (or return to editor)

---

## 2. Navigating Scrollback with Keyboard

Tuim uses Neovim's terminal-normal mode to provide rich, keyboard-driven scrollback inspection:

1. **Enter Scrollback Mode**:
   While the terminal is focused, press:
   ```
   Ctrl+\, followed by Ctrl+N
   ```
2. **Move Around with Vim Motions**:
   Use standard navigation keys:
   * <kbd>h</kbd>, <kbd>j</kbd>, <kbd>k</kbd>, <kbd>l</kbd> for directional movement
   * <kbd>Ctrl+U</kbd> / <kbd>Ctrl+D</kbd> for half-page scrolling
   * <kbd>gg</kbd> / <kbd>G</kbd> to jump to the top / bottom of scrollback history
3. **Select & Copy Text**:
   * Press <kbd>v</kbd> to start character selection.
   * Press <kbd>V</kbd> for line selection, or <kbd>Ctrl+V</kbd> for block selection.
   * Expand your selection using motions.
   * Press <kbd>y</kbd> to yank (copy) the selected text. If a system clipboard provider is available (`xclip`, `wl-copy`, `pbcopy`), the text is copied directly to your host clipboard.
4. **Resume Typing**:
   Press <kbd>i</kbd> or <kbd>a</kbd> to exit scrollback mode and resume live shell input.

---

## 3. Mouse Interaction in the Terminal

* **Scroll Wheel**: Rotate the mouse wheel while hovering over the terminal panel to scroll through history.
* **Click to Focus**: Left-clicking anywhere in the active shell row immediately focuses the live prompt.
* **Left-Click Drag Selection**: Click and drag across terminal output to visually highlight text, identical to desktop terminal emulators.
* **Mouse Event Forwarding**: If a program running inside the terminal enables terminal mouse reporting (such as `htop`, `tmux`, or `fzf`), Tuim forwards mouse clicks and drags directly to that program. When you need to select text from such programs, use the keyboard route (<kbd>Ctrl+\ Ctrl+N</kbd>).

---

## 4. Terminal Architecture

Under the hood, Tuim starts a dedicated, lightweight Neovim process (`src/nvim/terminal_init.lua`) specifically to drive the terminal interface. This process does not load heavy editor plugins (Treesitter, LSP, Telescope), ensuring minimal memory overhead and zero latency impact on your primary code editor.

---

## Next Steps

Learn how to review and commit changes in **[Git Integration](Git-Integration.md)**.
