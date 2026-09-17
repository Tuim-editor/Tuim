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
* Inspect Neovim's process log if enabled:
  ```
  ~/.local/state/tuim/nvim.log
  ```

---

## 2. Inspecting Log Output from the Terminal

You can monitor Tuim's log in real-time from a separate terminal window:

```bash
tail -f ~/.local/share/tuim/tuim.log
```

Common log markers include:
* `[reactor]`: Event loop multiplexing, poll descriptors, and resize events.
* `[rpc]`: MessagePack-RPC request/response dispatches and Neovim multigrid events.
* `[task_runner]`: Background worker threads and Git status task execution.
* `[extensions]`: Plugin catalog searches and python backend responses.

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
