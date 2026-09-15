#!/usr/bin/env sh
set -eu

script_dir=$(dirname -- "$0")
root=$(cd -- "$script_dir/.." && pwd)
mode=${1:-host}
cd "$root"

case "$mode" in
  host) python3 tests/pty_integration.py ;;
  tmux)
    command -v tmux >/dev/null 2>&1 || { echo "tmux is required" >&2; exit 77; }
    socket="tuim-smoke-$$"
    session="tuim-smoke"
    cleanup() { tmux -L "$socket" kill-server >/dev/null 2>&1 || true; }
    trap cleanup EXIT INT TERM
    tmux -L "$socket" -f /dev/null new-session -d -s "$session" \
      "cd '$root' && python3 tests/pty_integration.py" \; \
      set-option -t "$session" remain-on-exit on
    attempts=0
    while [ "$(tmux -L "$socket" display-message -p -t "$session" '#{pane_dead}')" != "1" ]; do
      attempts=$((attempts + 1))
      [ "$attempts" -lt 300 ] || { echo "tmux smoke test timed out" >&2; exit 1; }
      sleep 0.1
    done
    status=$(tmux -L "$socket" display-message -p -t "$session" '#{pane_dead_status}')
    tmux -L "$socket" capture-pane -p -t "$session" -S -30
    [ "$status" = "0" ] || exit "$status"
    ;;
  ssh)
    command -v ssh >/dev/null 2>&1 || { echo "ssh is required" >&2; exit 77; }
    command -v sshd >/dev/null 2>&1 || { echo "sshd is required" >&2; exit 77; }
    sshd_path=$(command -v sshd)
    temp=$(mktemp -d "${TMPDIR:-/tmp}/tuim-ssh-smoke.XXXXXX")
    cleanup() {
      [ ! -f "$temp/sshd.pid" ] || kill "$(cat "$temp/sshd.pid")" >/dev/null 2>&1 || true
      rm -rf "$temp"
    }
    trap cleanup EXIT INT TERM
    ssh-keygen -q -t ed25519 -N '' -f "$temp/host_key"
    ssh-keygen -q -t ed25519 -N '' -f "$temp/client_key"
    cp "$temp/client_key.pub" "$temp/authorized_keys"
    port=$((22000 + ($$ % 1000)))
    user=$(id -un)
    {
      printf 'Port %s\n' "$port"
      printf 'ListenAddress 127.0.0.1\n'
      printf 'HostKey %s/host_key\n' "$temp"
      printf 'PidFile %s/sshd.pid\n' "$temp"
      printf 'AuthorizedKeysFile %s/authorized_keys\n' "$temp"
      printf 'StrictModes no\nPasswordAuthentication no\nKbdInteractiveAuthentication no\n'
      printf 'UsePAM no\nPermitRootLogin no\nAllowUsers %s\n' "$user"
    } >"$temp/sshd_config"
    "$sshd_path" -f "$temp/sshd_config" -E "$temp/sshd.log"
    attempts=0
    while ! kill -0 "$(cat "$temp/sshd.pid" 2>/dev/null)" 2>/dev/null; do
      attempts=$((attempts + 1))
      [ "$attempts" -lt 50 ] || { cat "$temp/sshd.log" >&2; exit 1; }
      sleep 0.1
    done
    ssh -tt -p "$port" -i "$temp/client_key" \
      -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      "$user@127.0.0.1" "cd '$root' && tests/terminal_compat.sh host"
    ;;
  *) echo "usage: $0 [host|tmux|ssh]" >&2; exit 2 ;;
esac
