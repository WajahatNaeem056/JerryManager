# JerryManager

**A KernelSU / APatch module for achieving and maintaining Strong Device Integrity on Android.**

![Platform](https://img.shields.io/badge/Platform-KernelSU%20%7C%20APatch-blue)
![Version](https://img.shields.io/badge/Version-v4.4-purple)
![OS](https://img.shields.io/badge/Android-8%2B-3DDC84?logo=android&logoColor=white)
![License](https://img.shields.io/badge/License-GPL--3.0-orange)
![Status](https://img.shields.io/badge/Status-Active-success)

---

## About

**JerryManager** is a root module for KernelSU and APatch focused on one job: getting devices to pass **Basic**, **Device**, and **Strong** Play Integrity checks, and keeping them passing across reboots and updates. It ships with a full Web UI for configuration instead of raw config files.

Built for people who need integrity to actually hold — banking apps, payment systems, and other attestation-sensitive apps that break the moment a device is flagged.

## Features

- **Play Integrity Fix** — full pipeline covering keybox injection, security patch spoofing, and prop hardening to pass Strong Integrity
- **Keybox Management** — supply your own keybox or pull one automatically
- **ROM Detection** — identifies the running ROM using verified filesystem markers rather than guessing from spoofable build props; unknown ROMs are reported as `Unknown` instead of a wrong guess
- **Banking Mode** — deep-clean and cache-clean routines aimed at passing banking-app checks, with dedicated fixes for common Pakistani banking apps
- **Widevine Support** — DRM level patching for streaming apps
- **Hide Mock Accounts (HMA)** — including variant handling for stricter detection methods
- **Web UI** — Material Design 3 interface for every toggle; no manual file editing required
- **Persistent Config** — toggle states survive module updates and reboots

## Installation

1. Download the latest ZIP from [Releases](https://github.com/WajahatNaeem056/JerryManager/releases)
2. Flash via KernelSU or APatch (Magisk is not the primary target — verify support before flashing)
3. Reboot
4. Open the module's Web UI from your manager app to configure

## Requirements

- KernelSU or APatch
- Android 8.0+

---

## Source & building it yourself

This repo holds the editable source, built into the flashable module with GitHub Actions — not a hand-edited compiled bundle.

### Layout
- `src/` — module source: shell scripts (`lib/`, `features/`), webroot frontend (`webroot/`), and the Vite entry point (`webroot/material-entry.js`)
- `src/webroot-public/` — static custom JS/CSS shipped as-is (not bundled): `app-core.js`, `app-targeting.js`, `rom-status.js`, etc. These already were readable source, just never organized into a proper repo.
- `Module/` — build output (generated, gitignored, do not edit by hand)

### Build
```
npm install
npm run build
```
Produces `Module/` (ready-to-flash folder) and a `JerryManager-<version>.zip` in the repo root.

### CI
- `.github/workflows/build-test.yml` — builds on every push/PR, uploads the result as a workflow artifact
- `.github/workflows/build-release.yml` — on pushing a `v*` tag, builds and attaches the zip to a GitHub Release

### Note on `index-*.js` (@material/web bundle)
The old compiled module only shipped a minified `index-ChjuGUlr.js` — the readable source for it never existed in this repo (it was always built elsewhere and only the output got shipped). Rather than reverse-engineer minified third-party library code, `material-entry.js` re-imports `@material/web` fresh from npm and Vite rebuilds the equivalent bundle from source on every build.

---

## Developer

**WajahatNaeem056**

- GitHub: [@WajahatNaeem056](https://github.com/WajahatNaeem056)
- Telegram: [@JerryChatt](https://t.me/JerryChatt)
- Telegram: [@JerryTweaks](https://t.me/JerryTweaks)

## License

GPL-3.0 — see [LICENSE](https://github.com/WajahatNaeem056/JerryManager/blob/main/LICENSE) for full terms.

---

*Built for the community, by the community.*
