#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
binary=${TUIM_CAPTURE_BINARY:-$root/zig-out/bin/tuim}
output=${TUIM_CAPTURE_OUTPUT:-$root/docs/media}
socket="tuim-capture-$$"
session=tuim-capture
temp=$(mktemp -d "${TMPDIR:-/tmp}/tuim-capture.XXXXXX")
cleanup() { tmux -L "$socket" kill-server >/dev/null 2>&1 || true; rm -rf "$temp"; }
trap cleanup EXIT INT TERM
mkdir -p "$output"

capture() {
    local name=$1 mode=$2 action=${3:-}
    if [[ -n "${TUIM_CAPTURE_ONLY:-}" && "$TUIM_CAPTURE_ONLY" != "$name" ]]; then return; fi
    local home="$temp/$name"
    mkdir -p "$home/data/tuim" "$home/config" "$home/state" "$home/cache"
    printf '{"mode":"%s","nerd_fonts":false}\n' "$mode" >"$home/data/tuim/settings.json"
    local plugin_flag="TUIM_DISABLE_PLUGINS=1"
    local start_view=""
    local file_arg=""
    local launch_dir="$home"
    if [[ "$action" == diagnostics || "$action" == completion ]]; then
        [[ -d "$HOME/.local/share/tuim/lazy" && -d "$HOME/.local/share/tuim/mason" ]] || { echo "Installed Tuim plugins and Mason tools are required for $action" >&2; return 1; }
        ln -s "$HOME/.local/share/tuim/lazy" "$home/data/tuim/lazy"
        ln -s "$HOME/.local/share/tuim/mason" "$home/data/tuim/mason"
        launch_dir="$temp/$name-project"
        mkdir -p "$launch_dir"
        printf '{}\n' >"$launch_dir/.luarc.json"
        if [[ "$action" == diagnostics ]]; then
            cat >"$launch_dir/demo.lua" <<'EOF'
---@type string
local message = 42
print(message)
EOF
        else
            printf 'local value = vim.api.nvim\n' >"$launch_dir/demo.lua"
        fi
        plugin_flag=""
        file_arg="'$launch_dir/demo.lua'"
    fi
    if [[ "$action" == extensions ]]; then
        [[ -f "$HOME/.local/share/tuim/store_db.json" ]] || { echo "A cached Extension Shop catalog is required" >&2; return 1; }
        mkdir -p "$home/.local/share/tuim"
        cp "$HOME/.local/share/tuim/store_db.json" "$home/.local/share/tuim/store_db.json"
        start_view="TUIM_START_VIEW=extensions"
    fi
    tmux -L "$socket" -f /dev/null new-session -d -s "$session" -x 120 -y 36 \
        "cd '$launch_dir' && env HOME='$home' XDG_CONFIG_HOME='$home/config' XDG_DATA_HOME='$home/data' XDG_STATE_HOME='$home/state' XDG_CACHE_HOME='$home/cache' $plugin_flag $start_view TUIM_SKIP_ONBOARDING=1 TERM=xterm-256color '$binary' $file_arg"
    sleep 1
    case "$action" in
        type)
            tmux -L "$socket" send-keys -t "$session" C-n
            sleep 0.5
            tmux -L "$socket" send-keys -t "$session" "Welcome to Tuim — modeless editing" Enter
            ;;
        settings) tmux -L "$socket" send-keys -l -t "$session" $'\e[<0;3;34M\e[<0;3;34m' ;;
        ai)
            tmux -L "$socket" send-keys -t "$session" C-e
            sleep 0.2
            tmux -L "$socket" send-keys -t "$session" C-e
            for _ in 1 2 3 4; do sleep 0.3; tmux -L "$socket" send-keys -t "$session" Tab; done
            ;;
        extensions) tmux -L "$socket" send-keys -t "$session" Enter ;;
        git) tmux -L "$socket" send-keys -l -t "$session" $'\e[<0;3;8M\e[<0;3;8m' ;;
        terminal) tmux -L "$socket" send-keys -t "$session" C-t ;;
        diagnostics) sleep 4 ;;
        completion)
            sleep 3
            tmux -L "$socket" send-keys -t "$session" : "lua vim.cmd('startinsert');vim.schedule(function()require('blink.cmp').show()end)"
            sleep 0.5
            tmux -L "$socket" send-keys -t "$session" Enter
            sleep 2
            ;;
    esac
    sleep 1
    tmux -L "$socket" capture-pane -p -t "$session" >"$output/$name.txt"
    python3 "$root/scripts/terminal_capture_to_svg.py" "$output/$name.txt" "$output/$name.svg" "Tuim — $name"
    python3 - "$output/$name.txt" "$output/$name.cast" "$name" <<'PY'
import json, pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
header = {"version": 2, "width": 120, "height": 36, "timestamp": 0, "env": {"TERM": "xterm-256color", "SHELL": "/bin/sh"}, "title": f"Tuim — {sys.argv[3]}"}
pathlib.Path(sys.argv[2]).write_text(json.dumps(header) + "\n" + json.dumps([0.2, "o", "\u001b[2J\u001b[H" + text]) + "\n", encoding="utf-8")
PY
    tmux -L "$socket" kill-session -t "$session"
}

capture normal normal
capture ide ide type
capture zen zen
capture settings normal settings
capture ai normal ai
capture extensions normal extensions
capture git normal git
capture terminal normal terminal
capture diagnostics normal diagnostics
capture completion normal completion

cat >"$output/README.md" <<'EOF'
# Generated Tuim media

These SVG screenshots and asciinema v2 recordings are generated from the real
Tuim binary at 120×36 cells with portable symbols. Regenerate after visible UI
changes with `scripts/capture_media.sh`; do not hand-edit generated assets.

The set includes Normal, IDE, Zen, Settings, Git, AI actions, Extension Shop, integrated
terminal, diagnostics, and completion sessions. SVG files are lightweight
documentation screenshots; matching `.cast` files work with asciinema v2
players. `.txt` files preserve the captured terminal cells for review and
diffing. Diagnostics and completion use the locally installed Tuim plugin and
Mason trees with a generated Lua project; all other captures use offline mode.
EOF
echo "Captured Tuim media in $output"
