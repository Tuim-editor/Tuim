# Architecture Overview

Tuim is a high-performance terminal workspace written in Zig that embeds and controls Neovim over MessagePack-RPC. It is designed to combine the rich editing power of Neovim with the speed, memory safety, and native widget capabilities of Zig.

---

## 1. Process Model & Ownership

Tuim employs a **dual-process Neovim architecture**:

```
                              ┌────────────────────────────────────────┐
                              │            Tuim Zig Frontend           │
                              │  - Terminal input & event reactor      │
                              │  - Layout, widgets & statusline        │
                              │  - Differential row-run renderer       │
                              └───────────────┬────────────────────────┘
                                              │ MessagePack-RPC
                      ┌───────────────────────┴───────────────────────┐
                      ▼                                               ▼
         ┌─────────────────────────┐                     ┌─────────────────────────┐
         │  Neovim Editor Process  │                     │ Neovim Terminal Process │
         │   (tuim_init.lua)       │                     │  (terminal_init.lua)    │
         │ - Code buffers & text   │                     │ - Lightweight PTY host  │
         │ - Treesitter, LSP       │                     │ - Persistent user shell │
         │ - Plugins (lazy, mason) │                     │ - No editor plugins     │
         └─────────────────────────┘                     └─────────────────────────┘
```

1. **Editor Process (`tuim_init.lua`)**:
   Started with `NVIM_APPNAME=tuim` and `--clean`. Owns editable buffers, window layouts, text history, undo stacks, Treesitter highlights, diagnostics, language servers, and the plugin ecosystem.
2. **Terminal Frontend Process (`terminal_init.lua`)**:
   A separate lightweight Neovim process dedicated solely to hosting the integrated shell. It runs without the editor plugin stack, guaranteeing low memory overhead and zero latency impact on editing.
3. **Tuim Zig Frontend**:
   Owns keyboard/mouse input decoding, layout computation, native panels (Explorer, Git, AI, Extensions, Settings), focus management, and final terminal screen rendering.

---

## 2. Event Loop & The Reactor (`src/reactor.zig`)

Tuim uses an asynchronous event reactor that monitors readiness across:
* Host terminal input (`/dev/tty` or `stdin`)
* Window resize signals (`SIGWINCH`)
* RPC pipes from both Neovim processes
* Background task completion notifications

### Loop Progression
Each reactor cycle progresses through:
1. **Transport Drain**: Reads available MessagePack packets from Neovim.
2. **Normalized Dispatch**: Translates raw ANSI escape codes into high-level Tuim input events.
3. **State Updates**: Applies buffer, focus, and widget updates.
4. **Invalidation & Composition**: Determines which coarse screen regions are dirty.
5. **Flush**: Emits changed row runs to the terminal.

**Generation Tracking**: Registration generations ensure that stale events never target reused file descriptors or terminated tasks.

---

## 3. Background Task Runner (`src/task_runner.zig`)

Heavy operations—such as Git status scans, catalog indexing, and diff computations—are offloaded to a dedicated background task runner:
* Workers execute tasks on bounded worker threads.
* Tasks have explicit ownership IDs and generations; completions from superseded tasks (e.g. an outdated Git status check) are discarded automatically.
* Workers never directly touch the live UI arena or Neovim RPC clients, ensuring lock-free rendering.

---

## 4. MessagePack-RPC & Rendering Protocol

Communication with Neovim is implemented via custom MessagePack encoders and decoders:
* **Asynchronous Transport**: The interactive session communicates asynchronously so that typing and UI animations remain smooth even during large buffer loads.
* **Neovim Multigrid Protocol**: Consumes Neovim's `ext_multigrid`, `ext_linegrid`, and highlight events.
* **Differential Row-Run Renderer**: Rather than redrawing the whole screen every frame, Tuim's renderer (`src/tui/renderer.zig`) compares cell buffers and emits only the exact contiguous horizontal runs of changed cells, minimizing terminal I/O.

---

## 5. Extensions Backend (`src/nvim/store_search.py`)

The Extensions catalog search and marketplace parser is a standalone Python script embedded directly into the Tuim executable and extracted to the data directory at runtime:
* Exposes a clean JSON-over-stdout interface.
* Performs offline scans of installed plugins and local configurations.
* Queries the marketplace catalog, refreshing `db_minified.json` from GitHub in the background whenever the local cache is missing or older than 24 hours.

---

## Next Steps

Learn how to compile Tuim from source in **[Building from Source](Building-from-Source.md)**.
