#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"

log "PIF" "Start"

PIF_DIR="/data/adb/modules/playintegrityfix"

check_network || { log "PIF" "Error: No internet connection"; exit 1; }

if [ ! -d "$PIF_DIR" ]; then
  log "PIF" "Warning: Play Integrity Fix not installed, skipping"
  exit 0
fi

MODULE_NAME=$(grep "^name=" "$PIF_DIR/module.prop" 2>/dev/null | cut -d= -f2-)
[ -z "$MODULE_NAME" ] && { log "PIF" "Error: Cannot read module.prop"; exit 1; }

case "$MODULE_NAME" in
  "Play Integrity Fix [INJECT]")
    log "PIF" "Detected INJECT variant"
    sh "$PIF_DIR/autopif_ota.sh" || log "PIF" "Warning: autopif_ota.sh failed"
    sh "$PIF_DIR/autopif.sh" || log "PIF" "Warning: autopif.sh failed"
    ;;
  "Play Integrity Fork")
    log "PIF" "Detected Fork variant"
    sh "$PIF_DIR/autopif4.sh" -m || log "PIF" "Warning: autopif4.sh failed"
    ;;
  "Play Integrity Fix")
    log "PIF" "Detected original PIF variant"
    [ -f "$PIF_DIR/autopif.sh" ] && sh "$PIF_DIR/autopif.sh" || log "PIF" "Warning: autopif.sh failed or not found"
    ;;
  *)
    log "PIF" "Warning: Unknown module variant: $MODULE_NAME — skipping safely"
    exit 0
    ;;
esac

log "PIF" "Finish"
exit 0
