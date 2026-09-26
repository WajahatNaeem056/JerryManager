# JerryManager — source

This is the editable source for the JerryManager Magisk/KernelSU module,
built with GitHub Actions instead of hand-editing a compiled bundle.

## Layout
- `src/` — module source: shell scripts (`lib/`, `features/`), webroot
  frontend (`webroot/`), and the Vite entry point (`webroot/material-entry.js`)
- `src/webroot-public/` — static custom JS/CSS shipped as-is (not bundled):
  `app-core.js`, `app-targeting.js`, `rom-status.js`, etc. These already were
  readable source, just never organized into a proper repo.
- `Module/` — build output (generated, gitignored, do not edit by hand)

## Build
```
npm install
npm run build
```
Produces `Module/` (ready-to-flash folder) and a `JerryManager-<version>.zip`
in the repo root.

## CI
- `.github/workflows/build-test.yml` — builds on every push/PR, uploads the
  result as a workflow artifact
- `.github/workflows/build-release.yml` — on pushing a `v*` tag, builds and
  attaches the zip to a GitHub Release

## Note on `index-*.js` (@material/web bundle)
The old compiled module only shipped a minified `index-ChjuGUlr.js` — the
readable source for it never existed in this repo (it was always built
elsewhere and only the output got shipped). Rather than reverse-engineer
minified third-party library code, `material-entry.js` re-imports
`@material/web` fresh from npm and Vite rebuilds the equivalent bundle
from source on every build.
