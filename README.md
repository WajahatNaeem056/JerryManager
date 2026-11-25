<div align="center">

# JerryManager

**Root Hiding and Play Integrity module for Magisk, KernelSU and APatch.**

</div>

---

## About

JerryManager keeps root hidden and Play Integrity passing on Android. PIF and Tricky Store OSS are built in, so no separate modules are needed. A Web UI handles all configuration, with no config files to edit by hand.

## Features

**Integrity Related**
- **Built-in PIF** — no standalone PIF module needed. Source: [Jerry-pif](https://github.com/WajahatNaeem056/Jerry-pif)
- **Built-in Tricky Store OSS** — bundled keystore engine (works with Tricky Store only). Source: [Jerry TrickyStore-Oos](https://github.com/WajahatNaeem056/Jerry-Ts-Oos)
- **Keybox Management** — own keybox, auto pull, offline import or RKP catalog
- **Widevine L1** — attestation keys via KmInstallKeybox

**Hiding**
- **Boot Props & Hardening** — locked stock verified boot, vbmeta, SELinux and debug props
- **ADB Disabler** — hides dev options, USB debugging, OEM unlock
- **Custom ROM Cleanup** — removes custom ROM and GApps traces from props
- **ROM Spoof Engine Block** — disables PixelProps, PIHooks and similar
- **Multi-Root Hide** — hides folders of other root solutions
- **Recovery Folder Hide** — hides TWRP, OrangeFox and others

**Other**
- **Auto Target** — inotify + polling for new apps
- **ROM Detection** — identifies the ROM using verified filesystem markers rather than guessing from spoofable build props; ROMs it cannot identify are shown as `AOSP (Unrecognized)` or `Stock (<brand>)` instead of a wrong guess
- **Web UI** — English, Arabic, Turkish and Chinese; translations live in `webui-src/project/public/lang/` (`en.json` is the key list)

## Installation

1. Download the latest ZIP from [Releases](https://github.com/WajahatNaeem056/JerryManager/releases)
2. Reboot
3. Open the module's Web UI from your manager app (Magisk, KernelSU or APatch) to configure

## Structure

- `Jerry/`: module (features, lib, pipelines); `dex/classes.dex` and `zygisk/*.so` are the built-in PIF binaries, built from [Jerry-pif](https://github.com/WajahatNaeem056/Jerry-pif)
- `Jerry/ts/`, `Jerry/sepolicy.rule`: built-in Tricky Store OSS binaries, built from [Jerry TrickyStore-Oos](https://github.com/WajahatNaeem056/Jerry-Ts-Oos)
- `webui-src/project/`: WebUI source (Vite) and static webroot files (`public/`); `webroot/` in the zip is generated from it
- `tools/`: icon-font inline, webroot check and zip packaging scripts
- `licenses/duck-toolbox/`: original MIT `LICENSE` and `THIRD_PARTY_NOTICES.md` for the code above
- `Main.java`: source of `Jerry/dex/attest.dex` (boot hash probe), built by `.github/workflows/build-dex.yml`
- `package.json`, `vite.config.js`: WebUI build
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

Output: `dist/JerryManager-<version>.zip`

## Thanks

- [beakthoven](https://github.com/beakthoven) for TrickyStore OSS, which is integrated into JerryManager.
- [KOWX712](https://github.com/KOWX712) for PIF Inject, used for PIF injection.
- [dpejoh](https://github.com/dpejoh) for the UI inspiration and helpful work.
- [Eltavine](https://github.com/eltavine) for RKP Device / RKP Extractor, originally developed in Duck-ToolBox and used here with permission under the MIT license.

## Developer

**WajahatNaeem056**

- GitHub: [@WajahatNaeem056](https://github.com/WajahatNaeem056)
- Telegram: [@JerryChatt](https://t.me/JerryChatt)
- Telegram: [@JerryTweaks](https://t.me/JerryTweaks)

## License

GPL-3.0 — see [LICENSE](https://github.com/WajahatNaeem056/JerryManager/blob/main/LICENSE) for full terms.

--
*Built for the community, by the community.
