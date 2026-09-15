#!/usr/bin/env bash
set -euo pipefail

REPO="Rouboufy/tuim"
ZIG_VERSION="0.16.0"
NEOVIM_VERSION="0.12.4"
TREESITTER_VERSION="0.26.1"
DRY_RUN=false
NO_PLUGINS=false
SOURCE_BUILD=false
ASSUME_YES=false

usage() {
    cat <<'EOF'
Usage: setup.sh [options]

  --dry-run       Show the installation plan without changing files or packages.
  --no-plugins    Skip plugin/parser bootstrap and parser build dependencies.
  --source        Build from source; install a private Zig/Neovim if needed.
  --yes           Install missing system dependencies without prompting.
  -h, --help      Show this help.

Release bundles include Neovim. By default setup installs the tools needed for
plugins, Treesitter parsers, project search, and the Extension Shop, then waits
for plugin and parser installation to finish. User settings are preserved.
EOF
}
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;; --no-plugins) NO_PLUGINS=true ;;
        --source) SOURCE_BUILD=true ;; --yes) ASSUME_YES=true ;;
        -h|--help) usage; exit 0 ;; *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
    esac
done
run() {
    printf '+ '; printf '%q ' "$@"; printf '\n'
    if ! $DRY_RUN; then "$@"; fi
}
report_update_progress() {
    $DRY_RUN && return 0
    local progress_file="${TUIM_UPDATE_PROGRESS_FILE:-}"
    [ -n "$progress_file" ] || return 0
    printf '%s\n' "$1" >"${progress_file}.tmp.$$"
    mv -f "${progress_file}.tmp.$$" "$progress_file"
}
version_at_least() {
    # BSD sort has no -V; compare numeric components using Bash on every platform.
    local a b c x y z
    IFS=. read -r a b c <<<"${1%%-*}"
    IFS=. read -r x y z <<<"${2%%-*}"
    [[ "$a.${b:-0}.${c:-0}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    (( a > x || (a == x && ${b:-0} > ${y:-0}) || (a == x && ${b:-0} == ${y:-0} && ${c:-0} >= ${z:-0}) ))
}
hash_file() { python3 - "$1" <<'PY'
import hashlib, sys
with open(sys.argv[1], 'rb') as file:
    print(hashlib.file_digest(file, 'sha256').hexdigest() if hasattr(hashlib, 'file_digest') else hashlib.sha256(file.read()).hexdigest())
PY
}
OS_NAME="${TUIM_TEST_PLATFORM:-$(uname -s)}"
ARCH="${TUIM_TEST_ARCH:-$(uname -m)}"
case "$ARCH" in amd64) ARCH=x86_64 ;; arm64) ARCH=aarch64 ;; esac
case "$OS_NAME/$ARCH" in
    Linux/x86_64) PLATFORM=linux; TS_ARCH=x64; NVIM_ARCH=x86_64 ;;
    Linux/aarch64) PLATFORM=linux; TS_ARCH=arm64; NVIM_ARCH=arm64 ;;
    Darwin/x86_64) PLATFORM=macos; TS_ARCH=x64; NVIM_ARCH=x86_64 ;;
    Darwin/aarch64) PLATFORM=macos; TS_ARCH=arm64; NVIM_ARCH=arm64 ;;
    *)
        if $SOURCE_BUILD && { [ "$OS_NAME" = Linux ] || [ "$OS_NAME" = Darwin ]; }; then
            PLATFORM=linux; [ "$OS_NAME" != Darwin ] || PLATFORM=macos
            TS_ARCH=$ARCH; NVIM_ARCH=$ARCH
        else
            echo "No native release for $OS_NAME/$ARCH. Use --source with compatible local tools." >&2; exit 1
        fi ;;

esac
RELEASE_ASSET="tuim-$PLATFORM-$ARCH.tar.gz"
if [ "${TUIM_TEST_ONLY:-}" = release ]; then printf '%s\n' "$RELEASE_ASSET"; exit 0; fi

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tuim"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/tuim"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/tuim"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/tuim"
BIN_DIR="$HOME/.local/bin"
TOOLS_DIR="$DATA_DIR/tools"
export PATH="$TOOLS_DIR/bin:$PATH"
if [ "$OS_NAME" = Darwin ]; then
    for brew_prefix in "${HOMEBREW_PREFIX:-/opt/homebrew}" /opt/homebrew /usr/local; do
        if [ -x "$brew_prefix/bin/brew" ]; then export PATH="$brew_prefix/bin:$PATH"; break; fi
    done
fi
IS_WSL=false
if [ "${TUIM_TEST_WSL:-0}" = 1 ] || { [ "$OS_NAME" = Linux ] && grep -qi microsoft /proc/version 2>/dev/null; }; then IS_WSL=true; fi

MISSING=()
probe_dependencies() {
    MISSING=()
    for dependency in curl python3 tar gzip; do
        command -v "$dependency" >/dev/null 2>&1 || MISSING+=("$dependency")
    done
    if $SOURCE_BUILD || ! $NO_PLUGINS; then
        git --version >/dev/null 2>&1 || MISSING+=(git)
    fi
    if $SOURCE_BUILD; then command -v xz >/dev/null 2>&1 || MISSING+=(xz); fi
    if ! $NO_PLUGINS; then
        for dependency in cc make unzip rg; do
            command -v "$dependency" >/dev/null 2>&1 || MISSING+=("$dependency")
        done
        if [ "$OS_NAME" = Darwin ] && command -v cc >/dev/null 2>&1 && ! xcrun --find clang >/dev/null 2>&1; then
            MISSING+=(cc)
        fi
    fi
}
probe_dependencies
if [ "${TUIM_TEST_MISSING+x}" ]; then read -r -a MISSING <<<"$TUIM_TEST_MISSING" || true; fi

install_dependencies() {
    local manager="${TUIM_TEST_PACKAGE_MANAGER:-}" dependency
    local packages=() privilege=()
    if [ -z "$manager" ]; then
        if [ "$OS_NAME" = Darwin ]; then manager=brew
        else
            for candidate in apt-get pacman dnf zypper; do
                if command -v "$candidate" >/dev/null 2>&1; then manager=$candidate; break; fi
            done
        fi
    fi
    [ "$manager" != apt ] || manager=apt-get
    for dependency in "${MISSING[@]}"; do
        case "$manager/$dependency" in
            apt-get/cc) packages+=(gcc) ;; pacman/cc|dnf/cc|zypper/cc) packages+=(gcc) ;;
            brew/cc)
                echo "Apple's Command Line Tools are required to compile parsers."
                run xcode-select --install
                if ! $DRY_RUN; then
                    echo "Complete the macOS installer, then rerun setup.sh." >&2; exit 1
                fi ;;
            pacman/python3|brew/python3) packages+=(python) ;;
            */rg) packages+=(ripgrep) ;; apt-get/xz) packages+=(xz-utils) ;;
            */nvim|*/neovim*) packages+=(neovim) ;;
            */curl|*/git|*/python3|*/tar|*/gzip|*/make|*/unzip|*/xz) packages+=("$dependency") ;;
            *) echo "No package mapping for $manager/$dependency" >&2; exit 1 ;;
        esac
    done
    [ ${#packages[@]} -gt 0 ] || return 0
    if [ "$manager" != brew ] && [ "$EUID" -ne 0 ]; then
        command -v sudo >/dev/null 2>&1 || { echo "Install sudo or run the package commands as root." >&2; exit 1; }
        privilege=(sudo)
    fi
    case "$manager" in
        apt-get) run "${privilege[@]}" apt-get update; run "${privilege[@]}" apt-get install -y "${packages[@]}" ;;
        pacman) run "${privilege[@]}" pacman -S --needed --noconfirm "${packages[@]}" ;;
        dnf|zypper) run "${privilege[@]}" "$manager" install -y "${packages[@]}" ;;
        brew)
            if ! command -v brew >/dev/null 2>&1 && ! $DRY_RUN; then
                echo "Install Homebrew (https://brew.sh) and rerun setup.sh." >&2; exit 1
            fi
            run brew install "${packages[@]}" ;;
        *) echo "No supported package manager found; install: ${MISSING[*]}" >&2; exit 1 ;;
    esac
}
if [ ${#MISSING[@]} -gt 0 ]; then
    echo "Missing dependencies: ${MISSING[*]}"
    if ! $ASSUME_YES && ! $DRY_RUN; then
        if ! exec 3<>/dev/tty 2>/dev/null; then
            echo "No interactive terminal. Use --yes to install missing system dependencies." >&2; exit 1
        fi
        printf 'Install system dependencies now? [y/N] ' >&3
        if ! IFS= read -r reply <&3; then
            exec 3>&-
            echo "Could not read dependency installation consent. Use --yes or install dependencies manually." >&2; exit 1
        fi
        exec 3>&-
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            echo "Dependency installation declined. Install the missing dependencies manually or rerun with --yes." >&2; exit 1
        fi
    fi
    install_dependencies
    if ! $DRY_RUN; then
        probe_dependencies
        [ ${#MISSING[@]} -eq 0 ] || { echo "Dependencies still unavailable: ${MISSING[*]}" >&2; exit 1; }
    fi
fi
if [ "${TUIM_TEST_ONLY:-}" = 1 ]; then
    $IS_WSL && echo "WSL path detected"
    exit 0
fi

run mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$STATE_DIR" "$CACHE_DIR" "$BIN_DIR" "$TOOLS_DIR/bin"
if $DRY_RUN; then DOWNLOAD_DIR="${TMPDIR:-/tmp}/tuim-install.dry-run"
else DOWNLOAD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tuim-install.XXXXXX"); trap 'rm -rf "$DOWNLOAD_DIR"' EXIT; fi

# GitHub's asset digest verifies private tool downloads without trusting a
# distro package to provide a sufficiently recent parser generator or Neovim.
github_tool() {
    local repo=$1 tag=$2 asset=$3 target=$4 digest
    run curl -fsSL --retry 3 -o "$DOWNLOAD_DIR/tool-release.json" "https://api.github.com/repos/$repo/releases/tags/$tag"
    if ! $DRY_RUN; then
        digest=$(python3 - "$DOWNLOAD_DIR/tool-release.json" "$asset" <<'PY'
import json, re, sys
release = json.load(open(sys.argv[1]))
asset = next((a for a in release.get('assets', []) if a['name'] == sys.argv[2]), None)
digest = asset.get('digest', '') if asset else ''
if not re.fullmatch(r'sha256:[0-9a-f]{64}', digest or ''):
    sys.exit('Missing SHA-256 digest for ' + sys.argv[2])
print(digest[7:])
PY
)
    fi
    run curl -fL --retry 3 -o "$target" "https://github.com/$repo/releases/download/$tag/$asset"
    if ! $DRY_RUN; then
        [ "$(hash_file "$target")" = "$digest" ] || { echo "Checksum verification failed for $asset" >&2; exit 1; }
    fi
}

if ! $NO_PLUGINS; then
    ts_version=$(tree-sitter --version 2>/dev/null | awk '{print $2}') || ts_version=0
    if ! version_at_least "${ts_version:-0}" "$TREESITTER_VERSION"; then
        echo "Installing private Tree-sitter CLI $TREESITTER_VERSION..."
        github_tool tree-sitter/tree-sitter "v$TREESITTER_VERSION" "tree-sitter-$PLATFORM-$TS_ARCH.gz" "$DOWNLOAD_DIR/tree-sitter.gz"
        run gzip -df "$DOWNLOAD_DIR/tree-sitter.gz"
        run chmod 755 "$DOWNLOAD_DIR/tree-sitter"
        run mv -f "$DOWNLOAD_DIR/tree-sitter" "$TOOLS_DIR/bin/tree-sitter"
    fi
fi

# BASH_SOURCE is empty when the documented curl | bash command is used.
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ]; then SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); fi
SOURCE_DIR="$SCRIPT_DIR"
BOOTSTRAP_NVIM=nvim
if $SOURCE_BUILD; then
    if ! command -v zig >/dev/null 2>&1 || [ "$(zig version)" != "$ZIG_VERSION" ]; then
        echo "Installing private Zig $ZIG_VERSION..."
        run curl -fsSL --retry 3 -o "$DOWNLOAD_DIR/zig-index.json" https://ziglang.org/download/index.json
        if $DRY_RUN; then ZIG_URL="https://ziglang.org/download/$ZIG_VERSION/zig-$ARCH-$PLATFORM-$ZIG_VERSION.tar.xz"
        else
            read -r ZIG_URL ZIG_HASH < <(python3 - "$DOWNLOAD_DIR/zig-index.json" "$ZIG_VERSION" "$ARCH-$PLATFORM" <<'PY'
import json, sys
item = json.load(open(sys.argv[1]))[sys.argv[2]][sys.argv[3]]
print(item['tarball'], item['shasum'])
PY
)
        fi
        run curl -fL --retry 3 -o "$DOWNLOAD_DIR/zig.tar.xz" "$ZIG_URL"
        if ! $DRY_RUN; then
            [ "$(hash_file "$DOWNLOAD_DIR/zig.tar.xz")" = "$ZIG_HASH" ] || { echo "Zig checksum verification failed." >&2; exit 1; }
        fi
        run mkdir -p "$TOOLS_DIR/zig-$ZIG_VERSION"
        run tar -xJf "$DOWNLOAD_DIR/zig.tar.xz" --strip-components=1 -C "$TOOLS_DIR/zig-$ZIG_VERSION"
        run ln -sfn "$TOOLS_DIR/zig-$ZIG_VERSION/zig" "$TOOLS_DIR/bin/zig"
    fi
    if [ -x "$TOOLS_DIR/nvim/bin/nvim" ]; then BOOTSTRAP_NVIM="$TOOLS_DIR/nvim/bin/nvim"; fi
    nvim_version=$("$BOOTSTRAP_NVIM" --version 2>/dev/null | awk 'NR==1 { sub(/^v/, "", $2); print $2 }') || nvim_version=0
    if ! version_at_least "${nvim_version:-0}" 0.12.0; then
        echo "Installing private Neovim $NEOVIM_VERSION..."
        github_tool neovim/neovim "v$NEOVIM_VERSION" "nvim-$PLATFORM-$NVIM_ARCH.tar.gz" "$DOWNLOAD_DIR/nvim.tar.gz"
        run mkdir -p "$TOOLS_DIR/nvim"
        run tar -xzf "$DOWNLOAD_DIR/nvim.tar.gz" --strip-components=1 -C "$TOOLS_DIR/nvim"
        BOOTSTRAP_NVIM="$TOOLS_DIR/nvim/bin/nvim"
    fi
    if [ "$BOOTSTRAP_NVIM" != nvim ]; then export VIMRUNTIME="$TOOLS_DIR/nvim/share/nvim/runtime"; fi
    if [ ! -f "$SOURCE_DIR/build.zig" ]; then
        SOURCE_DIR="$DATA_DIR/repo"
        if [ -d "$SOURCE_DIR/.git" ]; then run git -C "$SOURCE_DIR" pull --ff-only
        else run git clone --depth 1 "https://github.com/$REPO.git" "$SOURCE_DIR"; fi
    fi
    report_update_progress 30
    run zig build --build-file "$SOURCE_DIR/build.zig" -Doptimize=ReleaseFast --prefix "$SOURCE_DIR/zig-out"
    INIT_PATH="$SOURCE_DIR/src/nvim/tuim_init.lua"
    # Source installs need the same private dependency path on future launches.
    if $DRY_RUN; then echo "+ write source launcher at $DATA_DIR/source-launcher"
    else
        {
            printf '#!/usr/bin/env bash\n'
            # Preserve $PATH literally for the generated launcher.
            # shellcheck disable=SC2016
            if [ "$BOOTSTRAP_NVIM" != nvim ]; then
                printf 'export PATH=%q:"$PATH"\n' "$(dirname "$BOOTSTRAP_NVIM"):$TOOLS_DIR/bin"
            else
                printf 'export PATH=%q:"$PATH"\n' "$TOOLS_DIR/bin"
            fi
            if [ "$BOOTSTRAP_NVIM" != nvim ]; then printf 'export VIMRUNTIME=%q\n' "$TOOLS_DIR/nvim/share/nvim/runtime"; fi
            printf 'exec %q "$@"\n' "$SOURCE_DIR/zig-out/bin/tuim"
        } >"$DATA_DIR/source-launcher"
        chmod 755 "$DATA_DIR/source-launcher"
    fi
    run ln -sfn "$DATA_DIR/source-launcher" "$BIN_DIR/tuim"
else
    # Resolve latest once so the archive, checksum, and fallback init use one tag.
    run curl -fsSL --retry 3 -o "$DOWNLOAD_DIR/release.json" "https://api.github.com/repos/$REPO/releases/latest"
    if $DRY_RUN; then RELEASE_TAG='<latest-tag>'
    else RELEASE_TAG=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tag_name"])' "$DOWNLOAD_DIR/release.json"); fi
    RELEASE_BASE="https://github.com/$REPO/releases/download/$RELEASE_TAG"
    report_update_progress 30
    run curl -fL --retry 3 -o "$DOWNLOAD_DIR/$RELEASE_ASSET" "$RELEASE_BASE/$RELEASE_ASSET"
    report_update_progress 65
    run curl -fL --retry 3 -o "$DOWNLOAD_DIR/SHA256SUMS" "$RELEASE_BASE/SHA256SUMS"
    report_update_progress 72
    if ! $DRY_RUN; then
        expected=$(awk -v asset="$RELEASE_ASSET" '$2 == asset || $2 == "./" asset { print $1; exit }' "$DOWNLOAD_DIR/SHA256SUMS")
        if [ -z "$expected" ] || [ "$(hash_file "$DOWNLOAD_DIR/$RELEASE_ASSET")" != "$expected" ]; then
            echo "Release checksum missing or invalid for $RELEASE_ASSET." >&2; exit 1
        fi
        tar -xzf "$DOWNLOAD_DIR/$RELEASE_ASSET" -C "$DOWNLOAD_DIR"
        BUNDLE_DIR="$DOWNLOAD_DIR/${RELEASE_ASSET%.tar.gz}"
        for executable in bin/tuim lib/tuim/tuim lib/tuim/nvim/bin/nvim; do
            [ -x "$BUNDLE_DIR/$executable" ] || { echo "Invalid release bundle: missing $executable" >&2; exit 1; }
        done
        [ -d "$BUNDLE_DIR/lib/tuim/nvim/share/nvim/runtime" ] || { echo "Neovim runtime missing from release." >&2; exit 1; }
        INSTALL_DIR="$DATA_DIR/runtime"
        BACKUP_DIR="$DATA_DIR/runtime.previous"
        rm -rf "$BACKUP_DIR"
        if [ -e "$INSTALL_DIR" ]; then mv "$INSTALL_DIR" "$BACKUP_DIR"; fi
        if ! mv "$BUNDLE_DIR" "$INSTALL_DIR"; then
            if [ -e "$BACKUP_DIR" ]; then mv "$BACKUP_DIR" "$INSTALL_DIR"; fi
            exit 1
        fi
        ln -sfn "$INSTALL_DIR/bin/tuim" "$BIN_DIR/tuim"
        rm -rf "$BACKUP_DIR"
    else
        echo "+ verify SHA256SUMS for $RELEASE_ASSET"
        echo "+ install bundled Neovim runtime from $RELEASE_ASSET"
        echo "+ link $BIN_DIR/tuim to its private launcher"
    fi
    BOOTSTRAP_NVIM="$DATA_DIR/runtime/lib/tuim/nvim/bin/nvim"
    export VIMRUNTIME="$DATA_DIR/runtime/lib/tuim/nvim/share/nvim/runtime"
    INIT_PATH="$DATA_DIR/runtime/lib/tuim/tuim_init.lua"
    if ! $NO_PLUGINS && { $DRY_RUN || [ ! -f "$INIT_PATH" ]; }; then
        # Compatibility with releases made before the init was included in bundles.
        INIT_PATH="$DOWNLOAD_DIR/tuim_init.lua"
        run curl -fsSL --retry 3 -o "$INIT_PATH" "https://raw.githubusercontent.com/$REPO/$RELEASE_TAG/src/nvim/tuim_init.lua"
    fi
fi
report_update_progress 85
if ! $NO_PLUGINS; then
    echo "Installing bundled plugins and Treesitter parsers (this may take a few minutes)..."
    if ! $DRY_RUN; then
        cat >"$DOWNLOAD_DIR/bootstrap.lua" <<'LUA'
local ok, err = xpcall(function()
    vim.rpcnotify = function() return true end
    dofile(vim.env.TUIM_INIT_PATH)
    assert(not vim.g.tuim_plugins_disabled, 'Plugin bootstrap failed; check Git and network access')
    require('lazy').sync({ wait = true, show = false })
    require('lazy').load({ plugins = { 'nvim-treesitter', 'vscode.nvim' } })
    local ts = require('nvim-treesitter')
    ts.setup({ install_dir = vim.fn.stdpath('data') .. '/site' })
    local parsers = _G.tuim_default_parsers or { 'bash', 'c', 'cpp', 'css', 'go', 'html', 'javascript', 'json', 'lua', 'markdown', 'markdown_inline', 'python', 'query', 'rust', 'tsx', 'typescript', 'vim', 'vimdoc', 'zig' }
    ts.install(parsers):wait(300000)
    vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/site")
    for _, lang in ipairs(parsers) do
        assert(vim.treesitter.language.add(lang), 'Missing Treesitter parser: ' .. lang)
        assert(vim.treesitter.query.get(lang, 'highlights'), 'Missing highlights: ' .. lang)
    end
    for name, plugin in pairs(require('lazy.core.config').plugins) do
        if plugin._.installed == false then error('Plugin not installed: ' .. name) end
        for _, task in ipairs(plugin._.tasks or {}) do
            assert(not task:has_errors(), 'Plugin task failed: ' .. name)
        end
    end
end, debug.traceback)
if not ok then
    io.stderr:write(tostring(err), '\n')
    vim.cmd('cquit 1')
end
print('Tuim plugins and Treesitter parsers are ready.')
vim.cmd('qa!')
LUA
    fi
    run env -u TUIM_DISABLE_PLUGINS NVIM_APPNAME=tuim TUIM_SKIP_ONBOARDING=1 TUIM_INIT_PATH="$INIT_PATH" \
        "$BOOTSTRAP_NVIM" --clean --headless -l "$DOWNLOAD_DIR/bootstrap.lua"
fi
if $DRY_RUN; then echo "Dry run complete; no files or packages were changed."
else report_update_progress 100; echo "Tuim installed at $BIN_DIR/tuim"; fi
$IS_WSL && echo "WSL detected; clipboard behavior depends on Windows Terminal and WSL integration."
[[ ":$PATH:" = *":$BIN_DIR:"* ]] || echo "Add $BIN_DIR to PATH."
