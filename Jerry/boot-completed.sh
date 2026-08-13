#!/system/bin/sh
MODDIR=${0%/*}
[ -z "$KSU" ] && exit 0

. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/paths.sh"
. "$MODDIR/lib/config_env.sh"
. "$MODDIR/lib/package_list.sh"
. "$MODDIR/lib/toggle_seed.sh"

log "BOOT" "Boot completed — finalizing"

_feature_enabled() {
  case "$1" in
    *) _fe_default=1 ;;
  esac
  [ "$(cfg_get "$1" "$_fe_default")" != "0" ]
}

mkdir -p "$JERRYKEY_CONFIG_DIR" 2>/dev/null

cfg_set "toggle_suspicious_props" "1"

_cleanup_marker="$JERRYKEY_CONFIG_DIR/.cleaned_kill_play_store_key"
if [ ! -f "$_cleanup_marker" ]; then
    if [ -f "$JERRYKEY_CONFIG_DIR/toggle_kill_play_store.val" ]; then
        rm -f "$JERRYKEY_CONFIG_DIR/toggle_kill_play_store.val" 2>/dev/null
        log "BOOT" "Cleanup: removed retired toggle_kill_play_store.val"
    fi
    touch "$_cleanup_marker" 2>/dev/null
fi
unset _cleanup_marker

_cleanup_marker2="$JERRYKEY_CONFIG_DIR/.cleaned_stale_config_log"
if [ ! -f "$_cleanup_marker2" ]; then
    _stale_config_log="$(dirname "$JERRYKEY_CONFIG_DIR")/config.log"
    if [ -f "$_stale_config_log" ]; then
        rm -f "$_stale_config_log" 2>/dev/null
        log "BOOT" "Cleanup: removed stale root-level config.log"
    fi
    unset _stale_config_log
    touch "$_cleanup_marker2" 2>/dev/null
fi
unset _cleanup_marker2

seed_toggle_defaults

. "$MODDIR/lib/rom_detect.sh"
cfg_set "cached_rom_status" "$(detect_rom)"

apply_critical_hiding_props

if _feature_enabled toggle_boot_hardening; then
    apply_boot_hardening
    chmod 440 /proc/cmdline       2>/dev/null || true
    chmod 440 /proc/net/unix      2>/dev/null || true
    find /vendor/bin /system/bin -name install-recovery.sh \
        -exec chmod 440 {} + 2>/dev/null || true
    chmod 750 /system/addon.d     2>/dev/null || true
    log "BOOT" "Boot hardening applied"
fi

if _feature_enabled toggle_recovery; then
    log "BOOT" "Hiding recovery folders..."
    hide_recovery_folders
    log "BOOT" "Recovery folders hidden"
fi

if _feature_enabled toggle_rom_spoof; then
    log "BOOT" "Blocking ROM spoof engines..."
    block_rom_spoof_engines
fi

if _feature_enabled toggle_bootloader_spoofer; then
    log "BOOT" "Disabling bootloader spoofer..."
    disable_bootloader_spoofer
fi

if _feature_enabled toggle_adb_disabler; then
    log "BOOT" "Disabling ADB & debugging..."
    sh "$MODDIR/features/adb_disabler.sh" 2>/dev/null || true
fi

if _feature_enabled toggle_rom_fingerprint; then
    log "BOOT" "Cleaning ROM fingerprint..."
    sh "$MODDIR/features/rom_fingerprint.sh" 2>/dev/null || true
fi

if _feature_enabled toggle_hide_lineage; then
    log "BOOT" "Hiding Lineage props..."
    sh "$MODDIR/features/hide_lineage.sh" 2>/dev/null || true
fi

if _feature_enabled toggle_nuke_lineage; then
    log "BOOT" "Nuking Lineage props..."
    sh "$MODDIR/features/nuke_lineage.sh" 2>/dev/null || true
fi

if _feature_enabled toggle_hide_custom_rom; then
    log "BOOT" "Cleaning custom ROM/GApps traces..."
    sh "$MODDIR/features/hide_custom_rom.sh" 2>/dev/null || true
fi

if _feature_enabled toggle_remove_custom_rom_props; then
    log "BOOT" "Removing custom ROM properties (24-ROM pattern)..."
    sh "$MODDIR/features/remove_custom_rom_props.sh" 2>/dev/null || true
fi

if _feature_enabled toggle_suspicious_props; then
    sh "$MODDIR/features/suspicious_props.sh" >/dev/null 2>&1 || true
fi

if _feature_enabled toggle_lsposed; then
    sh "$MODDIR/features/lsposed.sh" 2>/dev/null || true
fi

log "BOOT" "Running boot-time action pipeline features..."

_feature_enabled toggle_action_gms            && sh "$MODDIR/features/gms.sh" 2>/dev/null || true
_feature_enabled toggle_action_target         && sh "$MODDIR/features/target.sh" 2>/dev/null || true
_feature_enabled toggle_auto_target           && sh "$MODDIR/features/auto_target.sh" 2>/dev/null || true
_feature_enabled toggle_action_security_patch && sh "$MODDIR/features/security_patch.sh" 2>/dev/null || true
_feature_enabled toggle_action_boot_hash      && sh "$MODDIR/features/boot_hash.sh" 2>/dev/null || true

if _feature_enabled toggle_action_pif; then
    (
        _pif_tries=0
        while [ "$_pif_tries" -lt 10 ]; do
            sh "$MODDIR/features/pif.sh" 2>/dev/null && break
            _pif_tries=$((_pif_tries + 1))
            sleep 30
        done
        unset _pif_tries
    ) &
fi

resetprop -n ro.boot.verifiedbootstate green
resetprop -n vendor.boot.verifiedbootstate green
resetprop -n partition.system.verified 2
resetprop -n partition.vendor.verified 2
resetprop -n partition.product.verified 2
resetprop -n partition.system_ext.verified 2
resetprop -n partition.odm.verified 2

(
    sleep 120
    log "BOOT" "Delayed re-apply: reapplying critical props"
    sp_try ro.crypto.state encrypted
    sp_try ro.build.tags release-keys
    sp_try ro.boot.verifiedbootstate green
    sp_try vendor.boot.verifiedbootstate green
    resetprop --delete sys.oem_unlock_allowed 2>/dev/null || true
    sp_try ro.oem_unlock_supported 0
    sp_try ro.boot.warranty_bit 0
    sp_try ro.warranty_bit 0
    sp_try ro.vendor.warranty_bit 0
    sp_try ro.vendor.boot.warranty_bit 0
    sp_try ro.secureboot.lockstate locked
    sp_try ro.boot.vbmeta.device_state locked
    sp_try vendor.boot.vbmeta.device_state locked
    sp_try ro.boot.flash.locked 1
    sp_try ro.boot.veritymode enforcing
    hide_recovery_folders
    log "BOOT" "Delayed re-apply done"
    [ -f "$MODDIR/features/export_logs.sh" ] && sh "$MODDIR/features/export_logs.sh" >/dev/null 2>&1
) &

if _feature_enabled toggle_suspicious_props; then
    (
        while true; do
            sleep 3600
            sh "$MODDIR/features/suspicious_props.sh" >/dev/null 2>&1 || true
        done
    ) &
fi

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
