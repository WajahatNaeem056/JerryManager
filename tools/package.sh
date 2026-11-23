#!/bin/sh
# Packages the flashable module zip from Jerry/ + the built dist/webroot.
# Runs as the last step of `npm run build`.
set -e
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

[ -f dist/webroot/index.html ] || { echo "ERROR: dist/webroot missing, run npm run build" >&2; exit 1; }
VER=$(grep '^version=' Jerry/module.prop | cut -d= -f2)
mkdir -p dist
OUT="$ROOT/dist/JerryManager-$VER.zip"
rm -f "$OUT"

# Validate shell syntax (module scripts + the scripts shipped in webroot/common).
find Jerry webui-src/project/public -type f -name '*.sh' -exec sh -n {} \;

# Build from a staging copy so packaging permissions are deterministic and
# the developer's working-tree permissions are not changed by the build.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' 0 HUP INT TERM
cp -R Jerry/. "$STAGE/"
rm -rf "$STAGE/webroot"
cp -R dist/webroot "$STAGE/webroot"

# Directories and ordinary files get predictable permissions.
find "$STAGE" -type d -exec chmod 755 {} \;
find "$STAGE" -type f -exec chmod 644 {} \;

# Runtime shell scripts are executable. update-binary is kept executable for
# legacy recovery compatibility; KernelSU does not need to invoke it.
find "$STAGE" -type f -name '*.sh' -exec chmod 755 {} \;
if [ -f "$STAGE/META-INF/com/google/android/update-binary" ]; then
  chmod 755 "$STAGE/META-INF/com/google/android/update-binary"
fi

(
  cd "$STAGE"
  zip -r9 "$OUT" . -x '*.zip' >/dev/null
)

if unzip -l "$OUT" | grep -q node_modules; then
  echo "ERROR: node_modules in zip" >&2
  exit 1
fi

echo "built dist/JerryManager-$VER.zip"
