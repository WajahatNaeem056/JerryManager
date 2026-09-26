#!/system/bin/sh
MODDIR=${0%/*}

. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/paths.sh"
. "$MODDIR/lib/config_env.sh"
. "$MODDIR/lib/toggle_seed.sh"

mkdir -p "$(dirname "$JERRYMANAGER_LOG_FILE")" 2>/dev/null
: > "$JERRYMANAGER_LOG_FILE" 2>/dev/null || true

resolve_conflicts 2>/dev/null || log "POSTFS" "Warning: resolve_conflicts failed"

# Run early — service.sh is too late, TrickyStore's certgen daemon
# already loaded by then, forcing an extra reboot to pick up the fix.
if _feature_enabled "toggle_action_boot_hash"; then
    sh "$MODDIR/features/boot_hash.sh" 2>/dev/null || log "POSTFS" "Warning: early boot_hash run failed"
fi
