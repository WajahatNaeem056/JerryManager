#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"

if [ "$(cfg_get "safemode" "0")" = "1" ]; then
    log_customrom "HIDE_ROM_IDENTIFIER" "Skipped — Safe Mode is on"
    exit 0
fi

ensure_dir "$JERRYMANAGER_DIR"

CROM_PATTERN="lineage|infinity|evolution|crdroid|arrow|mistos|axion|pixelos|rising|lunaris|halcyon|havoc|alphadroid|avium|bliss|calyx|derpfest|graphene|lmodroid|lumine|matrixx|superior|clover|yaap"

resetprop 2>/dev/null | grep -iE "$CROM_PATTERN" | while IFS= read -r _crp_line; do
    _crp_prop=${_crp_line#*[}
    _crp_prop=${_crp_prop%%]*}
    [ -z "$_crp_prop" ] && continue
    log_customrom "HIDE_ROM_IDENTIFIER" "DEL $_crp_prop"
    resetprop -d "$_crp_prop" 2>/dev/null
done

if resetprop ro.modversion 2>/dev/null | grep -q .; then
    log_customrom "HIDE_ROM_IDENTIFIER" "DEL ro.modversion"
    resetprop -d "ro.modversion" 2>/dev/null
fi

log_customrom "HIDE_ROM_IDENTIFIER" "Done"
exit 0
