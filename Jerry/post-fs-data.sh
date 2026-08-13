#!/system/bin/sh
set -e
MODDIR=${0%/*}

. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/paths.sh"
. "$MODDIR/lib/config_env.sh"

mkdir -p "$(dirname "$JERRYKEY_LOG_FILE")" 2>/dev/null
: > "$JERRYKEY_LOG_FILE" 2>/dev/null || true

resolve_conflicts
