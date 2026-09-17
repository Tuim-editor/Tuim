# Themes & Styling

Tuim comes with carefully tuned syntax and UI styling designed to deliver clean contrast and readable widgets across all supported terminal emulators.

---

## 1. Default Theme: VS Code Dark Modern

Out of the box, fresh installations default to **VS Code Dark Modern**:
* Clean, balanced contrast between code syntax, UI borders, sidebar lists, and the status footer.
* Fully tuned for both 24-bit Truecolor terminal emulators and terminal multiplexers.
* Automated contrast regression tests ensure readability of active, inactive, and focused UI elements.

---

## 2. System Theme: Following the Omarchy Desktop Palette

Tuim includes an innovative **System (follow desktop)** theme mode that automatically synchronizes Tuim's colors with your desktop environment:

### How It Works
* Tuim monitors the Omarchy color specification file at:
  ```
  $XDG_STATE_HOME/omarchy/current/theme/colors.toml
  (Fallback: $XDG_CONFIG_HOME/omarchy/current/theme/colors.toml)
  ```
* Whenever your desktop theme changes (e.g. switching between light/dark or rotating accent palettes), Tuim parses the new palette and updates editor syntax, sidebar backgrounds, selection highlights, and borders **live without requiring a restart**.
* If the palette file is absent or temporarily invalid at startup, Tuim gracefully defaults to safe built-in colors while continuing to watch for the file.

---

## 3. Font Icons & Portable Symbols

Tuim adapts to your terminal font environment:

### Nerd Font Icons
If your terminal emulator uses a font with Nerd Font glyphs installed (e.g., JetBrainsMono Nerd Font, FiraCode Nerd Font):
* File types display recognizable graphical icons (Zig, Python, Rust, Lua, Git status indicators).

### Portable Symbols Mode
If you are working on a machine, container, or remote SSH session without a Nerd Font installed:
1. Open <kbd>F1</kbd> → **Settings** → **Appearance**.
2. Select **Portable symbols**.
3. Tuim immediately replaces Nerd Font glyphs with standard Unicode and ASCII indicators (`📁`, `📄`, `*`, `+`, `-`).
4. Eliminates broken or unrendered question-mark glyphs (``).

---

## 4. Terminal Color Capabilities

Tuim automatically queries your terminal environment (`COLORTERM`, `TERM`, `TERM_PROGRAM`):
* In **Truecolor (24-bit direct color)** terminals (Alacritty, Kitty, WezTerm, Ghostty, GNOME Terminal, Windows Terminal), Tuim renders full 16-million-color gradients and precise hex values.
* In **256-color** or indexed environments, Tuim maps RGB colors down to the closest matching terminal palette cells.

---

## Next Steps

Learn how to write custom Lua configuration overrides for plugins in **[Custom Plugin Configuration](Custom-Plugin-Configuration.md)**.
