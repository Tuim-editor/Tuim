# AI Coding Assistants

Tuim provides an **AI Assistants** panel that lets you interact with popular command-line AI coding tools right from the workspace, sharing active editor context, file contents, and Git diffs without leaving the terminal.

---

## 1. Opening the AI Panel

* From the sidebar: Click `< Workspace` and select **AI assistants**.
* From Command Palette: Press <kbd>F1</kbd> → **AI assistants**.

The AI panel displays an assistant selector that detects CLI assistants installed on your host system:
* **Antigravity** (`agy`)
* **Claude Code** (`claude`)
* **Codex** (`codex`)
* **Gemini** (`gemini`)
* **OpenCode** (`opencode`)
* **GitHub Copilot CLI** (`copilot`)

> [!NOTE]
> Each AI assistant requires its own host CLI installation and authentication (API keys or provider login). After installing an assistant CLI on your system, restart Tuim so it detects the newly installed executable.

---

## 2. Starting & Managing Chats

1. **Select an Assistant**:
   In the AI panel, use <kbd>↑</kbd> / <kbd>↓</kbd> or <kbd>Tab</kbd> to choose an assistant from the list.
2. **Open Chat**:
   Press <kbd>Enter</kbd> or select **Open chat**. Tuim launches the assistant CLI inside a dedicated interactive terminal session.
3. **Switch Between Chat & Editor**:
   Press <kbd>F6</kbd> to cycle between the AI chat terminal, the code editor, and the sidebar.
4. **Chat Control Actions**:
   * **Return to chat**: Brings focus back to the prompt input.
   * **Restart chat**: Kills the current assistant process and initiates a clean session.
   * **Stop chat**: Terminates the active assistant process.

---

## 3. Sharing Editor Context with the Assistant

With an AI chat session active, you can send code and diffs directly to the prompt without manually copying and pasting:

| Action | Description |
| :--- | :--- |
| **Send selection** | Pastes the currently selected code in the editor directly into the assistant chat prompt. |
| **Send file** | Pastes the full contents of the active buffer into the assistant chat. |
| **Review changes** | Sends the current Git working-tree diff to the assistant with a request to review your changes for bugs or improvements. |

These context actions only affect the assistant whose chat is currently active.

---

## Next Steps

Explore how Tuim manages configurations and XDG paths in **[Configuration Directories](../configuration/Configuration-Directories.md)**.
