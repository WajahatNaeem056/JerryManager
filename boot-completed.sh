#!/system/bin/sh
MODDIR=${0%/*}
# Guard: KernelSU and APatch both set $KSU=true; skip if not running under them
[ -z "$KSU" ] && exit 0

. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/paths.sh"
. "$MODDIR/lib/config_env.sh"

log "BOOT" "Boot completed — finalizing"

_feature_enabled() { [ "$(cfg_get "$1" 1)" != "0" ]; }

# Boot Hardening
if _feature_enabled toggle_boot_hardening; then
    apply_boot_hardening
    log "BOOT" "Boot hardening applied"
fi

# Auto-Hide Recovery Folders
if _feature_enabled toggle_recovery; then
    log "BOOT" "Hiding recovery folders..."
    hide_recovery_folders
    log "BOOT" "Recovery folders hidden"
fi

# Block ROM Spoof Engines
if _feature_enabled toggle_rom_spoof; then
    log "BOOT" "Blocking ROM spoof engines..."
    block_rom_spoof_engines
fi

# Disable Bootloader Spoofer
if _feature_enabled toggle_bootloader_spoofer; then
    log "BOOT" "Disabling bootloader spoofer..."
    disable_bootloader_spoofer
fi

# LSPosed ODEX Clean
if _feature_enabled toggle_lsposed; then
    sh "$MODDIR/features/lsposed.sh" 2>/dev/null || true
fi

log "BOOT" "Running boot-time action pipeline features..."

_feature_enabled toggle_action_gms     && sh "$MODDIR/features/gms.sh" 2>/dev/null || true
_feature_enabled toggle_action_target  && sh "$MODDIR/features/target.sh" 2>/dev/null || true
_feature_enabled toggle_action_security_patch && sh "$MODDIR/features/security_patch.sh" 2>/dev/null || true
_feature_enabled toggle_action_boot_hash      && sh "$MODDIR/features/boot_hash.sh" 2>/dev/null || true
_feature_enabled toggle_action_pif            && sh "$MODDIR/features/pif.sh" 2>/dev/null || true

# Re-affirm verified boot state after full boot
resetprop -n ro.boot.verifiedbootstate green
resetprop -n vendor.boot.verifiedbootstate green
resetprop -n partition.system.verified 2
resetprop -n partition.vendor.verified 2
resetprop -n partition.product.verified 2
resetprop -n partition.system_ext.verified 2
resetprop -n partition.odm.verified 2

. "$MODDIR/lib/paths.sh"
_release=$(getprop ro.build.version.release 2>/dev/null || echo "Unknown")
if [ -f "$TARGET_FILE" ]; then
    cfg_set "override.description" "Active | $_release"
    log "BOOT" "Description set to: Active | $_release"
else
    cfg_set "override.description" "Run action button to set up keybox"
    log "BOOT" "Description set to: Run action button to set up keybox"
fi
unset _release

log "BOOT" "Done"
