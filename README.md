JerryManager

KernelSU / APatch module for achieving and maintaining Strong Device Integrity on Android.

JerryManager brings together the components needed to maintain Play Integrity across different devices and ROMs, with a focus on keeping the module lightweight, predictable, and easy to maintain.

What it does

- Play Integrity — Handles the required changes for Basic, Device, and Strong Integrity.
- Keybox Management — Supports using a configured keybox and managing the keybox used by the module.
- ROM Detection — Detects the installed ROM using filesystem information instead of relying only on build properties.
- Widevine Support — Includes the required DRM-level changes for supported configurations.
- Mock Account Handling — Provides options for hiding mock accounts where required.
- Persistent Configuration — Keeps module settings across reboots and module updates.

Compatibility

JerryManager is designed for:

- KernelSU
- APatch
- Android 8.0+

Compatibility can vary depending on the device, ROM, Android version, and root environment.

Releases

JerryManager follows a versioned release cycle. Each release contains the corresponding module build and a changelog describing the changes made since the previous version.

For detailed release changes, see "CHANGELOG.md" (CHANGELOG.md).

Project

The project is maintained with a focus on keeping the source simple and maintainable. Changes are tested before being included in a release, and older code is cleaned up when it is no longer needed.

Issues and useful feedback are welcome, especially when accompanied by relevant device, ROM, Android, and KernelSU/APatch information.

Developer

WajahatNaeem056

- GitHub: "@WajahatNaeem056" (https://github.com/WajahatNaeem056)
- Telegram: "@JerryChat" (https://t.me/JerryChat)
- Telegram: "@JerryTweaks" (https://t.me/JerryTweaks)

License

JerryManager is licensed under GPL-3.0.

See "LICENSE" (LICENSE) for the full license text.

---

<p align="center">
  <i>Built for the community, by the community.</i>
</p>
