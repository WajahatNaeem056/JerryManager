<div align="center">

# JerryManager

**A KernelSU / APatch module for achieving and maintaining Root Hiding and Integrity on Android.**

![Platform](https://img.shields.io/badge/Platform-KernelSU%20%7C%20APatch-blue)
![Version](https://img.shields.io/badge/Version-v4.7-purple)
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
- **Built-in PIF** — powered by JerryManager itself, no separate standalone PIF module needed. Source: [Jerry-pif](https://github.com/WajahatNaeem056/Jerry-pif)
- **Keybox Management** — supply your own keybox or pull one automatically
- **Auto Target**: inotify + polling for new apps
- **Banking Mode**: dedicated handling for banking and payment apps
- **ADB Disabler**: dev options, USB debugging, OEM unlock
- **Detection Cleanup**: removes detector logs, temp dirs, caches
- **Widevine L1**: attestation keys via KmInstallKeybox
- **ROM Detection** — identifies the running ROM using verified filesystem markers rather than guessing from spoofable build props; ROMs it cannot identify are shown as `AOSP (Unrecognized)` or `Stock (<brand>)` instead of a wrong guess
- **Multi-language Web UI** — translations live in `webui-src/project/public/lang/` (`en.json` is the key list)


## Installation

1. Download the latest ZIP from [Releases](https://github.com/WajahatNaeem056/JerryManager/releases)
2. Flash via KernelSU or APatch (Magisk is not the primary target — verify support before flashing)
3. Reboot
4. Open the module's Web UI from your manager app to configure

## Structure

- `Jerry/`: module (features, lib, pipelines); `dex/classes.dex` and `zygisk/*.so` are the built-in PIF binaries, built from [Jerry-pif](https://github.com/WajahatNaeem056/Jerry-pif)
- `webui-src/project/`: WebUI source (Vite) and static webroot files (`public/`); `webroot/` in the zip is generated from it
- `package.json`, `vite.config.js`: WebUI build; `npm run build` builds the WebUI and the flashable ZIP
- `tools/`: icon-font inline, webroot check and zip packaging scripts
- `Main.java`: source of `Jerry/dex/attest.dex` (boot hash probe), built by `.github/workflows/build-dex.yml`
- `build.sh`: runs `npm install && npm run build`

## Build

Requires `git`, `zip`, `unzip`, Node.js 20.19+ and npm.

```bash
git clone https://github.com/WajahatNaeem056/JerryManager.git
cd JerryManager
sh build.sh
```

`sh build.sh` installs the dependencies and builds the module ZIP in one step. To do it step by step, run these from the repo root (`package.json` lives there, not in `webui-src/project`):

```bash
npm install
npm run build
```

`npm run build` builds the WebUI with Vite, moves the base64 icon font into index.html, checks the webroot and packages the ZIP. The WebUI is built into `dist/webroot` (`index.html` with the base64 icon font inline, plus one JS file and one CSS file in `assets/`) and packaged into the ZIP as `webroot/`.

Output: `dist/JerryManager-<version>.zip`, where `<version>` comes from `Jerry/module.prop` (e.g. `dist/JerryManager-v4.7.zip`).

## Developer

**WajahatNaeem056**

- GitHub: [@WajahatNaeem056](https://github.com/WajahatNaeem056)
- Telegram: [@JerryChatt](https://t.me/JerryChatt)
- Telegram: [@JerryTweaks](https://t.me/JerryTweaks)

## License

GPL-3.0 — see [LICENSE](https://github.com/WajahatNaeem056/JerryManager/blob/main/LICENSE) for full terms.

---

*Built for the community, by the community.*
