# File & Buffer Management

Tuim provides straightforward file exploration, buffer switching, and project-wide searching. Even in environments where third-party plugins are disabled or unavailable, Tuim's built-in buffer controls keep you productive.

---

## 1. File Explorer

Open the Explorer by clicking **Explorer** in the sidebar or via the <kbd>F1</kbd> command palette:

* **Navigating the Tree**: Use <kbd>↑</kbd> / <kbd>↓</kbd> or <kbd>j</kbd> / <kbd>k</kbd> to move between files and directories.
* **Expanding / Collapsing**: Press <kbd>Enter</kbd> or click a folder to toggle its contents.
* **Opening a File**: Press <kbd>Enter</kbd> or click a file to load it into the active editor split.
* **Collapsing the Sidebar**: Press <kbd>Ctrl+E</kbd> (or <kbd>Alt+E</kbd> in the Vim-safe preset) to toggle the sidebar view.

---

## 2. Creating New Files

You can create a new file from any editing mode:

1. Press <kbd>Ctrl+N</kbd> (or open <kbd>F1</kbd> → **New file**).
   > [!NOTE]
   > When the bottom terminal panel is focused, <kbd>Ctrl+N</kbd> is passed to the shell/terminal mode. To create a file while in the terminal, use <kbd>F1</kbd> → **New file** or switch focus with <kbd>F6</kbd>.
2. Begin typing immediately.
3. On the first save (<kbd>Ctrl+S</kbd>), Tuim presents a prompt:
   ```
   Save file as: [src/utils.zig         ]
   (Enter to save, Esc to cancel)
   ```
4. Enter the filename or relative path and press <kbd>Enter</kbd>.
5. Pressing <kbd>Esc</kbd> cancels the naming prompt safely without discarding any typed text.

---

## 3. Switching & Managing Buffers

### Switch Buffers
Tuim includes a native, plugin-independent **Switch buffers** dialog:
* Open <kbd>F1</kbd> → **Switch buffers**.
* Displays all open buffers, their relative paths, active/inactive state, and modification markers (`[+]`).
* Fuzzy filter buffers by typing.
* Use arrows and <kbd>Enter</kbd> to jump to the selected buffer.
* Works in Zen mode, narrow terminals, and recovery mode without requiring Telescope.

### Close Buffer
* Open <kbd>F1</kbd> → **Close buffer**.
* Closes the active buffer. If the buffer has unsaved changes, Tuim prompts you to save or discard before closing.

---

## 4. Project Search with Telescope & Ripgrep

Tuim integrates Telescope and ripgrep for lightning-fast project navigation:

### Find Files
* Press <kbd>Ctrl+P</kbd> or `<Space> f f`.
* Type any part of a file path to fuzzy search across the workspace.
* Results display the filename first followed by its parent directory path.
* Preview panel appears on wide terminals, showing the file content at your cursor.

### Live Grep (Search in Files)
* Press <kbd>Alt+G</kbd> or `<Space> f g`.
* Search text across the entire repository using ripgrep.
* Jump directly to matching lines and columns.

### Telescope Picker Controls
| Shortcut | Action |
| :--- | :--- |
| <kbd>Ctrl+N</kbd> / <kbd>Ctrl+P</kbd> | Move to next / previous search result |
| <kbd>Enter</kbd> | Open selected result in editor |
| <kbd>Tab</kbd> | Multi-select / mark entry |
| <kbd>Alt+P</kbd> | Toggle preview window |
| <kbd>Esc</kbd> | Close picker immediately (single press) |

---

## Next Steps

Learn how to interact with the shell and copy terminal text in **[Integrated Terminal](Integrated-Terminal.md)**.
