# Common Issues & Platform Fixes

This page documents common symptoms, platform-specific quirks, and verified fixes across various operating systems, terminal emulators, and environments.

---

## 1. Display & Visual Issues

### Broken Icons or Missing Glyphs
* **Cause**: Your terminal emulator is not configured to use a font patched with [Nerd Font](https://www.nerdfonts.com/) symbols.
* **Fix**:
  1. Open <kbd>F1</kbd> → **Settings** → **Appearance**.
  2. Uncheck the **Use Nerd Fonts (Icons)** checkbox.
  3. Tuim will replace icon glyphs with universal Unicode/ASCII characters (`📁`, `📄`, `*`, `+`).

### Screen Artifacts or Missing Colors
* **Cause**: Your terminal does not have 24-bit Truecolor enabled, or `COLORTERM` is not exported.
* **Fix**: Ensure your terminal exports `COLORTERM`:
  ```bash
  export COLORTERM=truecolor
  ```
  In `tmux.conf`, add:
  ```tmux
  set -g default-terminal "tmux-256color"
  set -as terminal-features ",*:RGB"
  ```

---

## 2. Clipboard Issues

### Copy / Cut / Paste Does Not Sync with System Clipboard
* **Cause**: Neovim requires a host clipboard tool to interface with the graphical desktop's clipboard.
* **Fix**:
  * **Wayland**: Install `wl-clipboard` (`sudo apt install wl-clipboard` or `sudo pacman -S wl-clipboard`).
  * **X11**: Install `xclip` or `xsel` (`sudo apt install xclip`).
  * **macOS**: `pbcopy` and `pbpaste` are used automatically. Ensure terminal clipboard access is allowed in System Settings.
  * **WSL**: Install `win32yank.exe` and place it in your `PATH`, or ensure Windows Terminal clipboard integration is enabled.

---

## 3. Keyboard & Modifier Issues

### `Ctrl+H` / `Backspace` / Shift-Arrow Not Working
* **Cause**: Some terminals (or terminal multiplexers like tmux) do not report distinct keycodes for modified keys (e.g. distinguishing `Ctrl+H` from `Backspace`, or sending raw escape codes for `Shift+Arrows`).
* **Fix**:
  * Use the **Vim-Safe Preset**: In Tuim, open <kbd>F1</kbd> → **Settings** → **Keyboard shortcuts**, and press <kbd>v</kbd>. This moves core commands to `Alt` keys, avoiding terminal `Ctrl` ambiguities.
  * In tmux, enable extended keys by adding to `~/.tmux.conf`:
    ```tmux
    set -s extended-keys on
    ```

---

## 4. Platform-Specific Quirks

### macOS: Startup Delays or Terminal Timeouts
* **Issue**: On macOS, running Tuim over standard terminal PTYs can occasionally hit permissions or `/dev/tty` polling latency.
* **Fix**: Ensure your terminal emulator (Terminal.app, iTerm2, Kitty, Ghostty) has been granted **Accessibility** and **Full Disk Access** permissions in macOS **System Settings → Privacy & Security**.

### Linux: AppImage FUSE Errors
* **Issue**: Error: `dlopen(): error loading libfuse.so.2` when launching `Tuim-linux-x86_64.AppImage` on newer distributions (Ubuntu 22.04+, Debian 12) or inside Docker containers.
* **Fix**:
  * Run the AppImage with the extract flag:
    ```bash
    ./Tuim-linux-x86_64.AppImage --appimage-extract-and-run
    ```
  * Or install `libfuse2`: `sudo apt install libfuse2`.

---

## Next Steps

Learn where Tuim writes logs and diagnostic information in **[Logs & Diagnostics](Logs-and-Diagnostics.md)**.
