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

mkdir -p "$JERRYMANAGER_CONFIG_DIR" 2>/dev/null

_cleanup_marker2="$JERRYMANAGER_CONFIG_DIR/.cleaned_stale_config_log"
if [ ! -f "$_cleanup_marker2" ]; then
    _stale_config_log="$(dirname "$JERRYMANAGER_CONFIG_DIR")/config.log"
    if [ -f "$_stale_config_log" ]; then
        rm -f "$_stale_config_log" 2>/dev/null
        log "SERVICE" "Cleanup: removed stale root-level config.log"
    fi
    unset _stale_config_log
    touch "$_cleanup_marker2" 2>/dev/null
fi
unset _cleanup_marker2

migrate_config_keys

seed_toggle_defaults

_teesim_auto_marker="$JERRYMANAGER_CONFIG_DIR/.teesim_auto_enabled"
if [ ! -f "$_teesim_auto_marker" ] && \
   { [ -d "/data/adb/modules/teesim" ] || [ -d "/data/adb/modules_update/teesim" ]; }; then
    cfg_set toggle_teesim_sync 1
    touch "$_teesim_auto_marker" 2>/dev/null
    log "SERVICE" "TEESimulator detected — auto-enabled Sync TEESimulator Config"
fi
unset _teesim_auto_marker

if [ "$KSU" != "true" ]; then
    log "SERVICE" "Magisk detected — polling sys.boot_completed"
else
    log "SERVICE" "KernelSU/APatch detected — polling sys.boot_completed"
fi
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
    sh "$MODDIR/features/recovery.sh" 2>/dev/null || true
fi

if _feature_enabled toggle_rom_spoof; then
    log "SERVICE" "Blocking ROM spoof engines..."
    if [ "$KSU" != "true" ]; then
        ( block_rom_spoof_engines ) &
    else
        block_rom_spoof_engines
    fi
fi

if _feature_enabled toggle_bootloader_spoofer; then
    log "SERVICE" "Disabling bootloader spoofer..."
    disable_bootloader_spoofer
fi

# toggle:script:label — label empty means run silently (no log line)
for _sv_entry in \
    "toggle_adb_disabler:adb_disabler:Disabling ADB & debugging..." \
    "toggle_rom_fingerprint:rom_fingerprint:Cleaning ROM fingerprint..." \
    "toggle_lineage_identity_cleanup:lineage_identity_cleanup:Hiding Lineage props..." \
    "toggle_nuke_lineage:nuke_lineage:Nuking Lineage props..." \
    "toggle_custom_rom_identity_cleanup:custom_rom_identity_cleanup:Cleaning custom ROM/GApps traces..." \
    "toggle_hide_rom_identifier:hide_rom_identifier:Removing custom ROM properties (24-ROM pattern)..." \
    "toggle_pif_traces:pif2:Cleaning PIF/PixelProps trace properties..." \
    "toggle_suspicious_props:suspicious_props:" \
    "toggle_action_gms:gms:" \
    "toggle_action_target:target:" \
    "toggle_auto_target:auto_target:" \
    "toggle_teesim_sync:teesim_sync:Syncing TEESimulator config..." \
    "toggle_action_security_patch:security_patch:" \
    "toggle_action_boot_hash:boot_hash:"
do
    _sv_toggle="${_sv_entry%%:*}"
    _sv_rest="${_sv_entry#*:}"
    _sv_script="${_sv_rest%%:*}"
    _sv_label="${_sv_rest#*:}"
    _feature_enabled "$_sv_toggle" || continue
    [ -n "$_sv_label" ] && log "SERVICE" "$_sv_label"
    if [ "$_sv_toggle" = "toggle_suspicious_props" ]; then
        sh "$MODDIR/features/${_sv_script}.sh" >/dev/null 2>&1 || true
    else
        sh "$MODDIR/features/${_sv_script}.sh" 2>/dev/null || true
    fi
done
unset _sv_entry _sv_toggle _sv_rest _sv_script _sv_label

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
    _feature_enabled toggle_recovery && hide_recovery_folders
    log "SERVICE" "Delayed re-apply done"
    [ -f "$MODDIR/features/export_logs.sh" ] && sh "$MODDIR/features/export_logs.sh" >/dev/null 2>&1
) &

if _feature_enabled toggle_suspicious_props; then
    (
        while true; do
            sleep 86400
            sh "$MODDIR/features/suspicious_props.sh" >/dev/null 2>&1 || true
        done
    ) &
fi

_release=$(getprop ro.build.version.release 2>/dev/null || echo "Unknown")
if [ -f "$TARGET_FILE" ]; then
    cfg_set "override.description" "Active | $_release"
    log "SERVICE" "Description set to: Active | $_release"
else
    cfg_set "override.description" "Run action button to set up keybox"
    log "SERVICE" "Description set to: Run action button to set up keybox"
fi
unset _release

log "SERVICE" "Done"
