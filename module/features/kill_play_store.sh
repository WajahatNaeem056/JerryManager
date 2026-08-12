#!/system/bin/sh
set -e
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"

log "PLAY_STORE" "Start"

# SAFE: Only force-stop Play Store — do NOT use pm clear (clears accounts/data)
# pm clear would log out Google account — intentionally excluded
log "PLAY_STORE" "Force-stopping Play Store (safe mode — account preserved)"
am force-stop com.android.vending >/dev/null 2>&1 || true

log "PLAY_STORE" "Done"
log "PLAY_STORE" "Finish"
exit 0
