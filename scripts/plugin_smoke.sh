#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${1:-${XDG_DATA_HOME:-$HOME/.local/share}/tuim/lazy}"
if [ ! -d "$PLUGIN_ROOT" ]; then
    echo "Tuim plugin directory not found: $PLUGIN_ROOT" >&2
    echo "Bootstrap plugins first, then pass the lazy directory as the first argument." >&2
    exit 1
fi

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tuim-plugin-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/data/tuim" "$TMP_DIR/config" "$TMP_DIR/state" "$TMP_DIR/cache"
ln -s "$PLUGIN_ROOT" "$TMP_DIR/data/tuim/lazy"

XDG_CONFIG_HOME="$TMP_DIR/config" \
XDG_DATA_HOME="$TMP_DIR/data" \
XDG_STATE_HOME="$TMP_DIR/state" \
XDG_CACHE_HOME="$TMP_DIR/cache" \
NVIM_APPNAME=tuim \
nvim --clean --headless \
    -c "lua vim.rpcnotify = function() return true end; vim.g.tuim_is_terminal = true" \
    -c "luafile src/nvim/tuim_init.lua" \
    -c "lua vim.opt.rtp:prepend(vim.fn.stdpath('data') .. '/lazy/blink.cmp')" \
    -c "lua local ok,err=pcall(function() for _,m in ipairs({'lazy','alpha','telescope','mason','blink.cmp','harpoon.mark'}) do assert(require(m), 'failed to load '..m) end end); if not ok then print(err); vim.cmd('cq') else print('TUIM_PLUGIN_SMOKE_OK') end" \
    -c qa
