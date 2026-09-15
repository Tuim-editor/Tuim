#!/bin/bash
# Tuim uninstaller

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

REMOVE_BINARY=0
REMOVE_CACHE=0
REMOVE_PLUGINS=0
REMOVE_SETTINGS=0
REMOVE_LOGS=0
REMOVE_SESSIONS=0
ASSUME_YES=0

usage() {
    cat <<'EOF'
Usage: uninstall.sh [options]

Options:
  --binary     Remove ~/.local/bin/tuim
  --cache      Remove Tuim cache files
  --plugins    Remove Tuim plugin data
  --settings   Remove Tuim config files
  --logs       Remove Tuim log files
  --sessions   Remove Tuim session files
  --all        Remove every Tuim file and directory
  --yes        Skip the confirmation prompt
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --binary) REMOVE_BINARY=1 ;;
        --cache) REMOVE_CACHE=1 ;;
        --plugins) REMOVE_PLUGINS=1 ;;
        --settings) REMOVE_SETTINGS=1 ;;
        --logs) REMOVE_LOGS=1 ;;
        --sessions) REMOVE_SESSIONS=1 ;;
        --all)
            REMOVE_BINARY=1
            REMOVE_CACHE=1
            REMOVE_PLUGINS=1
            REMOVE_SETTINGS=1
            REMOVE_LOGS=1
            REMOVE_SESSIONS=1
            ;;
        --yes) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
    shift
done

if [ "$REMOVE_BINARY" -eq 0 ] && [ "$REMOVE_CACHE" -eq 0 ] && [ "$REMOVE_PLUGINS" -eq 0 ] && \
   [ "$REMOVE_SETTINGS" -eq 0 ] && [ "$REMOVE_LOGS" -eq 0 ] && [ "$REMOVE_SESSIONS" -eq 0 ]; then
    REMOVE_BINARY=1
    REMOVE_CACHE=1
    REMOVE_PLUGINS=1
    REMOVE_SETTINGS=1
    REMOVE_LOGS=1
    REMOVE_SESSIONS=1
fi

declare -a paths=()
if [ "$REMOVE_BINARY" -eq 1 ]; then
    paths+=("$HOME/.local/bin/tuim")
fi
if [ "$REMOVE_SETTINGS" -eq 1 ]; then
    paths+=("${XDG_CONFIG_HOME:-$HOME/.config}/tuim")
fi
if [ "$REMOVE_PLUGINS" -eq 1 ]; then
    paths+=("${XDG_DATA_HOME:-$HOME/.local/share}/tuim")
fi
if [ "$REMOVE_CACHE" -eq 1 ]; then
    paths+=("${XDG_CACHE_HOME:-$HOME/.cache}/tuim")
fi
if [ "$REMOVE_LOGS" -eq 1 ]; then
    paths+=("${XDG_STATE_HOME:-$HOME/.local/state}/tuim/log")
fi
if [ "$REMOVE_SESSIONS" -eq 1 ]; then
    paths+=("${XDG_STATE_HOME:-$HOME/.local/state}/tuim/sessions")
fi

echo -e "${YELLOW}The following Tuim paths will be removed:${NC}"
for p in "${paths[@]}"; do
    echo "  $p"
done

if [ "$ASSUME_YES" -ne 1 ]; then
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Uninstallation cancelled."
        exit 0
    fi
fi

echo -e "${BLUE}Uninstalling Tuim...${NC}"
for p in "${paths[@]}"; do
    if [ -e "$p" ] || [ -L "$p" ]; then
        echo "Removing $p..."
        rm -rf "$p"
    fi
done

echo -e "\n${GREEN}✔ Tuim uninstall complete.${NC}"
