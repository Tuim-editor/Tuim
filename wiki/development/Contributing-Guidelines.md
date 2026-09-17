# Contributing Guidelines

Thank you for your interest in contributing to Tuim! We welcome bug fixes, documentation improvements, performance optimizations, and feature proposals.

---

## 1. Development Workflow

1. **Fork and Clone**:
   ```bash
   git clone https://github.com/<your-username>/tuim.git
   cd tuim
   ```
2. **Branch from `dev`**:
   The `dev` branch is the active integration branch. `main` tracks tagged stable releases.
   ```bash
   git checkout dev
   git checkout -b feat/your-feature-name
   ```
3. **Build and Test Locally**:
   Ensure you have **Zig 0.16.0** and **Neovim 0.12.0+** installed:
   ```bash
   zig build
   zig build test
   python3 tests/pty_integration.py
   ```

---

## 2. Code Style & Quality Standards

### Zig Code (`src/`)
* **Formatting**: Always format Zig code with the compiler:
  ```bash
  zig fmt build.zig src/
  ```
* **Memory Ownership**: Explicit allocators only. Ensure every allocated buffer has an unambiguous owner and is freed upon destruction. Avoid global mutable state.
* **Error Handling**: Use Zig's error unions (`!void`, `try`, `catch`). Do not use `@panic()` in non-test production code paths.
* **Bounded Operations**: Background tasks must use generational cancellation and bound their execution time.

### Lua Code (`src/nvim/`)
* Keep `tuim_init.lua` and `terminal_init.lua` clean, isolated, and fast.
* Never pollute global Neovim namespaces or write escape sequences directly to stdout (Neovim's stdout is Tuim's RPC channel).

### Shell Scripts
* Run `shellcheck` on all modified `.sh` files.
* Scripts must support standard POSIX or explicit `bash` semantics and handle spaces in paths properly.

---

## 3. Pull Request Checklist

Before submitting a Pull Request, ensure:
* [ ] `zig fmt --check build.zig src/main.zig src/nvim/ui_protocol.zig src/tui/renderer.zig` passes without changes.
* [ ] `zig build test` passes with 0 errors.
* [ ] `python3 tests/pty_integration.py` completes cleanly.
* [ ] Relevant shell scripts pass `shellcheck`.
* [ ] Commit messages clearly describe the problem and solution.
* [ ] Platform claims are verified with actual observed runs (see [Terminal Compatibility Matrix](../reference/Terminal-Compatibility-Matrix.md)).

---

## Next Steps

Explore the full keybindings summary in **[Keybindings Cheat Sheet](../reference/Keybindings-Cheat-Sheet.md)**.
