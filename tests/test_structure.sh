#!/bin/sh
# Confirms the Jerry/ directory has the pieces JerryManager actually needs
# to install and run — catches accidental deletions before they ship.
set -u
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
MODULE_DIR="$SCRIPT_DIR/../module"

status=0
check() {
    if [ -e "$MODULE_DIR/$1" ]; then
        echo "  ok: $1"
    else
        echo "  FAIL: missing $1"
        status=1
    fi
}

echo "Checking core module files..."
check "module.prop"
check "system.prop"
check "customize.sh"
check "service.sh"
check "post-fs-data.sh"
check "boot-completed.sh"
check "uninstall.sh"
check "META-INF/com/google/android/update-binary"
check "META-INF/com/google/android/updater-script"

echo "Checking lib/..."
check "lib/common.sh"
check "lib/paths.sh"
check "lib/config_env.sh"

echo "Checking webroot/..."
check "webroot/index.html"
check "webroot/config.json"

echo "Checking pipelines/..."
check "pipelines/root_hide"
check "pipelines/banking_mode"
check "pipelines/full_integrity"

exit $status
