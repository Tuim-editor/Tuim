#!/usr/bin/env sh
set -eu

tmp_dir="${TMPDIR:-/tmp}/tuim-onboarding-test-$$"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM
mkdir -p "$tmp_dir/data" "$tmp_dir/state" "$tmp_dir/cache"

TUIM_DISABLE_PLUGINS=1 \
TUIM_SKIP_ONBOARDING=1 \
XDG_DATA_HOME="$tmp_dir/data" \
XDG_STATE_HOME="$tmp_dir/state" \
XDG_CACHE_HOME="$tmp_dir/cache" \
nvim --headless --clean -u src/nvim/tuim_init.lua -l tests/onboarding.lua
