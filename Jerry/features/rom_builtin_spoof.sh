#!/system/bin/sh
# Zygiskless mode: let the ROM's own GMS / Play Store spoofing hooks run
# (PIHooks / KIHooks / PixelProps) instead of blocking them.
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"

[ "$(cfg_get toggle_rom_builtin_spoof 0)" = "0" ] && exit 0

if [ "$(cfg_get "safemode" "0")" = "1" ]; then
    log "ROM_BUILTIN" "Skipped — Safe Mode is on"
    exit 0
fi

log "ROM_BUILTIN" "Start"

# Only touch ROMs that actually ship these hooks
_rb_has_hooks=false
resetprop 2>/dev/null | grep -qE 'persist\.sys\.(pihooks|kihooks|entryhooks|pixelprops)' && _rb_has_hooks=true
if [ "$_rb_has_hooks" = "false" ]; then
    log "ROM_BUILTIN" "No ROM spoof hooks present on this ROM — nothing to enable"
    log "ROM_BUILTIN" "Finish"
    exit 0
fi

if [ "$(cfg_get toggle_rom_builtin_gms 1)" != "0" ]; then
    while IFS='|' read -r _rb_prop _rb_val; do
        [ -z "$_rb_prop" ] && continue
        sp_persist "$_rb_prop" "$_rb_val"
    done <<MAP
persist.sys.pihooks.disable.gms_key_attestation_block|false
persist.sys.pihooks.disable.gms_props|false
persist.sys.pihooks.enabled_features|1
persist.sys.pihooks.disable|0
persist.sys.kihooks.disable|0
MAP
    log "ROM_BUILTIN" "ROM GMS hooks enabled"
fi

if [ "$(cfg_get toggle_rom_builtin_vending 1)" != "0" ]; then
    sp_persist persist.sys.pixelprops.vending true
    log "ROM_BUILTIN" "ROM Play Store (vending) spoof enabled"
fi

unset _rb_has_hooks _rb_prop _rb_val
log "ROM_BUILTIN" "Finish"
exit 0
