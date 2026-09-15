#!/bin/sh
set -u

status_file=$1
log_file=$2
progress_file=$3
exec >"$log_file" 2>&1

result=failure
tmp_dir=

progress() {
    progress_tmp="$progress_file.tmp.$$"
    printf '%s\n' "$1" >"$progress_tmp" && mv -f "$progress_tmp" "$progress_file"
}

cleanup() {
    if [ "$result" = success ]; then progress 100; fi
    printf '%s\n' "$result" >"$status_file"
    [ -z "$tmp_dir" ] || rm -rf "$tmp_dir"
}

trap cleanup EXIT INT TERM
progress 2
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tuim-software-update.XXXXXX") || exit 1

if [ -n "${APPIMAGE:-}" ] && [ -f "$APPIMAGE" ]; then
    asset=Tuim-linux-x86_64.AppImage
    release=https://github.com/Rouboufy/tuim/releases/latest/download
    progress 10
    if curl -fsSL --retry 3 -o "$tmp_dir/$asset" "$release/$asset"; then
        progress 65
        if curl -fsSL --retry 3 -o "$tmp_dir/SHA256SUMS" "$release/SHA256SUMS"; then
            progress 75
            expected=$(awk -v asset="$asset" '$2 == asset || $2 == "./" asset { print $1; exit }' "$tmp_dir/SHA256SUMS")
            actual=$(sha256sum "$tmp_dir/$asset" | awk '{print $1}')
            progress 85
            if [ -n "$expected" ] && [ "$actual" = "$expected" ] &&
                cp "$tmp_dir/$asset" "$APPIMAGE.new" && chmod 755 "$APPIMAGE.new"; then
                progress 95
                if mv -f "$APPIMAGE.new" "$APPIMAGE"; then result=success; fi
            fi
            if [ "$result" != success ]; then rm -f "$APPIMAGE.new"; fi
        fi
    fi
else
    progress 10
    if curl -fsSL --retry 3 -o "$tmp_dir/setup.sh" "https://raw.githubusercontent.com/Rouboufy/tuim/main/setup.sh"; then
        progress 20
        if TUIM_UPDATE_PROGRESS_FILE="$progress_file" bash "$tmp_dir/setup.sh" --no-plugins; then
            result=success
        fi
    fi
fi
