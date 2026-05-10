MODDIR=${0%/*}

set +o standalone
unset ASH_STANDALONE

. "$MODDIR/lib/common.sh"

log "ACTION" "Running full integrity pipeline"

sh "$MODDIR/orchestrator.sh" full_integrity || return $?

# Use MODDIR-relative path (most reliable, no hardcoded case sensitivity issues)
if [ -f "$MODDIR/webroot/common/device-info.sh" ]; then
  sh "$MODDIR/webroot/common/device-info.sh"
elif [ -f /data/adb/modules_update/Jerrykey/webroot/common/device-info.sh ]; then
  sh /data/adb/modules_update/Jerrykey/webroot/common/device-info.sh
fi

log "ACTION" "Meets Strong Integrity with Jerrykey Manager"

[ "${0##*/}" = "action.sh" ] && exit 0 || return 0
