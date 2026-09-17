# Workspace Overview

Tuim is designed around a single unified workspace that integrates an Explorer, Git changes, an integrated terminal, native settings, and language tools into a coherent interface. Everything is accessible via both keyboard and mouse.

---

## 1. The Layout

The Tuim workspace consists of five core regions:

```
┌─────────────────────────────────────────────────────────────┐
│ < Workspace   Explorer   [Commands F1]                      │ 1. Header & Navigation
├────────────────┬────────────────────────────────────────────┤
│ 📁 Explorer    │ main.zig                                   │
│ ────────────── │                                            │
│ > src          │ 1 pub fn main() void {                     │ 2. Sidebar &
│   📄 main.zig  │ 2     // Code editing                      │    3. Editor Viewport
│   📄 app.zig   │ 3 }                                        │
│                │                                            │
├────────────────┴────────────────────────────────────────────┤
│ ❯_ Terminal                                            [x]  │ 4. Integrated Terminal
│ $ zig build test                                            │
├─────────────────────────────────────────────────────────────┤
│ [NORMAL] main.zig                                  utf-8    │ 5. Footer & Statusline
└─────────────────────────────────────────────────────────────┘
```

### 1. Header & Breadcrumb Bar
* **`< Workspace`**: Clickable breadcrumb navigation that takes you back from specific panels (Explorer, Git, AI, Extensions) to the top-level Workspace list.
* **View Title**: Shows the active panel or open tool name.
* **`[Commands F1]`**: Clickable button to open the command palette.

### 2. Workspace Sidebar
The sidebar hosts your primary project tools. Click an entry or press <kbd>Enter</kbd> to open:
* **Explorer**: Browse project files and folders in a tree view.
* **Git**: View changed files, inspect diffs, stage/unstage, and commit.
* **Extensions**: Manage installed plugins, browse the marketplace, and configure specs.
* **Language Tools**: Health status, Mason package manager, LSP servers, and formatters.
* **AI Assistants**: Launch terminal-based coding assistant CLIs (Antigravity, Claude, Codex, Gemini, OpenCode, Copilot).
* **Settings**: Open native application preferences.

### 3. Editor Viewport
The primary editing pane, powered by Neovim. Supports:
* Vertical and horizontal splits (<kbd>Ctrl+W v</kbd>, <kbd>Ctrl+W s</kbd>)
* Syntax highlighting via Tree-sitter
* Autocompletion popups via blink.cmp
* In-line diagnostics and LSP hover popups

### 4. Integrated Terminal
* A persistent shell session docked below the editor.
* Toggle visibility anytime with <kbd>Ctrl+T</kbd> without interrupting running commands.
* Supports keyboard scrollback navigation with Vim motions and mouse drag selection.

### 5. Status Footer
* Displays the active editing mode (`NORMAL`, `IDE`, or `ZEN`).
* Shows file path, encoding, and line/column position.
* Click the mode badge to switch between editing modes.

---

## 2. Navigating Between Regions

Tuim introduces seamless keyboard-driven region switching:

| Shortcut | Action |
| :--- | :--- |
| <kbd>F6</kbd> | Focus the **next** region (Editor → Sidebar → Terminal → Editor). |
| <kbd>Shift+F6</kbd> | Focus the **previous** region. |
| <kbd>Ctrl+E</kbd> | Toggle the **Sidebar** on or off. |
| <kbd>Ctrl+T</kbd> | Toggle the **Terminal** panel on or off. |
| <kbd>Esc</kbd> | In a tool panel, returns to the top-level Workspace list; pressed again, returns focus to the Editor. |

---

## 3. Resizing Splits & Panels

You can adjust panel widths and heights dynamically using your keyboard:

| Shortcut | Action |
| :--- | :--- |
| <kbd>Alt+←</kbd> | Resize panel boundary to the left |
| <kbd>Alt+→</kbd> | Resize panel boundary to the right |
| <kbd>Alt+↑</kbd> | Resize panel boundary upward |
| <kbd>Alt+↓</kbd> | Resize panel boundary downward |

> [!NOTE]
> You can also click and drag the divider borders between the sidebar, editor, and terminal panel using your mouse.

---

## 4. Responsive & Compact Behavior

* **Automatic Sidebar Collapse**: If your terminal window is narrower than **40 columns**, the sidebar automatically collapses to preserve editor readability. All sidebar tools and commands remain 100% accessible via the <kbd>F1</kbd> command palette.
* **Side-by-Side vs Focused Views**: In wider terminals (e.g. 100+ columns), dialogs such as Extensions display list and detail panes side by side. In compact terminals, they automatically adapt to a single focused view with smooth back navigation.

---

## Next Steps

Learn about Tuim's three distinct editing modes in **[Editing Modes](Editing-Modes.md)**.
