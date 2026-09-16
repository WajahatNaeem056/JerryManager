# Contributing to JerryManager

Thanks for considering a contribution.

## Before you start

- For bug reports or feature ideas, open an [issue](https://github.com/WajahatNaeem056/JerryManager/issues) first — this avoids duplicate work.
- For anything beyond a small fix, it's worth opening an issue to discuss the approach before writing code.

## Development setup

The module is plain shell scripts and a static Web UI — no build step required. Clone the repo, edit the relevant files under `Jerry/`, and test on-device.

## Before submitting a PR

1. Run the test suite: `bash tests/run.sh`
2. Run ShellCheck against any shell scripts you touched: `shellcheck path/to/your_script.sh`
3. Don't hardcode the module install path (`/data/adb/modules/JerryManager`) — use `$MODDIR` / `lib/paths.sh` instead
4. Don't call `su -c` inside feature scripts — they already run as root
5. If you touched `module.prop`, make sure `version` and `versionCode` stay in sync

## Pull requests

- Keep PRs focused — one feature or fix per PR is easier to review
- Describe what changed and why in the PR description
- CI runs automatically on push/PR and must pass

## Code style

- Shell scripts: POSIX `sh` compatible where practical, matching the style of surrounding code
- JS: match the existing plain-JS style in the Web UI — no framework required for module logic
