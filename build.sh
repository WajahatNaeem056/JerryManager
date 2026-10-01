#!/bin/sh
# Packages the flashable module zip from Jerry/ (repo-only files stay out).
# Run from the repo root:
#   sh build.sh             # package Jerry/webroot as it is
#   sh build.sh --webui     # rebuild the WebUI first (needs node + npm)
set -e
cd "$(dirname "$0")"
if [ "$1" = "--webui" ]; then
  (cd webui-src/project && npm install && npm run build)
fi
command -v node >/dev/null 2>&1 && node tools/check-webroot.mjs
VER=$(grep '^version=' Jerry/module.prop | cut -d= -f2)
mkdir -p dist
OUT="$(pwd)/dist/JerryManager-$VER.zip"
rm -f "$OUT"
cd Jerry
for f in $(find . -name '*.sh'); do sh -n "$f"; done
zip -r9 "$OUT" . -x '*.zip' >/dev/null
if unzip -l "$OUT" | grep -q node_modules; then echo "ERROR: node_modules in zip" >&2; exit 1; fi
echo "built dist/JerryManager-$VER.zip"
