#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"

log "RECOVERY" "Start"

hide_recovery_folders

log "RECOVERY" "Finish"
exit 0
