#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"

NUKE_LINEAGE_LOG="$CUSTOM_ROM_LOG_DIR/nuke_lineage_detail.log"

_nl_log() {
    _nll_line="$(date '+%Y-%m-%d %H:%M:%S') [NUKE_LINEAGE] $1"
    echo "$_nll_line"
    ensure_dir "$CUSTOM_ROM_LOG_DIR"
    echo "$_nll_line" >> "$NUKE_LINEAGE_LOG"
    unset _nll_line
}

if [ "$(cfg_get "safemode" "0")" = "1" ]; then
    _nl_log "Skipped — Safe Mode is on"
    exit 0
fi

ensure_dir "$CUSTOM_ROM_LOG_DIR"

resetprop 2>/dev/null | grep -i lineage | while IFS= read -r _nl_line; do
    _nl_prop=${_nl_line#*[}
    _nl_prop=${_nl_prop%%]*}
    [ -z "$_nl_prop" ] && continue
    echo "$(date '+%F %T') DEL $_nl_prop" >> "$NUKE_LINEAGE_LOG"
    resetprop -d "$_nl_prop" 2>/dev/null
done

_nl_log "Done"
exit 0
