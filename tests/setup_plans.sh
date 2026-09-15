#!/usr/bin/env bash
set -euo pipefail

check_plan() {
    local platform=$1 manager=$2 expected=$3
    local output
    output=$(TUIM_TEST_PLATFORM="$platform" TUIM_TEST_PACKAGE_MANAGER="$manager" \
        TUIM_TEST_MISSING="curl nvim git" TUIM_TEST_ONLY=1 \
        bash setup.sh --dry-run --yes --no-plugins)
    grep -Fq "$expected" <<< "$output"
    grep -Fq "curl neovim git" <<< "$output"
}

check_plan Linux apt "apt-get install"
check_plan Linux pacman "pacman -S"
check_plan Linux dnf "dnf install"
check_plan Linux zypper "zypper install"
check_plan Darwin brew "brew install"
for manager in apt pacman dnf zypper; do
    tools_output=$(TUIM_TEST_PLATFORM=Linux TUIM_TEST_PACKAGE_MANAGER="$manager" \
        TUIM_TEST_MISSING="python3 cc make unzip rg tar gzip" TUIM_TEST_ONLY=1 \
        bash setup.sh --dry-run --yes)
    grep -Fq gcc <<< "$tools_output"
    grep -Fq ripgrep <<< "$tools_output"
    grep -Fq unzip <<< "$tools_output"
done

wsl_output=$(TUIM_TEST_PLATFORM=Linux TUIM_TEST_PACKAGE_MANAGER=apt TUIM_TEST_WSL=1 \
    TUIM_TEST_MISSING="curl nvim git" TUIM_TEST_ONLY=1 \
    bash setup.sh --dry-run --yes --no-plugins)
grep -Fq "WSL path detected" <<< "$wsl_output"

check_asset() {
    local platform=$1 arch=$2 expected=$3
    local output
    output=$(TUIM_TEST_PLATFORM="$platform" TUIM_TEST_ARCH="$arch" \
        TUIM_TEST_MISSING="" TUIM_TEST_ONLY=release bash setup.sh)
    [ "$output" = "$expected" ]
}

check_asset Linux x86_64 tuim-linux-x86_64.tar.gz
check_asset Linux aarch64 tuim-linux-aarch64.tar.gz
check_asset Darwin x86_64 tuim-macos-x86_64.tar.gz
check_asset Darwin arm64 tuim-macos-aarch64.tar.gz

progress_file=$(mktemp "${TMPDIR:-/tmp}/tuim-setup-progress.XXXXXX")
fixture_dir=$(mktemp -d "${TMPDIR:-/tmp}/tuim-setup-tests.XXXXXX")
trap 'rm -f "$progress_file"; rm -rf "$fixture_dir"' EXIT
TUIM_TEST_PLATFORM=Linux TUIM_TEST_ARCH=x86_64 TUIM_UPDATE_PROGRESS_FILE="$progress_file" \
    bash setup.sh --dry-run --no-plugins >/dev/null
[ ! -s "$progress_file" ] # --dry-run must not write update progress

# Simulate macOS with Homebrew installed outside PATH and a broken system Git
# shim. No host package manager or network access is used.
bash_bin=$(command -v bash)
mkdir -p "$fixture_dir/bin" "$fixture_dir/homebrew/bin"
for utility in uname dirname grep awk; do
    ln -s "$(command -v "$utility")" "$fixture_dir/bin/$utility"
done
for utility in python3 tar gzip make unzip rg cc xcrun; do
    printf '#!/bin/sh\nexit 0\n' > "$fixture_dir/bin/$utility"
    chmod +x "$fixture_dir/bin/$utility"
done
printf '#!/bin/sh\nexit 0\n' > "$fixture_dir/bin/curl"
printf '#!/bin/sh\nexit 1\n' > "$fixture_dir/bin/git"
printf '#!/bin/sh\nexit 0\n' > "$fixture_dir/homebrew/bin/brew"
chmod +x "$fixture_dir/bin/curl" "$fixture_dir/bin/git" "$fixture_dir/homebrew/bin/brew"
brew_output=$(PATH="$fixture_dir/bin" HOMEBREW_PREFIX="$fixture_dir/homebrew" \
    TUIM_TEST_PLATFORM=Darwin TUIM_TEST_ARCH=arm64 TUIM_TEST_ONLY=1 \
    "$bash_bin" setup.sh --dry-run --yes)
grep -Fq 'brew install git' <<< "$brew_output"
if grep -Fq neovim <<< "$brew_output"; then exit 1; fi

no_plugins_output=$(PATH="$fixture_dir/bin" HOMEBREW_PREFIX="$fixture_dir/homebrew" \
    TUIM_TEST_PLATFORM=Darwin TUIM_TEST_ARCH=arm64 TUIM_TEST_ONLY=1 \
    "$bash_bin" setup.sh --dry-run --yes --no-plugins)
[ -z "$no_plugins_output" ]

# Homebrew-provided dependencies must be visible before probing for them.
printf '#!/bin/sh\nexit 0\n' > "$fixture_dir/homebrew/bin/git"
chmod +x "$fixture_dir/homebrew/bin/git"
installed_output=$(PATH="$fixture_dir/bin" HOMEBREW_PREFIX="$fixture_dir/homebrew" \
    TUIM_TEST_PLATFORM=Darwin TUIM_TEST_ARCH=arm64 TUIM_TEST_ONLY=1 \
    "$bash_bin" setup.sh --dry-run --yes)
[ -z "$installed_output" ]

bootstrap_output=$(TUIM_TEST_PLATFORM=Darwin TUIM_TEST_ARCH=arm64 \
    XDG_DATA_HOME="$fixture_dir/data" bash setup.sh --dry-run --yes)
grep -Fq "$fixture_dir/data/tuim/runtime/lib/tuim/nvim/bin/nvim --clean --headless" <<< "$bootstrap_output"
grep -Fq tuim-macos-aarch64.tar.gz <<< "$bootstrap_output"

echo "Installer package-manager and release-asset plans passed"
