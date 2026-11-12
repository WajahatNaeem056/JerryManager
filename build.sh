#!/bin/sh
# Same as `npm install && npm run build`: builds the WebUI and packages dist/JerryManager-<version>.zip.
# Run from the repo root (needs node, npm, zip):
#   sh build.sh
set -e
cd "$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
command -v node >/dev/null 2>&1 || { echo "ERROR: node is required to build the WebUI" >&2; exit 1; }
npm install
npm run build
