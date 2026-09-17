# Installation Guide

Tuim is designed to be self-contained and easy to set up. On Linux and macOS, release bundles include a private Neovim runtime, meaning you do **not** need to install or configure Neovim or Zig on your host system to use Tuim.

---

## 1. Recommended One-Line Installer

The fastest and most reliable way to install Tuim on Linux or macOS is using the official installer script:

```bash
curl -fsSL https://raw.githubusercontent.com/Rouboufy/tuim/main/setup.sh | bash
```

Once installation finishes, run:

```bash
tuim
```

> [!NOTE]
> If the `tuim` command is not recognized, ensure `~/.local/bin` is added to your shell's `PATH`. For example, in `~/.bashrc` or `~/.zshrc`:
> ```bash
> export PATH="$HOME/.local/bin:$PATH"
> ```

### What the Installer Does

1. **Detects Platform & Architecture**: Automatically determines whether you are running Linux (x86_64 or ARM64) or macOS (Apple Silicon or Intel).
2. **Downloads & Verifies Release Bundle**: Fetches the latest matching pre-compiled release archive and verifies its SHA-256 checksum against `SHA256SUMS`.
3. **Checks System Dependencies**: Checks for missing system utilities (Git, Python 3, ripgrep, C compiler, Make, unzip) and asks for permission to install them using your system package manager (`apt`, `pacman`, `dnf`, `zypper`, or `brew`).
4. **Installs Private Tree-sitter CLI**: If your host Tree-sitter CLI is older than 0.26.1, setup installs an isolated private binary under `~/.local/share/tuim/tools/bin`.
5. **Bootstraps Plugins & Highlighting**: Installs bundled plugins and precompiles 19 core Treesitter grammars (Zig, Rust, Python, C, C++, Lua, JavaScript, TypeScript, Markdown, etc.).
6. **Creates Symlink**: Links the executable launcher at `~/.local/bin/tuim`.

### Installer Command-Line Flags

You can customize the installer's behavior by passing arguments:

```bash
# Automated, non-interactive installation
curl -fsSL https://raw.githubusercontent.com/Rouboufy/tuim/main/setup.sh | bash -s -- --yes

# Preview actions without making changes
curl -fsSL https://raw.githubusercontent.com/Rouboufy/tuim/main/setup.sh | bash -s -- --dry-run

# Skip plugin and Treesitter parser bootstrap (faster initial install)
curl -fsSL https://raw.githubusercontent.com/Rouboufy/tuim/main/setup.sh | bash -s -- --no-plugins

# Build directly from source instead of downloading a pre-built bundle
curl -fsSL https://raw.githubusercontent.com/Rouboufy/tuim/main/setup.sh | bash -s -- --source
```

| Flag | Description |
| :--- | :--- |
| `--yes` | Automatically answers "yes" to package installation prompts. |
| `--dry-run` | Prints planned downloads, file operations, and package manager actions without executing them. |
| `--no-plugins` | Skips plugin downloading, lazy.nvim bootstrap, and Treesitter grammar compilation. |
| `--source` | Clones the repository and compiles Tuim locally. |

---

## 2. Portable Linux AppImage

If you prefer a single portable executable or are in a restricted environment, Tuim provides an official x86-64 Linux AppImage:

1. Download the latest AppImage and checksum from [GitHub Releases](https://github.com/Rouboufy/tuim/releases/latest):
   ```bash
   wget https://github.com/Rouboufy/tuim/releases/latest/download/Tuim-linux-x86_64.AppImage
   chmod +x Tuim-linux-x86_64.AppImage
   ```
2. Move it to a directory in your `PATH`:
   ```bash
   mv Tuim-linux-x86_64.AppImage ~/.local/bin/tuim
   ```
3. Run Tuim:
   ```bash
   tuim
   ```

> [!TIP]
> **FUSE-less Environments (Containers / Remote Servers)**:
> If your system lacks FUSE support, you can run the AppImage with:
> ```bash
> ./Tuim-linux-x86_64.AppImage --appimage-extract-and-run
> ```

---

## 3. Pre-Compiled Native Archives

Manual release archives are available on the [GitHub Releases page](https://github.com/Rouboufy/tuim/releases/latest) for:
* `tuim-linux-x86_64.tar.gz`
* `tuim-linux-aarch64.tar.gz`
* `tuim-macos-aarch64.tar.gz` (Apple Silicon)
* `tuim-macos-x86_64.tar.gz` (Intel Mac)

Each archive contains:
* The native `tuim` binary
* The launcher script
* An embedded, isolated Neovim runtime (`lib/tuim/nvim`)
* Shipped initialization script (`lib/tuim/tuim_init.lua`)

*(Desktop integration files `tuim.desktop` and SVG icons are packaged in the Linux AppImage and available in the source repository under `packaging/`).*

To install manually, extract the archive and symlink the binary:
```bash
tar -xzf tuim-linux-x86_64.tar.gz
cd tuim-linux-x86_64
mkdir -p ~/.local/bin ~/.local/share/tuim
cp -r * ~/.local/share/tuim/
ln -sf ~/.local/share/tuim/bin/tuim ~/.local/bin/tuim
```

---

## 4. Building from Source

If you are on an unsupported platform or developing Tuim, you can build from source.

### Prerequisites
* **Zig 0.16.0** (Tuim requires this exact compiler version)
* **Neovim 0.12.0 or newer**
* **Git**
* **Python 3** (used for extension catalog searches and plugin management)
* A C compiler (`gcc` or `clang`) and `make` (for compiling Treesitter parsers)

### Build Instructions

```bash
# Clone the repository
git clone https://github.com/Rouboufy/tuim.git
cd tuim

# Build release binary
zig build -Doptimize=ReleaseFast

# Run Tuim directly
./zig-out/bin/tuim
```

For automated user-local source installation (which automatically downloads a verified Zig 0.16.0 toolchain and Neovim if missing):
```bash
bash setup.sh --source --yes
```

---

## Platform Support Summary

| Platform | Tier | Notes |
| :--- | :--- | :--- |
| **Linux (x86_64, ARM64)** | Tier 1 (Primary) | Full continuous integration testing, native bundles, AppImage. |
| **macOS (Apple Silicon & Intel)** | Tier 2 | Native bundles available. Tested via Homebrew on macOS CI. |
| **WSL (Windows Subsystem for Linux)** | Tier 2 | Supported under WSL2; requires truecolor terminal (Windows Terminal). |

---

## Next Steps

Once installed, check out the **[Quick Start Guide](Quick-Start.md)** to learn about the interface and onboarding wizard!
