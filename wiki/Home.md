# Tuim Wiki

Welcome to the official **Tuim Wiki**! Tuim is a modern terminal workspace written in Zig with an embedded, isolated Neovim editing engine. It combines an Explorer, Git sidebar, persistent integrated shell, native settings panel, and coding assistant launchers into one keyboard- and mouse-accessible interface.

Whether you are a newcomer looking to get started, an experienced user configuring plugins and themes, a developer contributing code, or someone diagnosing an issue, this wiki covers everything you need to know.

---

## Quick Navigation

```
Tuim Wiki
├── 🚀 Getting Started
│   ├── Installation (Script, Bundles, AppImage, Source)
│   ├── Quick Start & First Run
│   └── Updating & Uninstalling
├── 📖 User Guide
│   ├── Workspace Overview & Layout
│   ├── Three Editing Modes (Normal, IDE, Zen)
│   ├── Keybindings & Customization
│   ├── File & Buffer Management
│   ├── Integrated Terminal & Scrollback
│   ├── Git Integration
│   ├── Extensions & Plugin Management
│   ├── Language Tools, Treesitter & LSP
│   └── AI Coding Assistants
├── ⚙️ Configuration
│   ├── Configuration Directories (XDG)
│   ├── Native Settings UI
│   ├── Themes & Desktop Styling (Omarchy)
│   └── Custom Plugin Configuration (Lua Specs)
├── 🛠️ Troubleshooting & Bug Reporting
│   ├── Recovery Mode (TUIM_DISABLE_PLUGINS=1)
│   ├── Common Issues & Platform Quirks
│   ├── Logs & Diagnostics
│   ├── In-App Bug Reporter
│   └── Cloudflare Bug Report Gateway
├── 💻 Architecture & Development
│   ├── System Architecture & Process Model
│   ├── Building from Source (Zig 0.16.0)
│   ├── Testing Suite & Verification
│   ├── Performance Profiling
│   ├── Packaging & Release Engineering
│   └── Contributing Guidelines
└── 📚 Compatibility & Reference
    ├── Complete Keybindings Cheat Sheet
    ├── Terminal Compatibility Matrix
    └── Plugin Compatibility Guide
```

---

## Wiki Highlights by Category

### 🚀 [Getting Started](getting-started/Installation.md)
* **[Installation Guide](getting-started/Installation.md)**: Install using the one-line curl script, download pre-built native bundles (Linux & macOS), run the portable AppImage, or compile from source.
* **[Quick Start](getting-started/Quick-Start.md)**: Step-by-step walkthrough of your first session, using the onboarding wizard, basic navigation, and saving your first file.
* **[Updating & Uninstalling](getting-started/Updating-and-Uninstalling.md)**: How in-place updates preserve your settings and how to perform clean or selective uninstalls.

### 📖 [User Guide](user-guide/Workspace-Overview.md)
* **[Workspace Overview](user-guide/Workspace-Overview.md)**: Understand the unified sidebar, region cycling (`F6`/`Shift+F6`), panel resizing, and mouse controls.
* **[Editing Modes](user-guide/Editing-Modes.md)**: Deep dive into **Normal** (modal Vim motions), **IDE** (modeless editing with standard shortcuts), and **Zen** (distraction-free focus).
* **[Keybindings & Shortcuts](user-guide/Keybindings-and-Shortcuts.md)**: TUI controls, editor mappings, the interactive key recorder, and built-in Vim-safe/IDE presets.
* **[File & Buffer Management](user-guide/File-and-Buffer-Management.md)**: Explorer file navigation, buffer switching without plugins, and Telescope project search (`Ctrl+P`, `Alt+G`).
* **[Integrated Terminal](user-guide/Integrated-Terminal.md)**: Persistent shell panel (`Ctrl+T`), scrollback navigation with Vim motions and mouse selection, and clipboard forwarding.
* **[Git Integration](user-guide/Git-Integration.md)**: Inspecting working tree diffs, staging/unstaging changes (`Space`), and committing (`c`) right from the terminal UI.
* **[Extensions & Plugins](user-guide/Extensions-and-Plugins.md)**: Managing plugins via the Extensions panel, browsing the Discover marketplace, and editing configuration overrides.
* **[Language Tools & LSP](user-guide/Language-Tools-and-LSP.md)**: Eager Treesitter highlighting with 19 precompiled parsers, Mason integration, and automatic project marker detection.
* **[AI Coding Assistants](user-guide/AI-Coding-Assistants.md)**: Launching CLI assistants (Antigravity, Claude Code, Codex, Gemini, OpenCode, Copilot) with editor context sharing (`Send selection`, `Send file`, `Review changes`).

### ⚙️ [Configuration](configuration/Configuration-Directories.md)
* **[Configuration Directories](configuration/Configuration-Directories.md)**: Isolated XDG storage paths (`~/.config/tuim`, `~/.local/share/tuim`, etc.) ensuring zero conflict with your system Neovim.
* **[Settings UI](configuration/Settings-UI.md)**: Customizing Appearance, Editor settings (column rulers, indentation), and Keyboard Shortcuts.
* **[Themes & Styling](configuration/Themes-and-Styling.md)**: Default VS Code Dark Modern theme, following the desktop palette via the Omarchy System theme, and Nerd Fonts vs portable symbols.
* **[Custom Plugin Configuration](configuration/Custom-Plugin-Configuration.md)**: Writing lazy.nvim spec overrides with `opts` and `config` in Lua.

### 🛠️ [Troubleshooting & Bug Reporting](troubleshooting/Recovery-Mode.md)
* **[Recovery Mode](troubleshooting/Recovery-Mode.md)**: Launching with `TUIM_DISABLE_PLUGINS=1 tuim` to recover from broken plugin configurations.
* **[Common Issues & Fixes](troubleshooting/Common-Issues-and-Fixes.md)**: Resolving broken font icons, missing clipboard providers, modifier key reporting quirks, and tmux/SSH behavior.
* **[Logs & Diagnostics](troubleshooting/Logs-and-Diagnostics.md)**: Accessing Tuim log files, Neovim error messages, and system diagnostic snapshots.
* **[In-App Bug Reporting](troubleshooting/In-App-Bug-Reporting.md)**: Using the built-in bug reporter (`F12` or `Commands > Report bug`) with automatic credential sanitization.
* **[Bug Report Gateway](troubleshooting/Bug-Report-Gateway.md)**: Technical overview and self-hosting instructions for the Cloudflare Worker reporting proxy.

### 💻 [Architecture & Development](development/Architecture.md)
* **[Architecture Overview](development/Architecture.md)**: Dual Neovim architecture, Zig event reactor (`src/reactor.zig`), MessagePack-RPC protocol, and differential row-run renderer.
* **[Building from Source](development/Building-from-Source.md)**: Compiling with Zig 0.16.0, build options, and running local developer builds.
* **[Testing & Verification](development/Testing-and-Verification.md)**: Running unit tests (`zig build test`), PTY integration tests, UI automation, and Shellcheck.
* **[Performance Profiling](development/Performance-Profiling.md)**: Measuring cold startup latency, resize storms, large Unicode files, and 5,000 file directories.
* **[Packaging & Releases](development/Packaging-and-Releases.md)**: Generating cross-platform native bundles, building AppImages, and GitHub Actions release workflows.
* **[Contributing Guidelines](development/Contributing-Guidelines.md)**: Development workflow, coding style conventions for Zig/Lua/Python, and pull request checklist.

### 📚 [Compatibility & Reference](reference/Keybindings-Cheat-Sheet.md)
* **[Keybindings Cheat Sheet](reference/Keybindings-Cheat-Sheet.md)**: Quick-reference table of every shortcut in Tuim organized by mode and context.
* **[Terminal Compatibility Matrix](reference/Terminal-Compatibility-Matrix.md)**: Verified behavior across Alacritty, Kitty, Ghostty, WezTerm, GNOME Terminal, Konsole, macOS Terminal, iTerm2, tmux, and OpenSSH.
* **[Plugin Compatibility Guide](reference/Plugin-Compatibility-Guide.md)**: Detailed analysis of what makes plugins compatible with Tuim's multigrid architecture.

---

> [!TIP]
> Use the sidebar on the left to jump directly to any topic, or press <kbd>F1</kbd> inside Tuim to explore the interactive command menu!
