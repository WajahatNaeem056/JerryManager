#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/config_env.sh"

[ "$(cfg_get toggle_recovery 1)" = "0" ] && exit 0

log "RECOVERY" "Start"

if hide_recovery_folders; then
    log "RECOVERY" "Finish - hidden successfully"
else
    log "RECOVERY" "Finish - one or more recovery folders could not be removed"
fi
exit 0
