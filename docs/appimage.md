# AppImage packaging and verification

Tuim's x86-64 AppImage contains Tuim, Neovim 0.12.4, Neovim's runtime,
desktop metadata, an SVG icon, and AppStream metadata. It does not require host
Neovim. User data still uses Tuim's isolated XDG directories outside the
read-only image.

Tagged releases publish `Tuim-<version>-x86_64.AppImage`, its neighboring
`.sha256`, the stable updater asset `Tuim-linux-x86_64.AppImage`, and the
release-wide `SHA256SUMS`. `VERSION.txt` records the Tuim version, Git commit,
architecture, and bundled Neovim version.

The About panel's update button detects the AppImage runtime through
`$APPIMAGE`, verifies the stable asset against `SHA256SUMS`, and atomically
replaces the launched image. The image must be in a user-writable directory.
Native installations continue to update through `setup.sh`.

## Reproduce and verify

```bash
VERSION=1.2.3 COMMIT_SHA=$(git rev-parse HEAD) bash build_appimage.sh
sha256sum -c Tuim-1.2.3-x86_64.AppImage.sha256
./Tuim-1.2.3-x86_64.AppImage --appimage-extract-and-run --version
tests/appimage_smoke.sh Tuim.AppDir
```

The extraction flag works without FUSE. The smoke test checks bundled assets,
Neovim discovery without `PATH`, version metadata, all editing modes, paste,
mouse input, resize, terminal cleanup, and temporary isolated XDG paths.

## Recorded smoke tests

| Distribution | Date | Result |
| --- | --- | --- |
| Arch Linux x86-64 | 2026-07-13 | Full AppDir PTY suite and final checksum/version passed |
| Ubuntu 24.04 x86-64 | 2026-07-13 | Final image started without FUSE or host Neovim |
| Debian 12 slim x86-64 | 2026-07-13 | Final image started without FUSE or host Neovim |
