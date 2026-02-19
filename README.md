# Codex Linux Wayland Stable

Unofficial Codex Linux installer tuned for better Wayland behavior.

Created and tested on **CachyOS (Arch Linux)**.

## One-Paste Install

```bash
curl -fsSL https://kroq.dev/tools/codex-for-linux.sh | sh
```

This script handles dependency install (when possible), downloads `Codex.dmg`, builds the Linux wrapper, installs CLI if needed, and creates a desktop launcher.

## High-Confidence Distro Support

High confidence this works on:

- Arch family: CachyOS, Arch Linux, EndeavourOS, Manjaro, Garuda
- Fedora family: Fedora, Nobara
- Debian/Ubuntu family: Ubuntu 22.04+, Debian 12+, Linux Mint 21+, Pop!_OS 22.04+
- openSUSE: Tumbleweed and recent Leap

Why confidence is high: the installer uses standard Linux tooling (`curl`, `python3`, `7z`, `make`, `g++`, `tar`, `xz`), rebuilds native modules locally, and bootstraps portable Node.js v20 if system Node is missing or too old.

## Installed Paths

- App: `~/.local/share/codex-linux-wayland-stable/codex-linux`
- Launcher: `~/.local/share/codex-linux-wayland-stable/codex-linux/codex-linux.sh`
- Desktop entry: `~/.local/share/applications/codex-desktop.desktop`
- Helper command: `~/.local/bin/codex-desktop`

## Optional Rendering Flags

```bash
CODEX_USE_X11_ON_WAYLAND=1 codex-desktop
CODEX_DISABLE_GPU=1 codex-desktop
CODEX_OZONE_PLATFORM=wayland codex-desktop
```
