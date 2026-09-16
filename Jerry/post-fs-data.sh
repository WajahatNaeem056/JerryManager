#!/system/bin/sh
MODDIR=${0%/*}

. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/paths.sh"
. "$MODDIR/lib/config_env.sh"

mkdir -p "$(dirname "$JERRYMANAGER_LOG_FILE")" 2>/dev/null
: > "$JERRYMANAGER_LOG_FILE" 2>/dev/null || true

resolve_conflicts 2>/dev/null || log "POSTFS" "Warning: resolve_conflicts failed"
