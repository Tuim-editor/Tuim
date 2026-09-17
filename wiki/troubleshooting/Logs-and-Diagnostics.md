# Logs & Diagnostics

When debugging unexpected behavior, plugin crashes, or RPC communication issues, Tuim provides several logging and diagnostic layers.

---

## 1. Locating Log Files

Tuim logs its frontend reactor, RPC traffic errors, and widget lifecycle events into its isolated state directory.

### Finding the Active Log Path
1. Launch Tuim.
2. Press <kbd>F1</kbd> → **Settings** → **About**.
3. Inspect the **Log path** row:
   ```
   ~/.local/share/tuim/tuim.log
   ```

### Inspecting Neovim Internal Messages
To view messages and errors emitted by the embedded Neovim processes:
* In Normal mode, type `:messages` and press <kbd>Enter</kbd>.
* Uncaught Lua errors, plugin notices, and LSP notifications are recorded in Neovim's internal message buffer.

---

## 2. Inspecting Log Output from the Terminal

You can monitor Tuim's log in real-time from a separate terminal window:

```bash
tail -f ~/.local/share/tuim/tuim.log
```

Log entries are prefixed with standard severity levels for easy filtering:
* `[ERROR]`: Fatal errors, RPC pipe failures, or unrecoverable worker errors.
* `[WARN]`: Non-fatal issues (e.g. missing clipboard tool, theme fallbacks, unrecognized terminal features).
* `[INFO]`: Application lifecycle transitions, mode switches, and theme updates.
* `[DEBUG]`: Verbose dispatch traces and differential redraw metrics.

---

## 3. Running Diagnostic Scripts

Tuim includes self-contained diagnostic scripts in the repository:

### Test Runtime Environment
Verifies that Neovim 0.12+, Tree-sitter parsers, and the default Zig syntax queries load cleanly:
```bash
python3 tests/default_runtime.py
```

### Smoke Test Bundled Plugins
Verifies that lazy.nvim, telescope, mason, blink.cmp, and alpha-nvim load without syntax errors in an isolated XDG sandbox:
```bash
scripts/plugin_smoke.sh
```

---

## Next Steps

If you need to report an issue, read how to use the built-in reporter in **[In-App Bug Reporting](In-App-Bug-Reporting.md)**.
