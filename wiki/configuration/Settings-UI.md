# Settings UI

Tuim provides a full-featured, native settings panel directly inside the terminal interface. You can adjust themes, editor preferences, indentation, column rulers, and keybindings without editing raw JSON by hand.

---

## 1. Opening Settings

* Press <kbd>F1</kbd> and search for **Settings**.
* Click `< Workspace` in the sidebar and choose **Settings**.

The Settings window is organized into dedicated tabs:
* **General**
* **Appearance**
* **Editor**
* **Plugins**
* **Keyboard shortcuts** (labeled **Keybindings**)
* **About**

---

## 2. General Settings

* **Editing Mode**: Switch default editing style between `Normal` (modal Vim motions), `IDE` (modeless), or `Zen`.
* **Autocomplete**: Toggle the automatic completion popup (`blink.cmp`) on or off.
* **Autoindent**: Toggle automatic code indentation when inserting new lines.

---

## 3. Appearance Settings

* **Theme Selection**:
  * **VS Code Dark Modern** (default): High-contrast, modern dark theme tested across editors and widgets.
  * **System (follow desktop)**: Dynamically reads the desktop theme palette from Omarchy (`omarchy/current/theme/colors.toml`) and updates colors in real-time.
  * Additional bundled themes (Tokyo Night, Catppuccin, Gruvbox, etc.).
* **Nerd Font Icons Toggle**:
  * Checkbox: `[x] Use Nerd Fonts (Icons)`.
  * Checked (default): Uses graphical Nerd Font glyphs for files, folders, Git status, and tools.
  * Unchecked: Enables **Portable symbols** mode, falling back to standard Unicode/ASCII characters (`📁`, `📄`, `*`, `+`) for terminals without Nerd Fonts.

---

## 4. Editor Settings

* **Column Ruler**:
  Display vertical guide lines in the editor:
  * Options: `Off`, `80`, `100`, `120`, or `80, 120`.
  * Rulers apply instantly to open and newly created code buffers. Utility buffers (terminals, dashboard, settings, help) never display rulers.
* **Line Numbers**:
  * Toggle between Absolute line numbers, Relative numbers (Vim-style), or Off.
* **Tab Width & Indentation**:
  * Set tab size (default 4 spaces) and toggle expand tabs (soft spaces vs hard tabs).

---

## 5. Keyboard Shortcuts Tab

* Browse all native TUI actions.
* Interactive key recording: select an action, press <kbd>Enter</kbd>, and strike the desired combination.
* Fast presets: press <kbd>v</kbd> for Vim-safe shortcuts or <kbd>p</kbd> for IDE-standard keys.
* Press <kbd>r</kbd> to reset an action, and <kbd>Ctrl+S</kbd> to save changes.

---

## 6. About Tab

The About panel gives you an instant health and diagnostic snapshot:
* Tuim version and Git commit hash.
* Bundled Neovim version.
* **Data**: Path to active data directory (`~/.local/share/tuim`).
* **Settings**: Path to active settings JSON file.
* **Log**: Exact path to the active runtime log file (`~/.local/share/tuim/tuim.log`).
* **Update button**: Checks for newer releases and launches the software updater (atomically updating the AppImage when `$APPIMAGE` is present, or rerunning the installer for native installs).

---

## Next Steps

Learn more about desktop color synchronization in **[Themes & Styling](Themes-and-Styling.md)**.
