#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CODEX_INSTALL_DIR:-$SCRIPT_DIR/codex-linux}"
EXTRACT_DIR="$SCRIPT_DIR/codex_extracted"
APP_SRC_DIR="$SCRIPT_DIR/codex_app_src"
ELECTRON_VERSION="40.0.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${CYAN}[*]${NC} $*"; }
success() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
fail() { echo -e "${RED}[x]${NC} $*"; exit 1; }

cleanup() {
    rm -rf "$EXTRACT_DIR" "$APP_SRC_DIR"
}

on_error() {
    fail "Install failed near line $1"
}

trap 'on_error $LINENO' ERR

print_header() {
    echo
    echo "Codex Linux Installer (Unofficial)"
    echo "Created and tested on CachyOS (Arch Linux)."
    echo
}

resolve_7zip() {
    if command -v 7z >/dev/null 2>&1; then
        echo "7z"
        return 0
    fi
    if command -v 7zz >/dev/null 2>&1; then
        echo "7zz"
        return 0
    fi
    return 1
}

check_prereqs() {
    local missing=()
    for cmd in node npm npx curl python3; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done

    if [ ${#missing[@]} -gt 0 ]; then
        fail "Missing tools: ${missing[*]}\nInstall dependencies first:\n  Arch/CachyOS: sudo pacman -S nodejs npm python curl p7zip base-devel\n  Debian/Ubuntu: sudo apt install nodejs npm python3 curl p7zip-full build-essential\n  Fedora: sudo dnf install nodejs npm python3 curl p7zip && sudo dnf groupinstall 'Development Tools'"
    fi

    if ! resolve_7zip >/dev/null; then
        fail "7zip not found (need 7z or 7zz). Install p7zip."
    fi

    if ! command -v make >/dev/null 2>&1 || ! command -v g++ >/dev/null 2>&1; then
        fail "C/C++ build tools missing (make + g++)."
    fi

    local node_major
    node_major="$(node -v | cut -d. -f1 | tr -d v)"
    if [ "$node_major" -lt 20 ]; then
        fail "Node.js 20+ required (found $(node -v))"
    fi

    success "Prerequisites look good"
}

resolve_dmg_path() {
    if [ $# -gt 0 ] && [ -f "$1" ]; then
        realpath "$1"
        return 0
    fi

    if [ -f "$SCRIPT_DIR/Codex.dmg" ]; then
        realpath "$SCRIPT_DIR/Codex.dmg"
        return 0
    fi

    local url="https://persistent.oaistatic.com/codex-app-prod/Codex.dmg"
    log "Codex.dmg not found locally. Downloading from OpenAI..."
    curl -L --progress-bar --max-time 900 --connect-timeout 30 -o "$SCRIPT_DIR/Codex.dmg" "$url"

    [ -s "$SCRIPT_DIR/Codex.dmg" ] || fail "Download failed or file is empty"
    realpath "$SCRIPT_DIR/Codex.dmg"
}

extract_dmg() {
    local dmg_path="$1"
    local seven_zip
    seven_zip="$(resolve_7zip)"

    log "Extracting DMG..."
    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"

    # DMGs often contain symlinks that make 7z return non-zero; continue and verify output.
    "$seven_zip" x "$dmg_path" -o"$EXTRACT_DIR" -y >/tmp/codex-7z.log 2>&1 || true

    local asar_path
    asar_path="$(find "$EXTRACT_DIR" -type f -name app.asar | head -1 || true)"
    [ -n "$asar_path" ] || fail "app.asar not found. Is this a valid Codex.dmg?"

    success "Found app.asar"
    echo "$asar_path"
}

extract_asar() {
    local asar_path="$1"

    log "Extracting app.asar..."
    rm -rf "$APP_SRC_DIR"
    npx --yes @electron/asar extract "$asar_path" "$APP_SRC_DIR"

    [ -d "$APP_SRC_DIR/.vite" ] || fail ".vite not found after asar extract"
    success "Application source extracted"
}

detect_native_version() {
    local module_name="$1"
    local fallback="$2"

    node - "$APP_SRC_DIR" "$module_name" "$fallback" <<'NODE'
const appSrcDir = process.argv[2];
const moduleName = process.argv[3];
const fallback = process.argv[4];
try {
  // eslint-disable-next-line import/no-dynamic-require,global-require
  const pkg = require(`${appSrcDir}/node_modules/${moduleName}/package.json`);
  process.stdout.write(String(pkg.version || fallback));
} catch {
  process.stdout.write(String(fallback));
}
NODE
}

write_package_json() {
    local bs3_version="$1"
    local npty_version="$2"

    cat > "$PROJECT_DIR/package.json" <<EOF_PKG
{
  "name": "codex-linux",
  "productName": "Codex",
  "version": "1.0.0-linux",
  "main": ".vite/build/main.js",
  "scripts": {
    "start": "electron ."
  },
  "dependencies": {
    "better-sqlite3": "${bs3_version}",
    "node-pty": "${npty_version}",
    "immer": "^10.1.1",
    "lodash": "^4.17.21",
    "memoizee": "^0.4.15",
    "mime-types": "^2.1.35",
    "shell-env": "^4.0.1",
    "shlex": "^3.0.0",
    "smol-toml": "^1.5.2",
    "zod": "^3.22.0"
  },
  "devDependencies": {
    "electron": "${ELECTRON_VERSION}",
    "@electron/rebuild": "^3.6.0"
  }
}
EOF_PKG
}

setup_project() {
    log "Preparing Linux project..."

    rm -rf "$PROJECT_DIR"
    mkdir -p "$PROJECT_DIR"

    cp -r "$APP_SRC_DIR/.vite" "$PROJECT_DIR/.vite"

    if [ -d "$APP_SRC_DIR/webview" ]; then
        cp -r "$APP_SRC_DIR/webview" "$PROJECT_DIR/webview"
    else
        local webview_path
        webview_path="$(find "$APP_SRC_DIR" -type d -name webview | head -1 || true)"
        [ -n "$webview_path" ] || fail "webview folder not found"
        cp -r "$webview_path" "$PROJECT_DIR/webview"
    fi

    cp -r "$APP_SRC_DIR/native" "$PROJECT_DIR/native" 2>/dev/null || mkdir -p "$PROJECT_DIR/native"

    local bs3_version
    local npty_version
    bs3_version="$(detect_native_version "better-sqlite3" "12.4.6")"
    npty_version="$(detect_native_version "node-pty" "1.1.0")"

    log "Native module versions: better-sqlite3@$bs3_version, node-pty@$npty_version"
    write_package_json "$bs3_version" "$npty_version"

    success "Project files ready"
}

install_node_deps() {
    log "Installing npm dependencies (this can take a few minutes)..."
    (cd "$PROJECT_DIR" && npm install)

    log "Rebuilding native modules for Electron ${ELECTRON_VERSION}..."
    (cd "$PROJECT_DIR" && npx --yes @electron/rebuild -v "$ELECTRON_VERSION" --force)

    success "Dependencies installed and rebuilt"
}

patch_macos_only_modules() {
    log "Patching macOS-only modules..."

    rm -f "$PROJECT_DIR/native/sparkle.node" 2>/dev/null || true
    rm -rf "$PROJECT_DIR/node_modules/sparkle-darwin" 2>/dev/null || true

    mkdir -p "$PROJECT_DIR/node_modules/electron-liquid-glass"
    cat > "$PROJECT_DIR/node_modules/electron-liquid-glass/index.js" <<'EOF_STUB'
const stub = {
  isGlassSupported: () => false,
  enable: () => {},
  disable: () => {},
  setOptions: () => {}
};

module.exports = stub;
module.exports.default = stub;
EOF_STUB

    cat > "$PROJECT_DIR/node_modules/electron-liquid-glass/package.json" <<'EOF_STUB_PKG'
{"name":"electron-liquid-glass","version":"1.0.0","main":"index.js"}
EOF_STUB_PKG

    success "Patched macOS-only modules"
}

create_launcher() {
    log "Creating launcher..."

    cat > "$PROJECT_DIR/codex-linux.sh" <<'EOF_LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export ELECTRON_RENDERER_URL="file://${SCRIPT_DIR}/webview/index.html"

ensure_opaque_windows() {
    local state_file="${CODEX_GLOBAL_STATE_PATH:-$HOME/.codex/.codex-global-state.json}"
    local state_dir
    state_dir="$(dirname "$state_file")"
    mkdir -p "$state_dir"

    if [ ! -f "$state_file" ]; then
        printf '{"opaqueWindows":true}\n' > "$state_file"
        return 0
    fi

    if ! command -v node >/dev/null 2>&1; then
        return 0
    fi

    node - "$state_file" <<'NODE'
const fs = require("fs");
const statePath = process.argv[2];
try {
  const raw = fs.readFileSync(statePath, "utf8");
  const data = JSON.parse(raw);
  if (data.opaqueWindows !== true) {
    data.opaqueWindows = true;
    fs.writeFileSync(statePath, JSON.stringify(data));
  }
} catch {
  // Ignore parse/write failures and launch anyway.
}
NODE
}

find_codex_cli() {
    if [ -n "${CODEX_CLI_PATH:-}" ] && [ -x "$CODEX_CLI_PATH" ]; then
        echo "$CODEX_CLI_PATH"
        return 0
    fi

    local candidate

    if command -v codex >/dev/null 2>&1; then
        candidate="$(command -v codex)"
        [ -x "$candidate" ] && { echo "$candidate"; return 0; }
    fi

    for candidate in "$HOME/.local/bin/codex" "/usr/local/bin/codex" "/usr/bin/codex"; do
        [ -x "$candidate" ] && { echo "$candidate"; return 0; }
    done

    shopt -s nullglob
    for candidate in "$HOME"/.nvm/versions/node/*/bin/codex; do
        [ -x "$candidate" ] && { echo "$candidate"; return 0; }
    done
    shopt -u nullglob

    if command -v npm >/dev/null 2>&1; then
        candidate="$(npm config get prefix 2>/dev/null)/bin/codex"
        [ -x "$candidate" ] && { echo "$candidate"; return 0; }
    fi

    return 1
}

CODEX_CLI_PATH_RESOLVED="$(find_codex_cli || true)"
if [ -z "$CODEX_CLI_PATH_RESOLVED" ]; then
    echo "Error: Unable to locate Codex CLI binary."
    echo "Install with: npm install -g @openai/codex"
    exit 1
fi
export CODEX_CLI_PATH="$CODEX_CLI_PATH_RESOLVED"

if [ "${CODEX_FORCE_OPAQUE_WINDOWS:-1}" = "1" ]; then
    ensure_opaque_windows
fi

ELECTRON_FLAGS=(--no-sandbox)

if [ -n "${CODEX_OZONE_PLATFORM:-}" ]; then
    ELECTRON_FLAGS+=(--ozone-platform="${CODEX_OZONE_PLATFORM}")
elif [ "${XDG_SESSION_TYPE:-}" = "wayland" ] && [ "${CODEX_USE_X11_ON_WAYLAND:-0}" = "1" ]; then
    ELECTRON_FLAGS+=(--ozone-platform=x11)
fi

if [ "${CODEX_DISABLE_GPU:-0}" = "1" ]; then
    ELECTRON_FLAGS+=(--disable-gpu --disable-gpu-compositing --disable-gpu-vsync)
fi

if [ -n "${CODEX_ELECTRON_FLAGS:-}" ]; then
    # shellcheck disable=SC2206
    EXTRA_FLAGS=($CODEX_ELECTRON_FLAGS)
    ELECTRON_FLAGS+=("${EXTRA_FLAGS[@]}")
fi

exec ./node_modules/.bin/electron "${ELECTRON_FLAGS[@]}" . "$@"
EOF_LAUNCHER

    chmod +x "$PROJECT_DIR/codex-linux.sh"
    success "Launcher created"
}

install_codex_cli_if_missing() {
    if command -v codex >/dev/null 2>&1; then
        success "Codex CLI found at: $(command -v codex)"
        return 0
    fi

    warn "Codex CLI not found. Trying to install globally..."
    if npm install -g @openai/codex; then
        success "Codex CLI installed"
    else
        warn "Global install failed. Run manually: npm install -g @openai/codex"
    fi
}

install_desktop_entry() {
    local desktop_dir="$HOME/.local/share/applications"
    local desktop_file="$desktop_dir/codex-desktop.desktop"
    local icon_path="utilities-terminal"

    mkdir -p "$desktop_dir"

    for candidate in \
        "$SCRIPT_DIR/openai-codex-logo.png" \
        "$SCRIPT_DIR/openai-codex-logo-hd.png" \
        "$SCRIPT_DIR/openai-codex-logo.webp"
    do
        if [ -f "$candidate" ]; then
            icon_path="$candidate"
            break
        fi
    done

    cat > "$desktop_file" <<EOF_DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=Codex Desktop
Comment=Codex Desktop (CachyOS/Arch compatible wrapper)
Exec=$PROJECT_DIR/codex-linux.sh
TryExec=$PROJECT_DIR/codex-linux.sh
Icon=$icon_path
Terminal=false
Categories=Development;
StartupNotify=true
EOF_DESKTOP

    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$desktop_dir" >/dev/null 2>&1 || true
    success "Desktop entry updated: $desktop_file"
}

main() {
    print_header
    check_prereqs

    local dmg_path
    dmg_path="$(resolve_dmg_path "$@")"
    success "Using DMG: $dmg_path"

    local asar_path
    asar_path="$(extract_dmg "$dmg_path")"

    extract_asar "$asar_path"
    setup_project
    install_node_deps
    patch_macos_only_modules
    create_launcher
    install_codex_cli_if_missing
    install_desktop_entry
    cleanup

    echo
    success "Install complete"
    echo "Launch with: $PROJECT_DIR/codex-linux.sh"
    echo "Tip: run 'codex auth' once in terminal if needed"
}

main "$@"
