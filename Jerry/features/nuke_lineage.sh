#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"

NUKE_LINEAGE_LOG="$JERRYKEY_DIR/nuke_lineage.log"

if [ "$(cfg_get "safemode" "0")" = "1" ]; then
    log "NUKE_LINEAGE" "Skipped — Safe Mode is on"
    exit 0
fi

ensure_dir "$JERRYKEY_DIR"

resetprop 2>/dev/null | grep -i lineage | while IFS= read -r _nl_line; do
    _nl_prop=${_nl_line#*[}
    _nl_prop=${_nl_prop%%]*}
    [ -z "$_nl_prop" ] && continue
    echo "$(date '+%F %T') DEL $_nl_prop" >> "$NUKE_LINEAGE_LOG"
    resetprop -d "$_nl_prop" 2>/dev/null
done

log "NUKE_LINEAGE" "Done — see nuke_lineage.log for details"
exit 0
