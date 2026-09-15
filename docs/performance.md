# Performance profiling

Tuim records measurements before making performance claims. Run the harness
against a release build:

```bash
zig build -Doptimize=ReleaseFast
python3 scripts/profile_tuim.py
```

The harness writes `docs/performance-profile.json` and measures:

- offline cold startup to first output and settled output;
- a twelve-resize redraw/input storm and emitted terminal bytes;
- opening a generated multi-megabyte Unicode file;
- starting in a generated directory containing 5,000 files;
- initialization with the locally installed Tuim plugin tree, when available.

Results are machine-specific observations, not universal latency or throughput
guarantees. Compare results only on equivalent hardware, terminal dimensions,
build mode, Neovim/plugin state, and filesystem conditions. The generated
large file and directory live in a temporary directory and are removed after
the run.

The current JSON record was captured on Arch Linux x86-64 with a ReleaseFast
build. “Settled” means terminal output remained idle for the harness interval;
it is not a claim that every asynchronous language server or plugin task has
finished. Plugin initialization is measured separately in headless Neovim so
plugin-owned UI/input cannot distort Tuim frontend shutdown timing.
