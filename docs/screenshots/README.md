# Tuim screenshots

These WebP images come from the real Tuim executable built from this checkout.
They show the current workspace interface, not UI mockups or historical release
screenshots. Published releases can differ from the source build shown here.

## Reproduce

Requirements: the pinned Zig toolchain, Neovim, tmux, fontconfig with a monospace
font, and Python with Pillow and pyte. With uv installed, run from the repository:

```bash
bash setup.sh --source
uv run --with pillow --with pyte python scripts/capture_screenshots.py
```

Use `--data-dir /path/to/tuim-data` to capture a separate installation.

The script opens Tuim in isolated temporary XDG directories, with a demo Git
repository containing copies of Tuim source files. It uses the default VS Code
Dark Modern theme, portable symbols, and the installed plugin/parser set copied into temporary
directories. Treesitter is enabled. No user settings or plugin files are changed.
The 132 × 38 terminal grid is captured with its ANSI colors and rendered as a
1584 × 950 lossless WebP image. Font appearance depends on the host monospace font.
No UI elements or text are added to the captured grid.

The set covers Explorer, workspace, terminal, Git, settings, Extensions, IDE, and Zen.
The current Extensions preview uses an isolated recovery session to inspect the
local plugin inventory without loading third-party plugin code.
Regenerate after visible UI changes and inspect each image before publishing.
The older [media fixtures](../media/README.md) serve terminal regression examples;
they are not the website's current screenshot set.
