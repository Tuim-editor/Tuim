#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tuim-launcher.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM

mkdir -p "$TEST_DIR/runtime/bin" "$TEST_DIR/runtime/lib/tuim/nvim/bin"
cp "$ROOT/packaging/tuim-launcher" "$TEST_DIR/runtime/bin/tuim"
chmod 755 "$TEST_DIR/runtime/bin/tuim"
ln -s "$(command -v env)" "$TEST_DIR/runtime/lib/tuim/tuim"
ln -s "$TEST_DIR/runtime/bin/tuim" "$TEST_DIR/tuim"

OUTPUT=$("$TEST_DIR/tuim")
EXPECTED_RUNTIME=$TEST_DIR/runtime/bin/../lib/tuim

printf '%s\n' "$OUTPUT" | grep -Fqx "VIMRUNTIME=$EXPECTED_RUNTIME/nvim/share/nvim/runtime"
printf '%s\n' "$OUTPUT" | grep -Fqx "PATH=$EXPECTED_RUNTIME/nvim/bin:$PATH"

echo "Launcher symlink smoke test passed."
