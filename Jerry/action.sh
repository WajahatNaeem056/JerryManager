MODDIR=${0%/*}

set +o standalone
unset ASH_STANDALONE

. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/paths.sh"
. "$MODDIR/lib/config_env.sh"

log "ACTION" "Running full integrity pipeline"

sh "$MODDIR/orchestrator.sh" full_integrity || return $?

if [ -f "$MODDIR/webroot/common/device-info.sh" ]; then
  sh "$MODDIR/webroot/common/device-info.sh"
elif [ -f /data/adb/modules_update/Jerrykey/webroot/common/device-info.sh ]; then
  sh /data/adb/modules_update/Jerrykey/webroot/common/device-info.sh
fi

log "ACTION" "Meets Strong Integrity with Jerrykey Manager"

update_description

if [ -f "$MODDIR/features/export_logs.sh" ]; then
  _export_path=$(sh "$MODDIR/features/export_logs.sh" 2>/dev/null)
  [ -n "$_export_path" ] && log "ACTION" "Config log exported to $_export_path"
  unset _export_path
fi

[ "${0##*/}" = "action.sh" ] && exit 0 || return 0
