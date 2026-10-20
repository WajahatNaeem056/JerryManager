#!/system/bin/sh
MODDIR=${0%/*}

. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/paths.sh"
. "$MODDIR/lib/config_env.sh"
. "$MODDIR/lib/toggle_seed.sh"

mkdir -p "$(dirname "$JERRYMANAGER_LOG_FILE")" 2>/dev/null
: > "$JERRYMANAGER_LOG_FILE" 2>/dev/null || true

# Only when built-in PIF is installed (skippable at install): keep a standalone PIF/Fork disabled, it would inject into GMS twice.
if [ -d "$MODDIR/zygisk" ] && [ -d /data/adb/modules/playintegrityfix ] && [ ! -f /data/adb/modules/playintegrityfix/disable ]; then
    touch /data/adb/modules/playintegrityfix/disable 2>/dev/null
    log "POSTFS" "Standalone PIF found, disabled (built-in PIF is used)"
fi
if [ -d "$MODDIR/zygisk" ]; then
    # Magisk: with DenyList enforced, GMS on the list gets Zygisk modules (PIF) unloaded, so take it off.
    if command -v magisk >/dev/null 2>&1 && magisk --denylist status >/dev/null 2>&1; then
        magisk --denylist rm com.google.android.gms >/dev/null 2>&1
    fi
    # First boot: seed pif.prop from the bundled default so the PIF Settings toggles have a file to edit.
    [ -s /data/adb/pif.prop ] || cp "$MODDIR/pif.prop" /data/adb/pif.prop 2>/dev/null
fi

resolve_conflicts 2>/dev/null || log "POSTFS" "Warning: resolve_conflicts failed"
