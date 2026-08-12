#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"

HIDE_CROM_LOG="$JERRYKEY_DIR/hide_custom_rom.log"

if [ "$(cfg_get "safemode" "0")" = "1" ]; then
    log "HIDE_CUSTOM_ROM" "Skipped — Safe Mode is on"
    exit 0
fi

ensure_dir "$JERRYKEY_DIR"

_hcr_log() {
    _msg="$(date '+%F %T') | $1"
    echo "$_msg" >> "$HIDE_CROM_LOG"
}

_hcr_log " ••••• Cleanup started •••••"

_hcr_dl_dir="/sdcard/Download"
if [ -d "$_hcr_dl_dir" ]; then
    _hcr_log "Scanning $_hcr_dl_dir for install/action logs..."
    find "$_hcr_dl_dir" -maxdepth 1 -type f \( \
        -name "*_install_log_2026*" -o \
        -name "*_action_log_2025*" -o \
        -name "*_action_log_2026*" \
    \) 2>/dev/null | while IFS= read -r _hcr_f; do
        _hcr_log "Deleted: $_hcr_f"
        rm -f "$_hcr_f"
    done
else
    _hcr_log "Directory $_hcr_dl_dir not found, skipping..."
fi

_HCR_TARGETS="
/sdcard/Android/litegapps/litegapps_controller.log|file
/tmp/NikGapps|dir
/tmp/NikGapps/logfiles|dir
/tmp/NikGapps/addonscripts|dir
/tmp/NikGapps/logfiles/package_log|dir
/sdcard/NikGapps|dir
/tmp/recovery.log|file
/tmp/NikGapps.log|file
/tmp/Mount.log|file
/tmp/installation_size.log|file
/tmp/busybox.log|file
/tmp/Logs-*.tar.gz|file
/tmp/bitgapps_debug_logs_*.tar.gz|file
/sdcard/bitgapps_debug_logs_*.tar.gz|file
/system/etc/bitgapps_debug_logs_*.tar.gz|file
/sdcard/Download/*_install_log_2026*|file
/sdcard/Download/*_action_log_2026*|file
"

echo "$_HCR_TARGETS" | while IFS= read -r _hcr_line; do
    [ -z "$_hcr_line" ] && continue

    _hcr_path="${_hcr_line%|*}"
    _hcr_type="${_hcr_line#*|}"
    [ -z "$_hcr_path" ] && continue

    if echo "$_hcr_path" | grep -q '\*'; then
        _hcr_dir="${_hcr_path%/*}"
        _hcr_pattern="${_hcr_path##*/}"
        [ -d "$_hcr_dir" ] || continue
        find "$_hcr_dir" -maxdepth 1 -type f -name "$_hcr_pattern" 2>/dev/null | while IFS= read -r _hcr_match; do
            _hcr_log "Deleting file: $_hcr_match"
            rm -f "$_hcr_match"
        done
    else
        if [ "$_hcr_type" = "file" ] && [ -f "$_hcr_path" ]; then
            _hcr_log "Deleting file: $_hcr_path"
            rm -f "$_hcr_path"
        elif [ "$_hcr_type" = "dir" ] && [ -d "$_hcr_path" ]; then
            _hcr_log "Deleting directory: $_hcr_path"
            rm -rf "$_hcr_path"
        fi
    fi
done

_hcr_log " ••••• Cleanup complete •••••"
log "HIDE_CUSTOM_ROM" "Done — see hide_custom_rom.log for details"
exit 0
