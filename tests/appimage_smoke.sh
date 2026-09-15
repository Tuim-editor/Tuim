#!/usr/bin/env bash
set -euo pipefail

appdir=${1:-Tuim.AppDir}
[[ -x "$appdir/AppRun" ]]
[[ -x "$appdir/usr/bin/tuim" ]]
[[ -x "$appdir/usr/bin/nvim" ]]
[[ -f "$appdir/usr/share/nvim/runtime/doc/help.txt" ]]
[[ -f "$appdir/tuim.desktop" ]]
[[ -f "$appdir/tuim.svg" ]]
[[ -f "$appdir/usr/share/applications/tuim.desktop" ]]
[[ -f "$appdir/usr/share/metainfo/io.github.rouboufy.tuim.metainfo.xml" ]]
[[ -f "$appdir/VERSION.txt" ]]
grep -Fq 'Bundled Neovim:' "$appdir/VERSION.txt"
grep -Fq 'Icon=tuim' "$appdir/tuim.desktop"
grep -Fq 'Terminal=true' "$appdir/tuim.desktop"

version=$("$appdir/AppRun" --version)
grep -Eq '^tuim [^[:space:]]+$' <<<"$version"
PATH=/nonexistent "$appdir/usr/bin/nvim" --clean --headless +'quit' >/dev/null

TUIM_TEST_BINARY="$appdir/AppRun" TUIM_TEST_SKIP_STARTUP_FAILURE=1 python3 tests/pty_integration.py
echo "AppImage AppDir smoke tests passed"
