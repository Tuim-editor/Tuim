# Updating & Uninstalling Tuim

Tuim isolates its application files, user configurations, and runtime state. This design guarantees that updates preserve your preferences and plugins, and allows clean or selective removal whenever needed.

---

## 1. Updating Tuim

### A. Updating a Release Installation (Recommended)

If you installed Tuim using the one-line curl installer, simply rerun the installer command:

```bash
curl -fsSL https://raw.githubusercontent.com/Rouboufy/tuim/main/setup.sh | bash
```

**What happens during an update:**
* The installer fetches the newest release bundle matching your platform.
* The binary and private Neovim runtime are updated in-place under `~/.local/share/tuim`.
* **Your settings and plugins are completely preserved**: `~/.config/tuim/` and `~/.local/share/tuim/settings.json`, `user_plugins.json`, and `plugin_configs/` are left untouched.
* The launcher symlink at `~/.local/bin/tuim` is refreshed.

### B. Updating the Linux AppImage

If you are running the portable Linux AppImage:
1. Open Tuim and press <kbd>F1</kbd> → **Settings** → **About**.
2. If a newer version is detected, click the **Update** button. Tuim will download and atomically replace the current AppImage in place (requires the file to be located in a user-writable directory).
3. Alternatively, manually download the latest stable AppImage:
   ```bash
   curl -fLo ~/.local/bin/tuim https://github.com/Rouboufy/tuim/releases/latest/download/Tuim-linux-x86_64.AppImage
   chmod +x ~/.local/bin/tuim
   ```

### C. Updating a Source Build

If you compiled Tuim from a Git checkout:

```bash
cd tuim
git pull --ff-only
zig build -Doptimize=ReleaseFast
```

---

## 2. Verifying Your Version

To check the installed version without launching the graphical UI:

```bash
tuim --version
```

Inside Tuim, open <kbd>F1</kbd> → **Settings** → **About** to see:
* Active Tuim version and Git commit
* Bundled Neovim engine version
* Active Data directory (`~/.local/share/tuim`)
* Settings path (`~/.local/share/tuim/settings.json`)
* Active log file path (`~/.local/share/tuim/tuim.log`)

---

## 3. Uninstalling Tuim

Tuim provides an official uninstaller script `uninstall.sh` that offers safe, selective removal options. If you have the repository checked out, run `bash uninstall.sh`. If you installed via the curl installer or a release bundle and do not have the repository cloned, you can run the script directly via `curl`.

### A. Binary Only Removal (Keeps Your Settings & Data)

If you want to remove the `tuim` executable launcher while keeping your preferences, plugins, and custom configurations intact:

```bash
# From repository:
bash uninstall.sh --binary

# Or via curl:
curl -fsSL https://raw.githubusercontent.com/Rouboufy/tuim/main/uninstall.sh | bash -s -- --binary
```

### B. Complete Clean Removal

To remove Tuim completely, including all configuration files, installed plugins, compiled Treesitter parsers, runtime state, and caches:

```bash
# From repository:
bash uninstall.sh --all

# Or via curl:
curl -fsSL https://raw.githubusercontent.com/Rouboufy/tuim/main/uninstall.sh | bash -s -- --all
```

> [!WARNING]
> Running `uninstall.sh --all` will permanently delete:
> - `~/.config/tuim` (Config directory)
> - `~/.local/share/tuim` (Data directory: settings, plugins, `tuim.log`, parsers, private runtimes)
> - `~/.local/state/tuim/log` and `~/.local/state/tuim/sessions` (State directories)
> - `~/.cache/tuim` (Cached artifacts)
>
> The script will always ask for explicit confirmation before deleting files. For automated environments, pass `--yes`.

### C. Selective Uninstallation Options

Run `bash uninstall.sh --help` to view all available flags:

```
Tuim uninstaller

Usage:
  uninstall.sh [options]

Options:
  --binary       Remove only the launcher symlink (~/.local/bin/tuim)
  --settings     Remove config directory (~/.config/tuim)
  --plugins      Remove data directory (~/.local/share/tuim: plugins, settings, tuim.log)
  --cache        Remove cache files (~/.cache/tuim)
  --logs         Remove state log directory (~/.local/state/tuim/log)
  --sessions     Remove state session directory (~/.local/state/tuim/sessions)
  --all          Remove all Tuim files across binary, settings, plugins, logs, sessions, cache
  --yes          Skip confirmation prompts
  --help, -h     Show this help message
```

---

## Next Steps

Now that installation and lifecycle management are covered, dive into the **[User Guide](../user-guide/Workspace-Overview.md)**!
