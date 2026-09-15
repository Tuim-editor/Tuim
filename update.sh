#!/bin/bash
# Tuim updater

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

FORCE_DIRTY=0
SYNC_PLUGINS=1

usage() {
    cat <<'EOF'
Usage: update.sh [--force] [--no-plugins]

--force       Rebuild even if the checkout has uncommitted changes.
--no-plugins  Skip headless Neovim plugin synchronization.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --force) FORCE_DIRTY=1 ;;
        --no-plugins) SYNC_PLUGINS=0 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
    shift
done

echo -e "${BLUE}Checking for Tuim updates...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TUIM_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/tuim"
REPO_DIR="$TUIM_DATA_HOME/repo"

if [ -d "$SCRIPT_DIR/config" ]; then
    TARGET_DIR="$SCRIPT_DIR"
    INSTALL_KIND="developer checkout"
elif [ -d "$REPO_DIR" ]; then
    TARGET_DIR="$REPO_DIR"
    INSTALL_KIND="cloned installation"
else
    TARGET_DIR="$SCRIPT_DIR"
    INSTALL_KIND="current directory"
fi

echo "Updating from $INSTALL_KIND: $TARGET_DIR"
cd "$TARGET_DIR"

if [ -d ".git" ]; then
    CURRENT_REV=$(git rev-parse --short HEAD)
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || true)
    echo "Current source revision: ${CURRENT_REV}${CURRENT_BRANCH:+ ($CURRENT_BRANCH)}"

    if [ -n "$(git status --porcelain)" ] && [ "$FORCE_DIRTY" -ne 1 ]; then
        echo -e "${RED}Refusing to update a dirty checkout. Commit, stash, or rerun with --force.${NC}"
        exit 1
    fi

    echo "Pulling latest changes from remote Git repository..."
    git pull --ff-only
    echo -e "${BLUE}Rebuilding Tuim...${NC}"
    zig build -Doptimize=ReleaseFast
else
    echo -e "${YELLOW}Warning: No git repository detected in $TARGET_DIR. Skipping git update.${NC}"
fi

if [ "$SYNC_PLUGINS" -eq 1 ] && command -v nvim &>/dev/null; then
    echo -e "${BLUE}Updating Neovim plugins...${NC}"
    NVIM_APPNAME="tuim" TUIM_INIT_PATH="$TARGET_DIR/src/nvim/tuim_init.lua" \
        nvim --clean --headless \
        -c "execute 'luafile ' .. fnameescape(\$TUIM_INIT_PATH)" \
        -c "Lazy! sync" -c "qa"
fi

echo -e "\n${GREEN}✔ Tuim updated successfully!${NC}"
