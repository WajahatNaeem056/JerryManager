#!/system/bin/sh
# Syncs device identity (brand/device/product/manufacturer/model) into TEESimulator's config.json
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"

TSIM_CONFIG="$TEESIM_CONFIG"
PIF_DIR="/data/adb/modules/playintegrityfix"

[ -f "$TSIM_CONFIG" ] || exit 0

log "TEESIM" "Start"

_ts_pif_prop=""
for _ts_pif_candidate in \
    "$PIF_DIR/custom.pif.prop" \
    "$PIF_DIR/pif.prop" \
    "/data/adb/custom.pif.prop"
do
    if [ -f "$_ts_pif_candidate" ]; then
        _ts_pif_prop="$_ts_pif_candidate"
        break
    fi
done
unset _ts_pif_candidate

if [ -z "$_ts_pif_prop" ]; then
    log "TEESIM" "No PIF config found — nothing to sync"
    exit 0
fi

if ! grep -q '"default"' "$TSIM_CONFIG" 2>/dev/null; then
    log "TEESIM" "No 'default' profile found in config.json — skipping"
    exit 0
fi

_ts_get_pif() {
    grep -m1 -i "^$1=" "$_ts_pif_prop" 2>/dev/null | cut -d '=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

_ts_esc_json() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

_ts_brand=$(_ts_esc_json "$(_ts_get_pif "BRAND")")
_ts_device=$(_ts_esc_json "$(_ts_get_pif "DEVICE")")
_ts_product=$(_ts_esc_json "$(_ts_get_pif "PRODUCT")")
_ts_manufacturer=$(_ts_esc_json "$(_ts_get_pif "MANUFACTURER")")
_ts_model=$(_ts_esc_json "$(_ts_get_pif "MODEL")")

_ts_tmp="${TSIM_CONFIG}.tmp.$$"
cp "$TSIM_CONFIG" "$_ts_tmp" 2>/dev/null || { log "TEESIM" "Could not stage a working copy — aborting"; exit 0; }

_ts_set_str() {
    _tss_key="$1"
    _tss_val="$2"
    [ -z "$_tss_val" ] && return 0
    sed -i "s|\"$_tss_key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"$_tss_key\": \"$_tss_val\"|" "$_ts_tmp"
}

_ts_set_str "brand"        "$_ts_brand"
_ts_set_str "device"       "$_ts_device"
_ts_set_str "product"      "$_ts_product"
_ts_set_str "manufacturer" "$_ts_manufacturer"
_ts_set_str "model"        "$_ts_model"

# Brace count must balance before committing, or the config is left unchanged
_ts_open=$(tr -dc '{' < "$_ts_tmp" | wc -c)
_ts_close=$(tr -dc '}' < "$_ts_tmp" | wc -c)
if [ "$_ts_open" = "$_ts_close" ] && [ -s "$_ts_tmp" ]; then
    mv -f "$_ts_tmp" "$TSIM_CONFIG"
    log "TEESIM" "Synced device identity to TEESimulator config"
else
    log "TEESIM" "Sanity check failed (unbalanced braces) — config.json left unchanged"
    rm -f "$_ts_tmp"
fi

unset _ts_pif_prop _ts_brand _ts_device _ts_product _ts_manufacturer _ts_model _ts_tmp _ts_open _ts_close

log "TEESIM" "Finish"
exit 0
