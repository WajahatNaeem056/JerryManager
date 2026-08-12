#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"

REMOVE_CROM_LOG="$JERRYKEY_DIR/remove_custom_rom_props.log"

if [ "$(cfg_get "safemode" "0")" = "1" ]; then
    log "REMOVE_CROM_PROPS" "Skipped — Safe Mode is on"
    exit 0
fi

ensure_dir "$JERRYKEY_DIR"

CROM_PATTERN="lineage|infinity|evolution|crdroid|arrow|mistos|axion|pixelos|rising|lunaris|halcyon|havoc|alphadroid|avium|bliss|calyx|derpfest|graphene|lmodroid|lumine|matrixx|superior|clover|yaap"

resetprop 2>/dev/null | grep -iE "$CROM_PATTERN" | while IFS= read -r _crp_line; do
    _crp_prop=${_crp_line#*[}
    _crp_prop=${_crp_prop%%]*}
    [ -z "$_crp_prop" ] && continue
    echo "$(date '+%F %T') DEL $_crp_prop" >> "$REMOVE_CROM_LOG"
    resetprop -d "$_crp_prop" 2>/dev/null
done

if resetprop ro.modversion 2>/dev/null | grep -q .; then
    echo "$(date '+%F %T') DEL ro.modversion" >> "$REMOVE_CROM_LOG"
    resetprop -d "ro.modversion" 2>/dev/null
fi

log "REMOVE_CROM_PROPS" "Done — see remove_custom_rom_props.log for details"
exit 0
