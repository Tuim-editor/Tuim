# Quick Start Guide

Welcome to Tuim! This guide walks you through your very first launch, explains the onboarding wizard, introduces the workspace layout, and shows you the essential shortcuts needed to get productive immediately.

---

## 1. First Run & Onboarding Wizard

When you launch Tuim for the first time by typing `tuim`, you are greeted by an interactive onboarding banner:

```
╭─────────────────────────────────────────────────────────────╮
│ Welcome to Tuim! Choose your preferred editing style:       │
│                                                             │
│   [i] IDE Mode    - Familiar modeless editing, Ctrl+S/Z/C/V │
│   [n] Normal Mode - Traditional Vim modal motions & leader  │
│   [l] Language Tools - Manage LSP servers & formatters      │
│                                                             │
│ Press 'i' or 'n' to select, or Escape to start editing.     │
╰─────────────────────────────────────────────────────────────╯
```

* Press <kbd>i</kbd> if you prefer **IDE Mode**: you can start typing immediately, select text with your mouse or Shift+Arrows, and use standard shortcuts (<kbd>Ctrl+S</kbd> to save, <kbd>Ctrl+Z</kbd> to undo, <kbd>Ctrl+C</kbd>/<kbd>Ctrl+V</kbd> for copy/paste).
* Press <kbd>n</kbd> if you prefer **Normal Mode**: you get standard Neovim modal editing (`Normal`, `Insert`, `Visual` modes, standard motions `h`/`j`/`k`/`l`, and `<Space>` as the leader key).
* Press <kbd>l</kbd> to inspect and install **Language Servers** via Mason.
* Press <kbd>Esc</kbd>, <kbd>Enter</kbd>, or <kbd>q</kbd> to close the guide and begin editing.

> [!TIP]
> You can reopen the onboarding guide at any time by running `:TuimOnboarding` in Normal mode, or pressing `o` while viewing Help.

---

## 2. Interface Layout

Tuim's interface is divided into clean, focused functional areas:

```
┌─────────────────────────────────────────────────────────────┐
│ < Workspace   Explorer   [Commands F1]                      │ Header Bar
├────────────────┬────────────────────────────────────────────┤
│ Workspace      │ main.zig                                   │
│ ────────────── │ 1 const std = @import("std");              │
│ 📁 src         │ 2                                          │
│   📄 main.zig  │ 3 pub fn main() !void {                    │ Editor Viewport
│   📄 app.zig   │ 4     std.debug.print("Hello Tuim!\n", .{});│
│ 📁 tests       │ 5 }                                        │
│                │                                            │
├────────────────┴────────────────────────────────────────────┤
│ ❯_ Terminal                                            [x]  │ Persistent Terminal
│ user@host:~/Projects/demo$ zig build run                    │
├─────────────────────────────────────────────────────────────┤
│ [NORMAL] main.zig                                     utf-8 │ Status Footer
└─────────────────────────────────────────────────────────────┘
```

1. **Header Bar**: Displays current view controls, clickable breadcrumbs (`< Workspace`), and the **[Commands F1]** search trigger.
2. **Left Sidebar**: Houses the file Explorer, open files list, Git changes panel, Extensions manager, and AI Assistant launcher.
3. **Editor Viewport**: The main code editing area powered by Neovim, supporting splits, syntax highlighting, and hover diagnostics.
4. **Integrated Terminal Panel**: A persistent shell at the bottom, toggled with <kbd>Ctrl+T</kbd>.
5. **Status Footer**: Shows the current editing mode (`NORMAL`, `IDE`, or `ZEN`), active file path, encoding, and cursor position.

---

## 3. Essential Navigation Shortcuts

| Action | Shortcut | What It Does |
| :--- | :--- | :--- |
| **Search Commands** | <kbd>F1</kbd> | Opens the fuzzy searchable command palette. |
| **Cycle Regions** | <kbd>F6</kbd> / <kbd>Shift+F6</kbd> | Switches focus between Editor, Sidebar, and Terminal. |
| **Toggle Sidebar** | <kbd>Ctrl+E</kbd> | Shows or hides the workspace sidebar. |
| **Toggle Terminal** | <kbd>Ctrl+T</kbd> | Opens or hides the bottom persistent shell panel. |
| **Toggle Zen Mode** | <kbd>F11</kbd> | Enters distraction-free full-screen editor mode. |
| **Find File** | <kbd>Ctrl+P</kbd> | Fuzzy finds files across your project with Telescope. |
| **Find in Files** | <kbd>Alt+G</kbd> | Searches text across all files using ripgrep. |
| **Save File** | <kbd>Ctrl+S</kbd> | Saves current file. Prompts for filename on new buffers. |

---

## 4. Your First Workflow: Creating & Saving a File

1. **Create a Buffer**:
   * Press <kbd>Ctrl+N</kbd> (or open <kbd>F1</kbd> and select **New file**).
2. **Write Content**:
   * In IDE Mode, simply start typing.
   * In Normal Mode, press <kbd>i</kbd> to enter Insert mode, then type your text.
3. **Save with a Name**:
   * Press <kbd>Ctrl+S</kbd>.
   * A prompt appears asking for the file name (e.g., `hello.zig` or `notes.txt`).
   * Type the file path and press <kbd>Enter</kbd>.
   * If you change your mind, press <kbd>Esc</kbd> to cancel naming without losing any of your typed text.
4. **Open the Terminal**:
   * Press <kbd>Ctrl+T</kbd> to bring up your shell.
   * Run your compiler, script, or tests (e.g., `zig build run`).
   * Press <kbd>Ctrl+T</kbd> again to hide the terminal—your shell session continues running in the background!

---

## 5. Next Steps

* Read the **[Editing Modes Guide](../user-guide/Editing-Modes.md)** to learn how Normal, IDE, and Zen modes work.
* Check out the **[Keybindings & Shortcuts Guide](../user-guide/Keybindings-and-Shortcuts.md)** to customize your keys.
* Explore **[Extensions & Plugins](../user-guide/Extensions-and-Plugins.md)** to customize your tools.
