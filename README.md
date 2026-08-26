<div align="center">

# JerryManager

**A KernelSU / APatch module for achieving and maintaining Strong Device Integrity on Android.**

![Platform](https://img.shields.io/badge/Platform-KernelSU%20%7C%20APatch-blue)
![Version](https://img.shields.io/badge/Version-v4.0-purple)
![OS](https://img.shields.io/badge/Android-8%2B-3DDC84?logo=android&logoColor=white)
![License](https://img.shields.io/badge/License-GPL--3.0-orange)
![Status](https://img.shields.io/badge/Status-Active-success)

</div>
---
##About

A KernelSU / APatch module for maintaining Strong Device Integrity on Android.

JerryManager is built around a simple goal: keeping the integrity setup stable without making the module unnecessarily complicated.

It handles the required system-side changes, detects the device environment, and keeps its configuration persistent between updates and reboots.

Features

- Play Integrity — Support for Basic, Device, and Strong Integrity.
- Keybox Management — Handles the keybox used by the integrity setup.
- ROM Detection — Detects the installed ROM using device filesystem information instead of relying only on build properties.
- Widevine Support — Includes support for DRM-related configurations.
- Mock Account Handling — Handles mock-account detection where required.
- Persistent Configuration — Settings remain preserved across reboots and module updates.

Requirements

- KernelSU or APatch
- Android 8.0+
- ARM64 device

Compatibility

JerryManager is primarily intended for KernelSU and APatch environments.

Results may vary between devices and ROMs depending on their implementation and security configuration.

Project Structure

The project is kept relatively simple so that the module can be maintained and updated without unnecessary dependencies.

Source files and scripts are reviewed and cleaned up as the project evolves. Changes that affect the module's behaviour are documented in the changelog.

Releases

Stable builds are published through GitHub Releases.

Each release has its own version code and changelog so changes between versions can be tracked easily.

See "Releases" (../../releases) for available versions.

Changelog

See "CHANGELOG.md" (CHANGELOG.md) for the complete release history.

Credits

JerryManager builds on the work and ideas from the Android root and integrity community.

Thanks to everyone who has tested the module, reported issues, and contributed feedback.

Developer

WajahatNaeem056

- GitHub: "@WajahatNaeem056" (https://github.com/WajahatNaeem056)
- Telegram: "@JerryChat" (https://t.me/JerryChat)
- Telegram: "@JerryTweaks" (https://t.me/JerryTweaks)

License

JerryManager is licensed under GNU General Public License v3.0.

See "LICENSE" (LICENSE) for the full license text.

---

<p align="center">
  <sub>Built for the community, maintained with care.</sub>
</p>
