#!/bin/sh
set -eu

APP_LABEL="Codex Linux Wayland Stable"
ELECTRON_VERSION="40.0.0"
DEFAULT_DMG_URL="https://persistent.oaistatic.com/codex-app-prod/Codex.dmg"

CODEX_INSTALL_DIR="${CODEX_INSTALL_DIR:-$HOME/.local/share/codex-linux-wayland-stable}"
TOOLS_DIR="$CODEX_INSTALL_DIR/.tools"
PROJECT_DIR="$CODEX_INSTALL_DIR/codex-linux"
WORK_DIR=""

NODE_BIN=""
NODE_CMD=""
NPM_CMD=""
NPX_CMD=""
SEVEN_ZIP=""

say() {
  printf '%s\n' "$*"
}

log() {
  printf '%s\n' "$*" >&2
}

info() {
  log "[INFO] $*"
}

ok() {
  log "[OK] $*"
}

warn() {
  log "[WARN] $*"
}

die() {
  log "[ERROR] $*"
  exit 1
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

cleanup() {
  if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
}

trap cleanup EXIT INT TERM

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    sh -c "$*"
    return
  fi

  if has_cmd sudo; then
    sudo sh -c "$*"
    return
  fi

  die "Need root privileges to install missing system packages. Install sudo or run as root."
}

detect_pkg_manager() {
  if has_cmd pacman; then
    say pacman
    return
  fi
  if has_cmd apt-get; then
    say apt
    return
  fi
  if has_cmd dnf; then
    say dnf
    return
  fi
  if has_cmd zypper; then
    say zypper
    return
  fi
  say unknown
}

install_system_deps() {
  PM="$(detect_pkg_manager)"

  case "$PM" in
    pacman)
      info "Installing dependencies with pacman"
      as_root "pacman -Sy --noconfirm --needed curl python p7zip base-devel tar xz"
      ;;
    apt)
      info "Installing dependencies with apt"
      as_root "apt-get update"
      as_root "DEBIAN_FRONTEND=noninteractive apt-get install -y curl python3 p7zip-full build-essential tar xz-utils"
      ;;
    dnf)
      info "Installing dependencies with dnf"
      as_root "dnf install -y curl python3 p7zip p7zip-plugins make gcc-c++ tar xz"
      ;;
    zypper)
      info "Installing dependencies with zypper"
      as_root "zypper --non-interactive install curl python3 7zip make gcc-c++ tar xz"
      ;;
    *)
      die "Could not detect package manager. Install manually: curl python3 7z/7zz make g++ tar xz"
      ;;
  esac
}

resolve_7zip() {
  if has_cmd 7z; then
    SEVEN_ZIP="7z"
    return
  fi
  if has_cmd 7zz; then
    SEVEN_ZIP="7zz"
    return
  fi

  install_system_deps

  if has_cmd 7z; then
    SEVEN_ZIP="7z"
    return
  fi
  if has_cmd 7zz; then
    SEVEN_ZIP="7zz"
    return
  fi

  die "7zip not found after dependency install"
}

ensure_build_tools() {
  MISSING=0
  has_cmd python3 || MISSING=1
  has_cmd make || MISSING=1
  has_cmd g++ || MISSING=1
  has_cmd tar || MISSING=1
  has_cmd curl || MISSING=1

  if [ "$MISSING" -eq 1 ]; then
    install_system_deps
  fi

  has_cmd python3 || die "python3 is required"
  has_cmd make || die "make is required"
  has_cmd g++ || die "g++ is required"
  has_cmd tar || die "tar is required"
  has_cmd curl || die "curl is required"
}

arch_to_node() {
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64) say x64 ;;
    aarch64|arm64) say arm64 ;;
    *) die "Unsupported architecture: $ARCH" ;;
  esac
}

use_system_node_if_valid() {
  if ! has_cmd node || ! has_cmd npm || ! has_cmd npx; then
    return 1
  fi

  MAJOR="$(node -v | sed 's/^v//' | cut -d. -f1)"
  case "$MAJOR" in
    ''|*[!0-9]*) return 1 ;;
  esac

  if [ "$MAJOR" -lt 20 ]; then
    return 1
  fi

  NODE_CMD="$(command -v node)"
  NPM_CMD="$(command -v npm)"
  NPX_CMD="$(command -v npx)"
  NODE_BIN="$(dirname "$NODE_CMD")"
  return 0
}

setup_portable_node() {
  NODE_ARCH="$(arch_to_node)"
  mkdir -p "$TOOLS_DIR"

  SHASUMS_URL="https://nodejs.org/dist/latest-v20.x/SHASUMS256.txt"
  info "Resolving latest Node.js v20 for linux-$NODE_ARCH"

  NODE_TARBALL="$(curl -fsSL "$SHASUMS_URL" | grep "linux-$NODE_ARCH.tar.xz" | head -n 1 | awk '{print $2}')"
  [ -n "$NODE_TARBALL" ] || die "Failed to resolve Node.js tarball for linux-$NODE_ARCH"

  NODE_URL="https://nodejs.org/dist/latest-v20.x/$NODE_TARBALL"
  TMP_NODE_ARCHIVE="$WORK_DIR/$NODE_TARBALL"

  info "Downloading portable Node.js ($NODE_TARBALL)"
  curl -fsSL "$NODE_URL" -o "$TMP_NODE_ARCHIVE"

  rm -rf "$TOOLS_DIR/node"
  tar -xJf "$TMP_NODE_ARCHIVE" -C "$TOOLS_DIR"

  EXTRACTED_DIR="$TOOLS_DIR/$(echo "$NODE_TARBALL" | sed 's/\.tar\.xz$//')"
  [ -d "$EXTRACTED_DIR" ] || die "Portable Node extraction failed"

  mv "$EXTRACTED_DIR" "$TOOLS_DIR/node"

  NODE_BIN="$TOOLS_DIR/node/bin"
  NODE_CMD="$NODE_BIN/node"
  NPM_CMD="$NODE_BIN/npm"
  NPX_CMD="$NODE_BIN/npx"

  PATH="$NODE_BIN:$PATH"
  export PATH

  ok "Using portable Node.js at $NODE_CMD"
}

setup_node() {
  if use_system_node_if_valid; then
    ok "Using system Node.js: $($NODE_CMD -v)"
    return
  fi

  warn "System Node.js is missing or too old. Bootstrapping portable Node.js v20..."
  setup_portable_node
}

resolve_dmg() {
  if [ -n "${CODEX_DMG_PATH:-}" ] && [ -f "${CODEX_DMG_PATH}" ]; then
    say "${CODEX_DMG_PATH}"
    return
  fi

  DMG_PATH="$WORK_DIR/Codex.dmg"
  DMG_URL="${CODEX_DMG_URL:-$DEFAULT_DMG_URL}"

  info "Downloading Codex.dmg"
  curl -L --progress-bar --connect-timeout 30 --max-time 1200 -o "$DMG_PATH" "$DMG_URL"

  [ -s "$DMG_PATH" ] || die "Downloaded DMG is empty"
  say "$DMG_PATH"
}

extract_app_asar() {
  DMG_PATH="$1"
  EXTRACT_DIR="$WORK_DIR/codex_extracted"

  info "Extracting DMG"
  rm -rf "$EXTRACT_DIR"
  mkdir -p "$EXTRACT_DIR"

  "$SEVEN_ZIP" x "$DMG_PATH" -o"$EXTRACT_DIR" -y >/tmp/codex-7z.log 2>&1 || true

  ASAR_PATH="$(find "$EXTRACT_DIR" -type f -name app.asar 2>/dev/null | head -n 1 || true)"
  [ -n "$ASAR_PATH" ] || die "Could not find app.asar in DMG"

  say "$ASAR_PATH"
}

extract_source() {
  ASAR_PATH="$1"
  APP_SRC_DIR="$WORK_DIR/codex_app_src"

  info "Extracting app.asar"
  rm -rf "$APP_SRC_DIR"
  "$NPX_CMD" --yes @electron/asar extract "$ASAR_PATH" "$APP_SRC_DIR"

  [ -d "$APP_SRC_DIR/.vite" ] || die "Invalid app.asar extract (.vite missing)"
  say "$APP_SRC_DIR"
}

detect_module_version() {
  APP_SRC_DIR="$1"
  MODULE_NAME="$2"
  FALLBACK="$3"

  "$NODE_CMD" - "$APP_SRC_DIR" "$MODULE_NAME" "$FALLBACK" <<'NODE'
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

prepare_project() {
  APP_SRC_DIR="$1"

  rm -rf "$PROJECT_DIR"
  mkdir -p "$PROJECT_DIR"

  cp -R "$APP_SRC_DIR/.vite" "$PROJECT_DIR/.vite"

  if [ -d "$APP_SRC_DIR/webview" ]; then
    cp -R "$APP_SRC_DIR/webview" "$PROJECT_DIR/webview"
  else
    WEBVIEW_PATH="$(find "$APP_SRC_DIR" -type d -name webview 2>/dev/null | head -n 1 || true)"
    [ -n "$WEBVIEW_PATH" ] || die "webview folder not found"
    cp -R "$WEBVIEW_PATH" "$PROJECT_DIR/webview"
  fi

  if [ -d "$APP_SRC_DIR/native" ]; then
    cp -R "$APP_SRC_DIR/native" "$PROJECT_DIR/native"
  else
    mkdir -p "$PROJECT_DIR/native"
  fi

  BS3_VERSION="$(detect_module_version "$APP_SRC_DIR" better-sqlite3 12.4.6)"
  NPTY_VERSION="$(detect_module_version "$APP_SRC_DIR" node-pty 1.1.0)"

  info "Native versions: better-sqlite3@$BS3_VERSION node-pty@$NPTY_VERSION"

  cat > "$PROJECT_DIR/package.json" <<EOF_JSON
{
  "name": "codex-linux",
  "productName": "Codex",
  "version": "1.0.0-linux",
  "main": ".vite/build/main.js",
  "scripts": {
    "start": "electron ."
  },
  "dependencies": {
    "better-sqlite3": "$BS3_VERSION",
    "node-pty": "$NPTY_VERSION",
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
    "electron": "$ELECTRON_VERSION",
    "@electron/rebuild": "^3.6.0"
  }
}
EOF_JSON
}

install_node_modules() {
  info "Installing npm dependencies"
  (
    cd "$PROJECT_DIR"
    "$NPM_CMD" install --no-audit --no-fund
  )

  info "Rebuilding native modules for Electron $ELECTRON_VERSION"
  (
    cd "$PROJECT_DIR"
    "$NPX_CMD" --yes @electron/rebuild -v "$ELECTRON_VERSION" --force
  )
}

patch_macos_modules() {
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
}

install_codex_cli() {
  LOCAL_CLI_PREFIX="$TOOLS_DIR/codex-cli"
  LOCAL_CLI_BIN="$LOCAL_CLI_PREFIX/bin/codex"

  if has_cmd codex; then
    say "$(command -v codex)"
    return
  fi

  if [ -x "$LOCAL_CLI_BIN" ]; then
    say "$LOCAL_CLI_BIN"
    return
  fi

  info "Installing local Codex CLI"
  mkdir -p "$LOCAL_CLI_PREFIX"
  "$NPM_CMD" install --prefix "$LOCAL_CLI_PREFIX" @openai/codex --no-audit --no-fund

  [ -x "$LOCAL_CLI_BIN" ] || die "Failed to install local Codex CLI"
  say "$LOCAL_CLI_BIN"
}

write_launcher() {
  LOCAL_CLI_BIN="$1"

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

    candidate="__LOCAL_CLI_BIN__"
    if [ -x "$candidate" ]; then
        echo "$candidate"
        return 0
    fi

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

  esc_path="$(printf '%s' "$LOCAL_CLI_BIN" | sed 's/[&/]/\\&/g')"
  sed -i "s/__LOCAL_CLI_BIN__/$esc_path/g" "$PROJECT_DIR/codex-linux.sh"
  chmod +x "$PROJECT_DIR/codex-linux.sh"
}

install_desktop_entry() {
  DESKTOP_DIR="$HOME/.local/share/applications"
  DESKTOP_FILE="$DESKTOP_DIR/codex-desktop.desktop"

  mkdir -p "$DESKTOP_DIR"

  ICON_VALUE="utilities-terminal"
  if [ -f "$HOME/Downloads/openai-codex-logo-hd.png" ]; then
    ICON_VALUE="$HOME/Downloads/openai-codex-logo-hd.png"
  elif [ -f "$HOME/Downloads/openai-codex-logo.png" ]; then
    ICON_VALUE="$HOME/Downloads/openai-codex-logo.png"
  fi

  cat > "$DESKTOP_FILE" <<EOF_DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=Codex Desktop
Comment=Codex Desktop (Linux Wayland Stable wrapper)
Exec=$PROJECT_DIR/codex-linux.sh
TryExec=$PROJECT_DIR/codex-linux.sh
Icon=$ICON_VALUE
Terminal=false
Categories=Development;
StartupNotify=true
EOF_DESKTOP

  if has_cmd update-desktop-database; then
    update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
  fi

  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/codex-desktop" <<EOF_BIN
#!/bin/sh
exec "$PROJECT_DIR/codex-linux.sh" "\$@"
EOF_BIN
  chmod +x "$HOME/.local/bin/codex-desktop"
}

main() {
  say "$APP_LABEL"
  say "Created/tested on CachyOS (Arch Linux), intended for most modern Linux distros."

  ensure_build_tools
  resolve_7zip

  mkdir -p "$CODEX_INSTALL_DIR"
  WORK_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t codex-installer)"

  setup_node

  DMG_PATH="$(resolve_dmg)"
  ok "Using DMG: $DMG_PATH"

  ASAR_PATH="$(extract_app_asar "$DMG_PATH")"
  APP_SRC_DIR="$(extract_source "$ASAR_PATH")"

  info "Preparing project in $PROJECT_DIR"
  prepare_project "$APP_SRC_DIR"
  install_node_modules
  patch_macos_modules

  CLI_PATH="$(install_codex_cli)"
  write_launcher "$CLI_PATH"
  install_desktop_entry

  ok "Install complete"
  say "Run: $PROJECT_DIR/codex-linux.sh"
  say "Or use: codex-desktop"
  say "If needed, run once in terminal: codex auth"
}

main "$@"
