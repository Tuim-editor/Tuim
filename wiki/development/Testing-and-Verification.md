# Testing & Verification

Tuim maintains a rigorous, multi-tiered test suite covering unit logic, pseudo-terminal (PTY) interactions, UI widget behaviors, installer plans, and cross-platform terminal compatibility.

---

## 1. Fast Unit Tests (Zig)

Run all native Zig unit tests covering data structures, MessagePack decoding, layout primitives, and unicode width calculations:

```bash
zig build test
```

---

## 2. Pseudo-Terminal (PTY) Integration Tests

PTY tests spawn real headless Neovim and Tuim sessions inside simulated terminal pseudo-devices to verify end-to-end event loops, text rendering, and process lifecycle:

```bash
# Build the binary first
zig build

# Run controlling TTY input suite
python3 tests/controlling_tty.py

# Run main PTY integration suite (modes, typing, mouse, exit cleanup)
python3 tests/pty_integration.py

# Verify default runtime, Treesitter queries, and Zig highlighting
python3 tests/default_runtime.py
```

---

## 3. UI Automation Tests

The `tests/` directory contains targeted Python UI automation tests that verify specific native widgets:

> [!NOTE]
> **Prerequisites for UI Tests**: The UI test scripts use `tmux` to host and drive interactive terminal sessions. Ensure `tmux` is installed (`sudo apt install tmux` or `brew install tmux`). Additionally, `pickers_ui.py` and `plugins_ui.py` require plugins to be bootstrapped in `~/.local/share/tuim/lazy`.

```bash
# Test F1 command palette and key remapping
python3 tests/commands_ui.py

# Test fuzzy pickers and preview pane
python3 tests/pickers_ui.py

# Test extensions manager, categories, and marketplace listing
python3 tests/plugins_ui.py
python3 tests/plugin_manager.py

# Test workspace sidebar collapse and region focus
python3 tests/workspace_ui.py

# Test hover documentation and diagnostics rendering
python3 tests/hover_ui.py

# Test onboarding wizard
python3 tests/onboarding_ui.py
```

---

## 4. Terminal Compatibility Smoke Tests

Tuim includes a real PTY suite that tests terminal attribute restoration, alternate screen cleanup, mouse tracking, and resize storms:

```bash
# Run host terminal smoke suite
tests/terminal_compat.sh host

# Run isolated tmux server smoke suite
tests/terminal_compat.sh tmux

# Run loopback OpenSSH remote PTY suite
tests/terminal_compat.sh ssh
```

---

## 5. Static Analysis & Shell Script Checks

Before submitting pull requests or merging code, ensure code formatting and shell scripts pass static analysis:

```bash
# Verify Zig source formatting
zig fmt --check build.zig src/main.zig src/nvim/ui_protocol.zig src/tui/renderer.zig

# Check shell scripts with shellcheck
shellcheck setup.sh update.sh uninstall.sh build_appimage.sh tests/*.sh scripts/*.sh

# Validate static website HTML/CSS
python3 tests/site.py
```

---

## Next Steps

Learn how performance benchmarks are captured in **[Performance Profiling](Performance-Profiling.md)**.
