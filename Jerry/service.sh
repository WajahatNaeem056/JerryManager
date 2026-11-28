#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/paths.sh"
. "$MODDIR/lib/config_env.sh"
. "$MODDIR/lib/keystore.sh"
. "$MODDIR/lib/package_list.sh"
. "$MODDIR/lib/toggle_seed.sh"
. "$MODDIR/lib/root_detect.sh"

log "SERVICE" "Resolving module conflicts..."
resolve_conflicts

if _feature_enabled toggle_boot_props; then
    log "SERVICE" "Setting boot properties"
    apply_boot_props
fi

resolve_keystore_backend
log "SERVICE" "Keystore backend: $KEYSTORE_NAME ($KEYSTORE_BACKEND)"

if [ "$KEYSTORE_BACKEND" = "trickystore" ] && [ "$KEYSTORE_BUILTIN" = "1" ]; then
    # Built-in Tricky Store: start before boot_completed, after boot props
    if [ -f "$MODDIR/ts/supervisor.sh" ]; then
        log "SERVICE" "Starting built-in Tricky Store OSS"
        sh "$MODDIR/ts/supervisor.sh" 2>/dev/null
    fi
else
    log "SERVICE" "Built-in Tricky Store OSS not started ($KEYSTORE_NAME is active)"
fi

# SELinux permissive: hide state from apps
if [ "$(toybox cat /sys/fs/selinux/enforce 2>/dev/null)" = "0" ]; then
    chmod 640 /sys/fs/selinux/enforce 2>/dev/null || true
    chmod 440 /sys/fs/selinux/policy  2>/dev/null || true
fi

mkdir -p "$JERRYMANAGER_CONFIG_DIR" 2>/dev/null

# One-time stale config.log cleanup
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

cfg_delete "cached_rom_status"
cfg_delete "cached_root_type"

write_state_snapshot

# Hide/restore other root solutions' folders
if _feature_enabled toggle_multiroot_hide; then
    sh "$MODDIR/features/multiroot_hide.sh" --hide 2>/dev/null || true
else
    sh "$MODDIR/features/multiroot_hide.sh" --restore 2>/dev/null || true
fi

_ROOT_FAMILY=$(detect_root_family)
log "SERVICE" "Root: ${_ROOT_FAMILY:-unknown} — polling sys.boot_completed"
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
done

# Re-resolve boot hash from TEE once keystore is up
if _feature_enabled toggle_action_boot_hash; then
    sh "$MODDIR/features/boot_hash.sh" --refresh 2>/dev/null \
        || log "SERVICE" "Warning: post-boot boot_hash refresh failed"
fi

_feature_enabled toggle_boot_props && apply_critical_hiding_props

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

if _feature_enabled toggle_rom_spoof && ! _feature_enabled toggle_rom_builtin_spoof; then
    log "SERVICE" "Blocking ROM spoof engines..."
    # Magisk: background; KSU/APatch: foreground
    case "$_ROOT_FAMILY" in
        kernelsu|apatch) block_rom_spoof_engines ;;
        *)               ( block_rom_spoof_engines ) & ;;
    esac
fi

if _feature_enabled toggle_bootloader_spoofer; then
    log "SERVICE" "Disabling bootloader spoofer..."
    disable_bootloader_spoofer
fi

# toggle:script:label (empty label = silent)
for _sv_entry in \
    "toggle_adb_disabler:adb_disabler:Disabling ADB & debugging..." \
    "toggle_rom_fingerprint:rom_fingerprint:Cleaning ROM fingerprint..." \
    "toggle_lineage_identity_cleanup:lineage_identity_cleanup:Hiding Lineage props..." \
    "toggle_nuke_lineage:nuke_lineage:Nuking Lineage props..." \
    "toggle_custom_rom_identity_cleanup:custom_rom_identity_cleanup:Cleaning custom ROM/GApps traces..." \
    "toggle_hide_rom_identifier:hide_rom_identifier:Removing custom ROM properties (24-ROM pattern)..." \
    "toggle_pif_traces:pif2:Cleaning PIF/PixelProps trace properties..." \
    "toggle_rom_builtin_spoof:rom_builtin_spoof:Enabling ROM built-in spoof hooks (zygiskless)..." \
    "toggle_suspicious_props:suspicious_props:" \
    "toggle_action_gms:gms:" \
    "toggle_action_target:target:" \
    "toggle_auto_target:auto_target:" \
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
    elif [ "$_sv_script" = "auto_target" ]; then
        # Exit 75 = incomplete, retry up to 5x
        sh "$MODDIR/features/auto_target.sh" boot 2>/dev/null
        if [ "$?" = "75" ]; then
            (
                _at_retry=0
                while [ "$_at_retry" -lt 5 ]; do
                    sleep 60
                    _at_retry=$((_at_retry + 1))
                    sh "$MODDIR/features/auto_target.sh" boot 2>/dev/null
                    [ "$?" = "75" ] || exit 0
                done
                log "SERVICE" "Auto Target: boot scan did not complete after 5 retries"
            ) &
        fi
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

# Auto Target on install: inotify + 60s poll backup
if _feature_enabled toggle_auto_target_immediate; then
    resolve_inotifyd
    if [ "$INOTIFYD_KIND" != "none" ] && [ -d "/data/app" ]; then
        chmod 755 "$MODDIR/features/auto_target_notify.sh" 2>/dev/null
        _at_watch="/data/app:nyd"
        # packages.xml is replaced by rename: watch the dir too
        [ -f "/data/system/packages.xml" ] && _at_watch="$_at_watch /data/system/packages.xml:w /data/system:y"
        # shellcheck disable=SC2086
        $INOTIFYD_CMD "$MODDIR/features/auto_target_notify.sh" $_at_watch >/dev/null 2>&1 &
        log "SERVICE" "Auto Target: real-time watch active ($INOTIFYD_KIND inotifyd: $_at_watch)"
        unset _at_watch
    else
        log "SERVICE" "Auto Target: inotify unavailable"
    fi
    (
        while true; do
            sleep 60
            _feature_enabled toggle_auto_target_immediate || continue
            sh "$MODDIR/features/auto_target.sh" poll 2>/dev/null
        done
    ) &
    log "SERVICE" "Auto Target: polling every 60s as backup"
fi

# OMK / TEESimulator watcher (exits at once if not detected)
( sh "$MODDIR/features/keystore_watch.sh" >/dev/null 2>&1 ) &

# Auto keybox update
( sh "$MODDIR/features/keybox_autoupdate.sh" >/dev/null 2>&1 ) &

# Re-apply boot props (ROM may reset them)
_feature_enabled toggle_boot_props && apply_boot_prop_list

# Re-apply after 120s (late services may overwrite)
(
    sleep 120
    log "SERVICE" "Delayed re-apply: reapplying critical props"
    _feature_enabled toggle_boot_props && apply_boot_prop_list
    # Shared by Boot Props and Boot Hardening
    if _feature_enabled toggle_boot_props || _feature_enabled toggle_boot_hardening; then
        apply_shared_boot_props
    fi
    _feature_enabled toggle_recovery && hide_recovery_folders
    log "SERVICE" "Delayed re-apply done"
    [ -f "$MODDIR/features/export_logs.sh" ] && sh "$MODDIR/features/export_logs.sh" >/dev/null 2>&1
) &

# Daily suspicious_props check
if _feature_enabled toggle_suspicious_props; then
    (
        while true; do
            sleep 86400
            sh "$MODDIR/features/suspicious_props.sh" >/dev/null 2>&1 || true
        done
    ) &
fi

if _feature_enabled toggle_kernel_buildtime; then
    log "SERVICE" "Syncing build time to kernel..."
    sh "$MODDIR/features/build_sanitize.sh" 2>/dev/null || true
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
