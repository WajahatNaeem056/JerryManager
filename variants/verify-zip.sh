#!/bin/sh
# Checks a built module ZIP for one of the two variants.
#   sh variants/verify-zip.sh <zip> normal|trickstore
# normal     : no Trick Store OSS files or patches; multi-backend files still present
# trickstore : every Trick Store OSS file present and byte-identical to variants/trickstore/SHA256SUMS,
#              patched scripts present, OMK/TEESim scripts still present (not stripped)
set -eu
ZIP=${1:?usage: verify-zip.sh <zip> normal|trickstore}
KIND=${2:?usage: verify-zip.sh <zip> normal|trickstore}
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
fail() { echo "verify-zip ($KIND): FAIL: $*" >&2; exit 1; }
ok()   { echo "verify-zip ($KIND): ok: $*"; }

[ -f "$ZIP" ] || fail "no such file: $ZIP"
unzip -tq "$ZIP" >/dev/null || fail "ZIP integrity test failed"
ok "ZIP integrity (unzip -t)"

T=$(mktemp -d); trap 'rm -rf "$T"' 0 HUP INT TERM
unzip -q "$ZIP" -d "$T"

# --- common ---
for f in module.prop customize.sh service.sh post-fs-data.sh uninstall.sh webroot/index.html \
         META-INF/com/google/android/update-binary META-INF/com/google/android/updater-script \
         lib/keystore.sh lib/paths.sh zygisk/arm64-v8a.so dex/classes.dex; do
  [ -f "$T/$f" ] || fail "missing $f"
done
grep -q '^id=JerryManager$' "$T/module.prop" || fail "module.prop id is not JerryManager"
find "$T" -name node_modules | grep -q . && fail "node_modules in zip"
ok "common module files"

# Multi-backend files must be present in both variants (nothing is stripped)
for f in features/omk_sync.sh features/teesim_sync.sh features/keystore_watch.sh lib/omk.sh lib/teesim.sh lib/ini.sh; do
  [ -f "$T/$f" ] || fail "missing $f (OMK/TEESim files must not be removed)"
done
ok "OMK/TEESim files still shipped"

TS_FILES="sepolicy.rule ts/daemon ts/supervisor.sh ts/classes.dex"
for a in arm64-v8a armeabi-v7a x86 x86_64; do TS_FILES="$TS_FILES ts/lib/$a/libTrickyStoreOSS.so ts/lib/$a/libinject.so"; done
MARKERS='_jm_install_ts|TS_CONFLICT_IDS|ts/supervisor\.sh|libTrickyStoreOSS|Built-in Tricky Store OSS'

case "$KIND" in
  normal)
    for f in $TS_FILES; do [ ! -e "$T/$f" ] || fail "Trick Store file present in Normal build: $f"; done
    [ ! -e "$T/ts" ] || fail "ts/ directory present in Normal build"
    if grep -rEl "$MARKERS" "$T" 2>/dev/null | grep -v '^$' | grep -q .; then
      fail "Trick Store marker found in: $(grep -rEl "$MARKERS" "$T" | sed "s#$T/##" | tr '\n' ' ')"
    fi
    grep -q '_module_enabled "teesim"' "$T/lib/keystore.sh" || fail "multi-backend resolver missing in Normal build"
    grep -q 'No supported keystore backend is installed' "$T/customize.sh" || fail "Normal customize.sh gate missing"
    ok "no Trick Store files or integration markers; multi-backend resolver and install gate intact"
    ;;
  trickstore)
    for f in $TS_FILES; do [ -f "$T/$f" ] || fail "missing Trick Store file: $f"; done
    ( cd "$T" && sed 's#  overlay/Jerry/#  #' "$HERE/trickstore/SHA256SUMS" | sha256sum -c - >/dev/null ) \
      || fail "Trick Store file(s) differ from variants/trickstore/SHA256SUMS"
    ok "12 Trick Store OSS files present and byte-identical to the reference (SHA256)"
    grep -q 'TS_CONFLICT_IDS=' "$T/lib/paths.sh"          || fail "paths.sh not patched"
    grep -q 'KEYSTORE_NAME="Tricky Store OSS"' "$T/lib/keystore.sh" || fail "keystore.sh resolver not patched"
    grep -q '_jm_install_ts' "$T/customize.sh"             || fail "customize.sh not patched"
    grep -q 'ts/supervisor.sh' "$T/service.sh"             || fail "service.sh not patched"
    if grep -q 'No supported keystore backend is installed' "$T/customize.sh"; then fail "external-backend install gate still present"; fi
    if grep -q 'keystore_watch.sh' "$T/service.sh"; then fail "keystore_watch.sh still launched from service.sh"; fi
    # never destructive towards other keystore modules: the conflict loops may only write 'disable'
    if grep -En '_ts_(old|c)/remove' "$T/customize.sh" "$T/service.sh" | grep -q .; then
      fail "a 'remove' flag is written to another keystore module"
    fi
    grep -q '_ts_old/disable' "$T/customize.sh" || fail "customize.sh does not disable conflicting keystore modules"
    grep -q '_ts_c/disable' "$T/service.sh"     || fail "service.sh does not disable conflicting keystore modules"
    ok "patched scripts present; external backend gate and watcher gone; conflicting modules are disabled, never removed"
    ;;
  *) fail "unknown variant '$KIND' (use normal|trickstore)" ;;
esac
echo "verify-zip ($KIND): ALL CHECKS PASSED"
