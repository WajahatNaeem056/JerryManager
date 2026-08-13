#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/paths.sh"
. "$MODDIR/lib/config_env.sh"
. "$MODDIR/lib/package_list.sh"
. "$MODDIR/lib/toggle_seed.sh"

log "SERVICE" "Resolving module conflicts..."
resolve_conflicts

log "SERVICE" "Setting boot properties"
apply_boot_props

if [ "$(toybox cat /sys/fs/selinux/enforce 2>/dev/null)" = "0" ]; then
    chmod 640 /sys/fs/selinux/enforce 2>/dev/null || true
    chmod 440 /sys/fs/selinux/policy  2>/dev/null || true
fi

_feature_enabled() {
  case "$1" in
    *) _fe_default=1 ;;
  esac
  [ "$(cfg_get "$1" "$_fe_default")" != "0" ]
}

mkdir -p "$JERRYKEY_CONFIG_DIR" 2>/dev/null

seed_toggle_defaults

if [ "$KSU" != "true" ]; then
    log "SERVICE" "Magisk detected — polling sys.boot_completed"
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 1
    done

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
        log "SERVICE" "Boot hardening applied"
    fi

    if _feature_enabled toggle_recovery; then
        log "SERVICE" "Hiding recovery folders..."
        hide_recovery_folders
        log "SERVICE" "Recovery folders hidden"
    fi

    if _feature_enabled toggle_rom_spoof; then
        log "SERVICE" "Blocking ROM spoof engines..."
        ( block_rom_spoof_engines ) &
    fi

    if _feature_enabled toggle_bootloader_spoofer; then
        log "SERVICE" "Disabling bootloader spoofer..."
        disable_bootloader_spoofer
    fi

    if _feature_enabled toggle_adb_disabler; then
        log "SERVICE" "Disabling ADB & debugging..."
        sh "$MODDIR/features/adb_disabler.sh" 2>/dev/null || true
    fi

    if _feature_enabled toggle_rom_fingerprint; then
        log "SERVICE" "Cleaning ROM fingerprint..."
        sh "$MODDIR/features/rom_fingerprint.sh" 2>/dev/null || true
    fi

    if _feature_enabled toggle_hide_lineage; then
        log "SERVICE" "Hiding Lineage props..."
        sh "$MODDIR/features/hide_lineage.sh" 2>/dev/null || true
    fi

    if _feature_enabled toggle_nuke_lineage; then
        log "SERVICE" "Nuking Lineage props..."
        sh "$MODDIR/features/nuke_lineage.sh" 2>/dev/null || true
    fi

    if _feature_enabled toggle_hide_custom_rom; then
        log "SERVICE" "Cleaning custom ROM/GApps traces..."
        sh "$MODDIR/features/hide_custom_rom.sh" 2>/dev/null || true
    fi

    if _feature_enabled toggle_remove_custom_rom_props; then
        log "SERVICE" "Removing custom ROM properties (24-ROM pattern)..."
        sh "$MODDIR/features/remove_custom_rom_props.sh" 2>/dev/null || true
    fi

    if _feature_enabled toggle_suspicious_props; then
        sh "$MODDIR/features/suspicious_props.sh" >/dev/null 2>&1 || true
    fi

    if _feature_enabled toggle_lsposed; then
        sh "$MODDIR/features/lsposed.sh" 2>/dev/null || true
    fi

    if _feature_enabled toggle_action_gms; then
        sh "$MODDIR/features/gms.sh" 2>/dev/null || true
    fi

    (
        sleep 120
        log "SERVICE" "Delayed re-apply: reapplying critical props"
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
        log "SERVICE" "Delayed re-apply done"
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

    log "SERVICE" "Boot hardening applied"
else
    log "SERVICE" "KernelSU/APatch detected — boot-completed.sh will handle hardening"
fi

log "SERVICE" "Done"
