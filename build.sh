#!/bin/sh
# Packages the flashable module zip (excludes repo-only files).
# Run from the repo root:
#   sh build.sh             # package webroot/ as it is
#   sh build.sh --webui     # rebuild the WebUI first (needs node + npm)
set -e
cd "$(dirname "$0")"
if [ "$1" = "--webui" ]; then
  (cd webui-src/project && npm install && npm run build)
fi
command -v node >/dev/null 2>&1 && node tools/check-webroot.mjs
VER=$(grep '^version=' module.prop | cut -d= -f2)
mkdir -p dist
OUT="dist/JerryManager-$VER.zip"
rm -f "$OUT"
for f in $(find . -name '*.sh' -not -path './dist/*' -not -path './tools/*' -not -path '*/node_modules/*'); do sh -n "$f"; done
zip -r9 "$OUT" . \
  -x 'dist/*' '.git/*' '.gitignore' 'webui-src/*' 'tools/*' 'node_modules/*' '*/node_modules/*' \
     'README.md' 'CHANGELOG.md' 'update.json' 'Copyright Notice' 'build.sh' '*.zip' >/dev/null
if unzip -l "$OUT" | grep -q node_modules; then echo "ERROR: node_modules in zip" >&2; exit 1; fi
echo "built $OUT"
