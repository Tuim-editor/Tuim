# Packaging & Releases

Tuim produces cross-platform native bundles for Linux and macOS, as well as a standalone portable Linux AppImage.

---

## 1. Native Release Bundles

For tagged releases (`v*`), Tuim compiles native archives containing:
* The optimized `tuim` binary
* The launcher script
* An embedded, isolated Neovim runtime (`lib/tuim/nvim/`)
* Shipped initialization script (`lib/tuim/tuim_init.lua`)

*(Plugins are not bundled into the archive; they are automatically bootstrapped and downloaded upon installation by `setup.sh` into `~/.local/share/tuim/lazy/`. Desktop integration files `tuim.desktop` and SVG icons are packaged in the Linux AppImage and available in the source repository under `packaging/`).*

### Release Targets
* `x86_64-linux-musl` (Statically linked Linux x86_64)
* `aarch64-linux-musl` (Statically linked Linux ARM64)
* `x86_64-macos` (Intel Mac)
* `aarch64-macos` (Apple Silicon)

All published assets and their SHA-256 checksums are documented in `SHA256SUMS`.

---

## 2. Linux AppImage Packaging

Tuim builds an official x86-64 AppImage using `build_appimage.sh`:

### Building the AppImage Locally
```bash
VERSION=0.3.0 COMMIT_SHA=$(git rev-parse HEAD) bash build_appimage.sh
```

### Verifying the Built AppImage
```bash
# Verify checksum
sha256sum -c Tuim-0.3.0-x86_64.AppImage.sha256

# Test version output without FUSE
./Tuim-0.3.0-x86_64.AppImage --appimage-extract-and-run --version

# Run full AppDir smoke suite
tests/appimage_smoke.sh Tuim.AppDir
```

The smoke test checks:
* Bundled asset integrity
* Independent Neovim discovery without relying on host `PATH`
* All editing modes (Normal, IDE, Zen)
* Paste, mouse selection, and window resizing
* Clean alternate-screen exit and terminal attribute restoration

---

## 3. GitHub Actions Release Workflow

Tagged releases (`git tag v0.3.0 && git push origin v0.3.0`) trigger `.github/workflows/release.yml`:
1. **Cross-Compilation**: Compiles release artifacts across Linux and macOS runner matrices.
2. **Neovim Bundling**: Packages a verified, private Neovim runtime into each bundle.
3. **AppImage Assembly**: Packages and signs the Linux AppImage.
4. **Checksum Generation**: Generates `SHA256SUMS` and individual `.sha256` files.
5. **Asset Publication**: Creates the GitHub Release draft and uploads all artifacts.

---

## Next Steps

Review contribution rules and pull request standards in **[Contributing Guidelines](Contributing-Guidelines.md)**.
