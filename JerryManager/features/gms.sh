#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"

log "GMS" "Start"

if ! pm list packages | grep -q com.android.vending; then
  log "GMS" "Warning: Play Store not installed, skipping"
  exit 0
fi

am force-stop com.android.vending >/dev/null 2>&1 || log "GMS" "Warning: Failed to force-stop Play Store"
cmd package trim-caches 999999999 com.android.vending >/dev/null 2>&1 || log "GMS" "Warning: Failed to clear Play Store cache"

log "GMS" "Finish"
exit 0
