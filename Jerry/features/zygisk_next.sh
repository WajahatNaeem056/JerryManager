#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"

log "ZYGISK_NEXT" "Start"

REQUIRED="1.3.0"

ZYNEXT_DIR="/data/adb/modules/zygisksu"
[ ! -d "$ZYNEXT_DIR" ] && ZYNEXT_DIR="/data/adb/modules_update/zygisksu"

ZYNEXT_PROP="$ZYNEXT_DIR/module.prop"
SCRIPT_FILE="$ZYNEXT_DIR/bin/zygiskd"

if [ ! -f "$ZYNEXT_PROP" ]; then
  log "ZYGISK_NEXT" "Error: Zygisk Next module not found"
  exit 1
fi

CURRENT=$(grep "^version=" "$ZYNEXT_PROP" | cut -d'=' -f2 | cut -d' ' -f1)

version_ge "$CURRENT" "$REQUIRED" || {
  log "ZYGISK_NEXT" "Error: Zygisk Next version too low, need $REQUIRED"
  exit 0
}

ensure_dir "$(dirname "$SCRIPT_FILE")"

zygisk_next() {
  [ -n "$1" ] && "$SCRIPT_FILE" "$@" 2>/dev/null
}

zygisk_next enforce-denylist just_umount
zygisk_next memory-type anonymous
zygisk_next linker builtin

log "ZYGISK_NEXT" "Finish"
exit 0
