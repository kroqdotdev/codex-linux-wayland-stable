# Codex Linux Wayland Stable

Unofficial installer that ports OpenAI's macOS `Codex.dmg` to Linux, with launch defaults tuned for better Wayland stability.

Created and tested on **CachyOS (Arch Linux)**.

## High-Confidence Distro Support

High confidence this works on:

- CachyOS, Arch Linux, EndeavourOS, Manjaro, Garuda
- Fedora and Nobara
- Ubuntu 22.04+, Debian 12+, Linux Mint 21+, Pop!_OS 22.04+
- openSUSE Tumbleweed and recent Leap

Why confidence is high: the installer only relies on common system tooling (`node`, `npm`, `python3`, `curl`, `7z`, `make`, `g++`) and rebuilds native modules locally for your machine.

## Install Dependencies

```bash
# Arch / CachyOS / EndeavourOS / Manjaro / Garuda
sudo pacman -S nodejs npm python curl p7zip base-devel

# Fedora / Nobara
sudo dnf install nodejs npm python3 curl p7zip
sudo dnf groupinstall "Development Tools"

# Ubuntu / Debian / Mint / Pop!_OS
sudo apt update
sudo apt install nodejs npm python3 curl p7zip-full build-essential

# openSUSE
sudo zypper install nodejs npm python3 curl 7zip make gcc-c++
```

## Quick Start

1. Put `Codex.dmg` next to `install-codex-linux.sh` (or let the script download it).
2. Run:

```bash
chmod +x install-codex-linux.sh
./install-codex-linux.sh
```

3. Launch:

```bash
cd codex-linux
./codex-linux.sh
```

## Notes

- Forces `opaqueWindows=true` to reduce transparency artifacts.
- Creates/updates `~/.local/share/applications/codex-desktop.desktop`.
- If CLI is missing:

```bash
npm install -g @openai/codex
```

## Optional Rendering Flags

```bash
CODEX_USE_X11_ON_WAYLAND=1 ./codex-linux.sh
CODEX_DISABLE_GPU=1 ./codex-linux.sh
CODEX_OZONE_PLATFORM=wayland ./codex-linux.sh
```
