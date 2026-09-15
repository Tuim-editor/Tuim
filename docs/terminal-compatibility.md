# Terminal compatibility smoke tests

Platform claims here represent observed runs, not inferred support. Run
`tests/terminal_compat.sh host` in a terminal or
`tests/terminal_compat.sh tmux` for the isolated tmux path. The `ssh` mode
starts an isolated key-only OpenSSH server on loopback and runs the host suite
through a forced remote PTY. Each run exercises
all three modes, typing, newline, paste, mouse input, resize, shutdown,
alternate-screen cleanup, and terminal-attribute restoration.
The mouse column covers Neovim-routed terminal scrolling and selection as well
as forwarding to terminal applications that enable mouse reporting; clipboard
copy still depends on an available Neovim provider.

| Environment | Last observed | Result | Notes |
| --- | --- | --- | --- |
| Alacritty 0.16, Arch Linux x86-64 | 2026-07-13 | Pass | Host PTY suite; `TERM=alacritty` |
| tmux 3.7b on Arch Linux x86-64 | 2026-07-13 | Pass | Real isolated tmux server; nested PTY suite passed |
| OpenSSH 10.4 loopback on Arch Linux x86-64 | 2026-07-13 | Pass | Key-only server, forced remote PTY, full nested suite |
| macOS Terminal and iTerm2 | Not yet recorded | Unverified | Requires macOS hardware or runner |
| Windows Terminal/WSL | Not yet recorded | Unverified | Installer simulation is not a platform smoke test |

CI runs the macOS host suite in `.github/workflows/ci.yml` and retains its log
as `macos-terminal-smoke`. Real WSL verification is intentionally a manual job
in `.github/workflows/wsl-smoke.yml` on a runner labeled `windows` and `wsl`;
the job retains `wsl-terminal-smoke`. A green job may be copied into the table
with its run URL, runner OS, terminal host, and date. Merely adding either job
does not change an entry from `Unverified`.

For a new observation, record the terminal and version, operating system,
date, command, failures or limitations, and whether every cleanup assertion
passed. Never change an `Unverified` entry based only on environment-variable
simulation.

## Capability matrix

`Observed` means the real transport or terminal ran the PTY suite. `Profile`
means capability detection and fallback behavior are unit-tested but the GUI
terminal was not available in this workspace. Clipboard results always depend
on both the terminal transport and a host Neovim provider.

| Terminal / transport | Evidence | Color | Mouse | Paste | Modifiers | Unicode | Resize | Clipboard |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Alacritty | Observed pass | 24-bit | SGR | Bracketed | Distinct | Cell-tested | Pass | Provider-dependent |
| Kitty | Profile | 24-bit | SGR | Bracketed | Distinct | Cell-tested | Expected | Provider-dependent |
| Ghostty | Profile | 24-bit | SGR | Bracketed | Distinct | Cell-tested | Expected | Provider-dependent |
| WezTerm | Profile | 24-bit | SGR | Bracketed | Distinct | Cell-tested | Expected | Provider-dependent |
| GNOME Terminal / VTE | Profile | 24-bit | SGR | Bracketed | Distinct | Cell-tested | Expected | Provider-dependent |
| Konsole | Profile | 24-bit | SGR | Bracketed | Distinct | Cell-tested | Expected | Provider-dependent |
| macOS Terminal | Deferred | Profile fallback | Expected | Expected | Terminal-dependent | Font-dependent | Expected | `pbcopy` expected |
| iTerm2 | Deferred | Profile 24-bit | Expected | Expected | Expected | Font-dependent | Expected | `pbcopy` expected |
| Windows Terminal / WSL | Deferred | Profile 24-bit | Expected | Expected | Conservative fallback | Font-dependent | Expected | WSL/provider-dependent |
| tmux 3.7b | Observed pass | 24-bit preserved | Pass | Pass | Conservative fallback | Pass | Pass | Outer-terminal dependent |
| OpenSSH 10.4 | Observed pass | Client-preserved | Pass | Pass | Conservative fallback | Pass | Pass | Remote-provider dependent |
| Linux console | Profile | Indexed | Disabled | Bracketed | Conservative fallback | Console-font dependent | Expected | Unavailable by default |

The profile suite recognizes `TERM_PROGRAM`, `VTE_VERSION`,
`KONSOLE_VERSION`, and `WT_SESSION`, and deliberately disables assumptions
about GUI-style modifier sequences under tmux, SSH, WSL, dumb terminals, and
the Linux console. Unicode renderer tests cover ASCII, CJK, emoji, combining
marks, variation selectors, Nerd Font symbols, continuation cells, and
clipping. The PTY suite sends CJK and emoji input in every editing mode.
