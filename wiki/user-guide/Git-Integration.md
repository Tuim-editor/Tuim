# Git Integration

Tuim includes a built-in Git changes panel in the workspace sidebar. It lets you review diffs, stage and unstage files, and compose commits without leaving your keyboard or opening an external tool.

---

## 1. Opening the Git Panel

* From the sidebar: Click `< Workspace` and select **Git** (or press <kbd>Enter</kbd> on Git in the sidebar).
* From Command Palette: Press <kbd>F1</kbd> → **Git**.

The Git panel displays all modified, added, deleted, and untracked files in your repository, grouped by staged and unstaged state.

---

## 2. Navigating Changes

| Action | Shortcut |
| :--- | :--- |
| **Move up / down** | <kbd>↑</kbd> / <kbd>↓</kbd> or <kbd>j</kbd> / <kbd>k</kbd> |
| **Jump to first / last change** | <kbd>Home</kbd> / <kbd>End</kbd> |
| **Open changed file** | <kbd>Enter</kbd> (opens the file in the editor) |
| **Stage / Unstage toggle** | <kbd>Space</kbd> |
| **Explicitly Stage file** | <kbd>s</kbd> or <kbd>+</kbd> |
| **Explicitly Unstage file** | <kbd>u</kbd> or <kbd>-</kbd> |
| **Return to Workspace** | <kbd>Esc</kbd> |

---

## 3. Staging and Committing

1. **Open File**:
   Highlight any changed file and press <kbd>Enter</kbd>. Tuim opens the file directly in the active editor buffer so you can review or edit it.
2. **Stage Your Changes**:
   Press <kbd>Space</kbd> on the files you want to include in the commit. The file moves into the "Staged Changes" list. (You can also press <kbd>s</kbd>/<kbd>+</kbd> to stage and <kbd>u</kbd>/<kbd>-</kbd> to unstage).
3. **Compose Commit**:
   Press <kbd>c</kbd>. Tuim presents an inline commit message prompt:
   ```
   Commit message: [feat: add dark theme support               ]
   (Enter to commit, Esc to cancel)
   ```
4. **Finalize**:
   Press <kbd>Enter</kbd> to execute `git commit`. Tuim updates the working tree status immediately.
   Press <kbd>Esc</kbd> to discard the message prompt without committing.

---

## 4. Background Refresh & Non-Blocking Updates

Git status monitoring in Tuim is powered by Tuim's background task runner (`src/task_runner.zig`):
* Background status checks and diff computations run asynchronously on bounded worker threads, ensuring the UI and editor remain 100% fluid.
* Interactive mutations (staging, unstaging, and committing) execute directly and immediately trigger a status refresh.
* Generation counters ensure that slow or stale Git status completions are automatically discarded if your working tree state has changed in the meantime.

---

## Next Steps

Learn how to manage plugins and browse the marketplace in **[Extensions & Plugins](Extensions-and-Plugins.md)**.
