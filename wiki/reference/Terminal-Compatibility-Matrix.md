# Terminal Compatibility Matrix

Platform and terminal claims in Tuim represent **empirically observed test runs**, not assumptions. This page documents the observed support status across terminal emulators, multiplexers, and remote transports.

---

## 1. Observed Compatibility Results

| Environment | Observation Type | Status | Notes |
| :--- | :--- | :--- | :--- |
| **Alacritty 0.16 (Linux x86-64)** | Observed Pass | Supported | Host PTY suite passed with `TERM=alacritty`. Full 24-bit Truecolor and SGR mouse. |
| **tmux 3.7b (Linux x86-64)** | Observed Pass | Supported | Real isolated tmux server; nested PTY suite passed cleanly. |
| **OpenSSH 10.4 Loopback (Linux)**| Observed Pass | Supported | Key-only server, forced remote PTY, full nested suite passed. |
| **Kitty** | Profile Pass | Supported | 24-bit Truecolor, SGR mouse, bracketed paste, distinct modifiers. |
| **Ghostty** | Profile Pass | Supported | 24-bit Truecolor, SGR mouse, distinct modifiers verified. |
| **WezTerm** | Profile Pass | Supported | 24-bit Truecolor, SGR mouse, bracketed paste verified. |
| **GNOME Terminal / VTE** | Profile Pass | Supported | 24-bit Truecolor, SGR mouse, standard modifier fallbacks. |
| **Konsole** | Profile Pass | Supported | 24-bit Truecolor, SGR mouse, distinct modifiers verified. |
| **macOS Terminal / iTerm2** | CI Monitored | Unverified | Tested on macOS runners in CI (`macos-input`). Full smoke run is experimental pending macOS startup hang fix (#68). |
| **Windows Terminal (WSL2)** | Manual Smoke | Unverified | Runner workflow available in `.github/workflows/wsl-smoke.yml`; requires recorded hardware/runner run before marking verified. |
| **Linux Virtual Console (TTY)** | Profile Pass | Limited | 16-color indexed palette, mouse disabled, console font fallback. |

* **Observed Pass**: Ran through real automated PTY suites (`tests/terminal_compat.sh`) on hardware or runner.
* **Profile Pass**: Terminal profile detection, escape codes, and fallback paths are verified via automated unit tests.

---

## 2. Feature & Protocol Capability Breakdown

| Terminal / Transport | Color Depth | Mouse Protocol | Paste Mode | Modifier Keys | Unicode & Nerd Fonts | Clipboard Provider |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Alacritty** | 24-bit Truecolor | SGR | Bracketed | Distinct | Full width & glyph support | `xclip` / `wl-copy` |
| **Kitty** | 24-bit Truecolor | SGR | Bracketed | Distinct | Full width & glyph support | Host clipboard |
| **Ghostty** | 24-bit Truecolor | SGR | Bracketed | Distinct | Full width & glyph support | Host clipboard |
| **WezTerm** | 24-bit Truecolor | SGR | Bracketed | Distinct | Full width & glyph support | Host clipboard |
| **GNOME Terminal (VTE)** | 24-bit Truecolor | SGR | Bracketed | Distinct (`VTE_VERSION`) | Full width support | `xclip` / `wl-copy` |
| **Konsole** | 24-bit Truecolor | SGR | Bracketed | Distinct (`KONSOLE_VERSION`) | Full width support | `xclip` / `wl-copy` |
| **tmux** | 24-bit (Passthrough)| SGR | Bracketed | Conservative | Depends on outer terminal | Outer terminal dependent |
| **OpenSSH** | Client-Preserved | SGR | Bracketed | Conservative | Depends on client font | Remote provider dependent |
| **Linux Console** | 16-Color Indexed | None | Bracketed | Conservative | ASCII / Console Font | Unavailable |

---

## 3. Running the Smoke Test Suite Locally

You can test your own terminal emulator against Tuim's compatibility assertions:

```bash
# Test active terminal host
tests/terminal_compat.sh host

# Test inside an isolated tmux session
tests/terminal_compat.sh tmux

# Test over an isolated local SSH server
tests/terminal_compat.sh ssh
```

Each run verifies:
1. Entry into Normal, IDE, and Zen modes.
2. UTF-8 character insertion, newlines, and bracketed paste.
3. Mouse wheel scrolling and drag selection.
4. Terminal resizing and reflow.
5. Alternate-screen exit and terminal attribute restoration.
