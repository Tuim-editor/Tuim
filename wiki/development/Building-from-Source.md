# Building from Source

This guide covers everything required to compile, build, and run Tuim from source.

---

## 1. Prerequisites & Toolchain Requirements

To build Tuim, ensure the following tools are installed:

| Tool | Version Requirement | Purpose |
| :--- | :--- | :--- |
| **Zig** | **0.16.0 exactly** | Compiles the Zig frontend, reactor, and TUI renderer. |
| **Neovim** | **0.12.0 or newer** | Editing and terminal engine. |
| **Git** | Any modern version | Source control and plugin cloning. |
| **Python 3** | Python 3.8+ | Marketplace search and test suite runner. |
| **C Compiler & Make** | `gcc` / `clang` & `make` | Compiling Tree-sitter parsers and grammars. |
| **Tree-sitter CLI** | 0.26.1+ | Grammar generator (setup will auto-install if missing). |

> [!IMPORTANT]
> Zig is actively evolving. Tuim is pinned specifically to **Zig 0.16.0**. Older (e.g. 0.13, 0.14) or newer nightly builds may fail due to standard library API changes.

---

## 2. Cloning & Compiling

Clone the repository and build using Zig's standard build system:

```bash
# Clone the repository
git clone https://github.com/Rouboufy/tuim.git
cd tuim

# Compile with optimization
zig build -Doptimize=ReleaseFast
```

The compiled binary will be placed at:
```
./zig-out/bin/tuim
```

---

## 3. Build Options & Optimization Modes

`build.zig` provides several customizable flags:

```bash
# Fast release (optimized for execution speed, stripped assertions)
zig build -Doptimize=ReleaseFast

# Safe release (optimized with runtime bounds checks enabled)
zig build -Doptimize=ReleaseSafe

# Debug build (unoptimized, full debug symbols, fastest compilation)
zig build -Doptimize=Debug

# Specify custom version string
zig build -Dversion=0.4.0-dev

# Specify custom bug reporting endpoint
zig build -Dbug-report-endpoint=https://my-reporting-worker.dev/bug-report
```

---

## 4. Running the Development Build

Run your newly built binary directly:

```bash
./zig-out/bin/tuim
```

You can also use Zig's built-in run step:

```bash
zig build run
```

To run with pass-through arguments (e.g. opening a specific file or directory):

```bash
zig build run -- src/main.zig
```

---

## 5. Automated Source Setup (`setup.sh --source`)

If you want an automated source build that downloads and configures private, isolated toolchains (Zig 0.16.0 and Neovim 0.12+) without altering your system packages:

```bash
bash setup.sh --source --yes
```

This installs private toolchains under `~/.local/share/tuim/tools/` and links the launcher at `~/.local/bin/tuim`.

---

## Next Steps

Learn how to run test suites and verify your changes in **[Testing & Verification](Testing-and-Verification.md)**.
