#!/system/bin/sh
set -e
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"

log "TWRP" "Start"

hide_recovery_folders

log "TWRP" "Finish"
exit 0
