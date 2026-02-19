# Codex Linux Installer (CachyOS/Arch Friendly)

Unofficial installer that ports OpenAI's macOS `Codex.dmg` to Linux.

Created and tested on **CachyOS (Arch Linux)**. It should also work on other modern distros.

## Quick Start

1. Install dependencies.

```bash
# CachyOS / Arch
sudo pacman -S nodejs npm python curl p7zip base-devel
```

2. Put `Codex.dmg` next to `install-codex-linux.sh`.

3. Run the installer.

```bash
chmod +x install-codex-linux.sh
./install-codex-linux.sh
```

4. Launch Codex.

```bash
cd codex-linux
./codex-linux.sh
```

## Notes

- If `Codex.dmg` is missing, the script will try to download it automatically.
- The launcher forces `opaqueWindows=true` to reduce transparency artifacts.
- The installer writes/updates `~/.local/share/applications/codex-desktop.desktop`.
- If CLI is missing, install it with:

```bash
npm install -g @openai/codex
```

## Optional Rendering Flags

```bash
CODEX_USE_X11_ON_WAYLAND=1 ./codex-linux.sh
CODEX_DISABLE_GPU=1 ./codex-linux.sh
CODEX_OZONE_PLATFORM=wayland ./codex-linux.sh
```
