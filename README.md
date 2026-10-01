<div align="center">

# JerryManager

**A KernelSU / APatch module for achieving and maintaining Root Hiding and Integrity on Android.**

![Platform](https://img.shields.io/badge/Platform-KernelSU%20%7C%20APatch%20%7C%20Magisk-blue)
![Version](https://img.shields.io/badge/Version-v4.4-purple)
![OS](https://img.shields.io/badge/Android-8%2B-3DDC84?logo=android&logoColor=white)
![License](https://img.shields.io/badge/License-GPL--3.0-orange)
![Status](https://img.shields.io/badge/Status-Active-success)

</div>

---

## About

**JerryManager** is a root management module for KernelSU and APatch, primarily focused on **Root Hiding and Play Integrity**. It provides a centralized set of tools to help hide root-related traces, manage target applications, handle integrity configuration, and maintain selected settings across reboots and module updates.

It includes an integrated **Web UI** that makes Root Hiding and integrity-related configuration simple to manage without manually editing configuration files.

Built for users who need a practical, centralized solution for **Root Hiding, Play Integrity, banking apps, payment apps, DRM services, and other security-sensitive applications**.

## Features

- **Play Integrity And Root Hiding** — full pipeline covering keybox injection, security patch spoofing, and prop hardening to pass Strong Integrity
- **Keybox Management** — supply your own keybox or pull one automatically
- **Auto Target**: inotify + polling for new apps
- **Banking Mode**: dedicated handling for banking and payment apps
- **ADB Disabler**: dev options, USB debugging, OEM unlock
- **Detection Cleanup**: removes detector logs, temp dirs, caches
- **Widevine L1**: attestation keys via KmInstallKeybox
- **ROM Detection** — identifies the running ROM using verified filesystem markers rather than guessing from spoofable build props; unknown ROMs are reported as `Unknown` instead of a wrong guess
- **Multi-language Web UI** — translations live in `webroot/lang/` (`source/string.json` is the key list)

## Installation

1. Download the latest ZIP from [Releases](https://github.com/WajahatNaeem056/JerryManager/releases)
2. Flash via KernelSU or APatch (Magisk is not the primary target — verify support before flashing)
3. Reboot
4. Open the module's Web UI from your manager app to configure

## Requirements

- KernelSU or APatch
- Android 8.0+

---

## Source & Building It Yourself

The repository contains the JerryManager module source and the complete editable WebUI source.

### Repository Structure

- `Jerry/` — the module itself (this is what gets zipped and flashed)
- `Jerry/features/` — module feature scripts
- `Jerry/lib/` — shared shell libraries
- `Jerry/pipelines/` — integrity pipelines
- `Jerry/webroot/` — generated WebUI shipped with the module
- `webui-src/project/` — editable WebUI source (Vite)
- `tools/` — webroot clean/check scripts used by the build
- `build.sh` — module build script

### Requirements

- `git`, `zip`, `unzip`
- `node` + `npm` — only needed if you change the WebUI

Termux: `pkg install git zip unzip nodejs -y`

### Build From Source

Clone the repository:

```bash
git clone https://github.com/WajahatNaeem056/JerryManager.git
cd JerryManager
```

Build the module ZIP (uses the WebUI already in `Jerry/webroot/`):

```bash
sh build.sh
```

If you edited the WebUI source, rebuild it first with one command:

```bash
sh build.sh --webui
```

The completed ZIP is generated in:

```text
dist/JerryManager-<version>.zip
```

The version number is read from `Jerry/module.prop`. The WebUI source is in `webui-src/project/`, and the generated production WebUI is written to `Jerry/webroot/`.

## Developer

**WajahatNaeem056**

- GitHub: [@WajahatNaeem056](https://github.com/WajahatNaeem056)
- Telegram: [@JerryChatt](https://t.me/JerryChatt)
- Telegram: [@JerryTweaks](https://t.me/JerryTweaks)

## License

GPL-3.0 — see [LICENSE](https://github.com/WajahatNaeem056/JerryManager/blob/main/LICENSE) for full terms.

---

*Built for the community, by the community.*
