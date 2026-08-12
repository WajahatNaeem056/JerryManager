#!/system/bin/sh
MODDIR=${0%/*}
# Guard: KernelSU and APatch both set $KSU=true; skip if not running under them
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

# ── Always keep toggle_suspicious_props ON ────────────────────────────────────
# This used to be a one-time, marker-guarded migration (fixing installs stuck
# at an old buggy "0" default). That approach failed to self-heal: the
# marker file lives in /data/adb/JerryManager/config/, which is outside the
# module folder and survives module delete+reinstall, so once the marker
# existed the fix never ran again even if the value somehow ended up "0"
# again. This feature is now unconditionally forced ON every boot instead.
cfg_set "toggle_suspicious_props" "1"

# ── One-time cleanup: remove toggle_kill_play_store.val ──────────────────────
# This key is fully retired — Play Store/GMS management is now entirely
# controlled by toggle_action_gms (see features/gms.sh). The old .val file
# is leftover residue from before that consolidation and is never read by
# any script anymore; delete it so config.log doesn't show a dead/confusing
# entry. Guarded by its own marker so this runs once.
_cleanup_marker="$JERRYKEY_CONFIG_DIR/.cleaned_kill_play_store_key"
if [ ! -f "$_cleanup_marker" ]; then
    if [ -f "$JERRYKEY_CONFIG_DIR/toggle_kill_play_store.val" ]; then
        rm -f "$JERRYKEY_CONFIG_DIR/toggle_kill_play_store.val" 2>/dev/null
        log "BOOT" "Cleanup: removed retired toggle_kill_play_store.val"
    fi
    touch "$_cleanup_marker" 2>/dev/null
fi
unset _cleanup_marker

# ── One-time cleanup: remove stale root-level config.log ─────────────────────
# Leftover from an older version of export_logs.sh, before it was renamed
# to write JerryManager.log instead. No current script writes to
# config.log anymore; delete it so it doesn't sit around as stale, confusing
# residue in the JerryManager root. Guarded by its own marker so this runs once.
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

# Seed any never-touched toggle's default to disk so the WebUI's file-based
# reads and the shell's _feature_enabled() logic always agree. Per-toggle
# defaults only (see lib/toggle_seed.sh) — never overwrites an existing .val.
seed_toggle_defaults

# ── Capture real ROM identity BEFORE rom_fingerprint.sh can strip the evidence ──
# Cached via cfg_set so device-info.sh can read it any time later, even after
# the identifying props below have been deleted/rewritten by spoofing.
. "$MODDIR/lib/rom_detect.sh"
cfg_set "cached_rom_status" "$(detect_rom)"

# Critical root-hiding props (oem_unlock_allowed/supported, warranty bits) —
# always applied, independent of the Boot Hardening toggle below.
apply_critical_hiding_props

# Boot Hardening
if _feature_enabled toggle_boot_hardening; then
    apply_boot_hardening
    # Harden sensitive proc files
    chmod 440 /proc/cmdline       2>/dev/null || true
    chmod 440 /proc/net/unix      2>/dev/null || true
    find /vendor/bin /system/bin -name install-recovery.sh \
        -exec chmod 440 {} + 2>/dev/null || true
    chmod 750 /system/addon.d     2>/dev/null || true
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

# Disable ADB & Debugging
if _feature_enabled toggle_adb_disabler; then
    log "BOOT" "Disabling ADB & debugging..."
    sh "$MODDIR/features/adb_disabler.sh" 2>/dev/null || true
fi

# Clean ROM Fingerprint
if _feature_enabled toggle_rom_fingerprint; then
    log "BOOT" "Cleaning ROM fingerprint..."
    sh "$MODDIR/features/rom_fingerprint.sh" 2>/dev/null || true
fi

# Hide Lineage (ported from Integrity Box override_lineage.sh)
if _feature_enabled toggle_hide_lineage; then
    log "BOOT" "Hiding Lineage props..."
    sh "$MODDIR/features/hide_lineage.sh" 2>/dev/null || true
fi

# Nuke Lineage — off by default, medium risk (ported from Integrity Box force_override.sh)
if _feature_enabled toggle_nuke_lineage; then
    log "BOOT" "Nuking Lineage props..."
    sh "$MODDIR/features/nuke_lineage.sh" 2>/dev/null || true
fi

# Hide Custom ROM (ported from Integrity Box susfiles.sh — GApps installer log cleanup)
if _feature_enabled toggle_hide_custom_rom; then
    log "BOOT" "Cleaning custom ROM/GApps traces..."
    sh "$MODDIR/features/hide_custom_rom.sh" 2>/dev/null || true
fi

# Remove Custom ROM Properties — off by default, medium risk (ported from BRENE config_rom_props)
if _feature_enabled toggle_remove_custom_rom_props; then
    log "BOOT" "Removing custom ROM properties (24-ROM pattern)..."
    sh "$MODDIR/features/remove_custom_rom_props.sh" 2>/dev/null || true
fi

# Suspicious Props clean
if _feature_enabled toggle_suspicious_props; then
    sh "$MODDIR/features/suspicious_props.sh" >/dev/null 2>&1 || true
fi

# LSPosed ODEX Clean
if _feature_enabled toggle_lsposed; then
    sh "$MODDIR/features/lsposed.sh" 2>/dev/null || true
fi

log "BOOT" "Running boot-time action pipeline features..."

# gms.sh handles Play Store/GMS force-stop and cache-clear together, both
# controlled by the single toggle_action_gms toggle (see features/gms.sh).
# The standalone kill_play_store.sh script is intentionally NOT called here;
# it's reserved for the manual Magisk action-button trigger only (see
# action.sh), not the automated boot pipeline.
_feature_enabled toggle_action_gms            && sh "$MODDIR/features/gms.sh" 2>/dev/null || true
_feature_enabled toggle_action_target         && sh "$MODDIR/features/target.sh" 2>/dev/null || true
_feature_enabled toggle_auto_target           && sh "$MODDIR/features/auto_target.sh" 2>/dev/null || true
_feature_enabled toggle_action_security_patch && sh "$MODDIR/features/security_patch.sh" 2>/dev/null || true
_feature_enabled toggle_action_boot_hash      && sh "$MODDIR/features/boot_hash.sh" 2>/dev/null || true

# ── PIF needs network, which often isn't up yet this early in boot ───────────
# Run it in the background with its own retry loop (every 30s, up to 5 min)
# instead of a single early attempt that fails before Wi-Fi/data connects.
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

# Re-affirm verified boot state after full boot
resetprop -n ro.boot.verifiedbootstate green
resetprop -n vendor.boot.verifiedbootstate green
resetprop -n partition.system.verified 2
resetprop -n partition.vendor.verified 2
resetprop -n partition.product.verified 2
resetprop -n partition.system_ext.verified 2
resetprop -n partition.odm.verified 2

# ── Delayed re-apply (120s) — props system may have overridden ───────────────
(
    sleep 120
    log "BOOT" "Delayed re-apply: reapplying critical props"
    sp_try ro.crypto.state encrypted
    sp_try ro.build.tags release-keys
    sp_try ro.boot.verifiedbootstate green
    sp_try vendor.boot.verifiedbootstate green
    # sys.oem_unlock_allowed deleted, not force-set — see apply_critical_hiding_props() in lib/common.sh
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
    # Refresh JerryManager.log with the post-reapply state (see features/export_logs.sh)
    [ -f "$MODDIR/features/export_logs.sh" ] && sh "$MODDIR/features/export_logs.sh" >/dev/null 2>&1
) &

# ── Hourly suspicious props cleanup ──────────────────────────────────────────
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
