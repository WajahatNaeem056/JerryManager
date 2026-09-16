#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/config_env.sh"

[ "$(cfg_get toggle_recovery 1)" = "0" ] && exit 0

log "RECOVERY" "Start"

hide_recovery_folders

log "RECOVERY" "Finish"
exit 0
