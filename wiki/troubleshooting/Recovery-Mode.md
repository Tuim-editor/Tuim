# Recovery Mode

If a faulty third-party plugin, broken Lua configuration override, or corrupt plugin state prevents Tuim from starting or makes the UI unresponsive, **Recovery Mode** allows you to launch the editor safely without executing user plugin code.

---

## 1. How to Launch Recovery Mode

Start Tuim from your terminal with the `TUIM_DISABLE_PLUGINS` environment variable set to `1`:

```bash
TUIM_DISABLE_PLUGINS=1 tuim
```

---

## 2. What Recovery Mode Does

When `TUIM_DISABLE_PLUGINS=1` is passed:

1. **Skips Lazy Bootstrap**: Tuim bypasses loading `lazy.nvim` and disables the user plugin execution chain.
2. **Skips User Configuration Specs**: Custom `.lua` files under `~/.local/share/tuim/plugin_configs/` are not executed.
3. **Preserves All Files**: No files or configurations are deleted. Your plugins, settings, and code remain completely intact on disk.
4. **Maintains Native TUI Functions**: Tuim's Zig frontend, file explorer, basic editor buffers, and the Settings UI remain fully operational.

---

## 3. How to Fix Problems in Recovery Mode

Once inside a recovery session:

### A. Disable or Remove Faulty Plugins
1. Open **Extensions** (<kbd>F1</kbd> → **Extensions**).
2. Highlight the problematic plugin.
3. Press <kbd>d</kbd> to disable it, or <kbd>u</kbd> followed by <kbd>y</kbd> to uninstall it.

### B. Repair Custom Lua Configs
1. Open the plugin's configuration override (<kbd>e</kbd> in Extensions).
2. Fix the Lua syntax error or invalid table option.
3. Save the file (<kbd>Ctrl+S</kbd>).

### C. Resynchronize lazy.nvim
1. Open <kbd>F1</kbd> → **Settings** → **Plugins** → **Plugin Manager**.
2. Press <kbd>s</kbd> to force a re-synchronization and rebuild the plugin lockfile.

---

## 4. Returning to Normal Operation

After resolving the issue:
1. Exit Tuim (<kbd>Ctrl+Q</kbd> or `:quit`).
2. Start Tuim normally:
   ```bash
   tuim
   ```

Tuim will boot normally with the repaired configuration.

---

## Next Steps

For other common setup and display issues, consult **[Common Issues & Fixes](Common-Issues-and-Fixes.md)**.
