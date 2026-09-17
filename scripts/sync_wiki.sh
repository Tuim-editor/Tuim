#!/usr/bin/env bash
# scripts/sync_wiki.sh - Sync local wiki/ directory to GitHub Wiki repository
set -euo pipefail

REPO_URL="${1:-https://github.com/Rouboufy/tuim.wiki.git}"
TEMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "=== Syncing Tuim Wiki to ${REPO_URL} ==="

if ! git clone "$REPO_URL" "$TEMP_DIR"; then
    echo "Warning: Could not clone $REPO_URL (wiki may not be initialized yet on GitHub)."
    echo "To initialize: Visit https://github.com/Rouboufy/tuim/wiki and create the first page."
    exit 1
fi

# Copy all wiki markdown files and directories
cp -R wiki/. "$TEMP_DIR/"

cd "$TEMP_DIR"
git add .
if git diff --staged --quiet; then
    echo "No wiki changes to commit. Everything is up to date!"
else
    git commit -m "docs(wiki): update wiki documentation"
    echo "Ready to push. Run: git push origin master (or main)"
    git push origin HEAD
    echo "=== Wiki successfully synchronized! ==="
fi
