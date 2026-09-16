#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/keystore.sh"

TSIM_DIR="/data/adb/teesim"
TSIM_CONFIG="$TSIM_DIR/config.json"
PIF_DIR="/data/adb/modules/playintegrityfix"

[ -f "$TSIM_CONFIG" ] || exit 0

log "TEESIM" "Start"

_ts_pif_prop=""
for _ts_pif_candidate in \
    "$PIF_DIR/custom.pif.prop" \
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

resolve_keystore_backend

if [ -f "$TARGET_TXT" ]; then
    _ts_source_targets="$TARGET_TXT"
    _ts_source_format="flat"
elif [ -f "$OMK_INJECTOR" ]; then
    _ts_source_targets="$OMK_INJECTOR"
    _ts_source_format="toml"
else
    log "TEESIM" "No target list found from either backend — nothing to sync"
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

_ts_patch=""
[ -f "$SECURITY_PATCH_FILE" ] && _ts_patch=$(head -n1 "$SECURITY_PATCH_FILE" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

case "$_ts_patch" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) _ts_patch_ym=$(printf '%s' "$_ts_patch" | cut -d'-' -f1-2) ;;
    *) _ts_patch="" ; _ts_patch_ym="" ;;
esac

if ! grep -q '"default"' "$TSIM_CONFIG" 2>/dev/null; then
    log "TEESIM" "No 'default' profile found in config.json — skipping"
    exit 0
fi

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

if [ -n "$_ts_patch" ]; then
    sed -i "s|\"patchLevel\"[[:space:]]*:[[:space:]]*{[^}]*}|\"patchLevel\": { \"system\": \"$_ts_patch_ym\", \"vendor\": \"$_ts_patch\", \"boot\": \"$_ts_patch\" }|" "$_ts_tmp"
fi

_ts_apps_start=$(grep -n '"apps"' "$_ts_tmp" | head -n1 | cut -d: -f1)
if [ -n "$_ts_apps_start" ]; then
    _ts_apps_end_rel=$(tail -n +"$_ts_apps_start" "$_ts_tmp" | grep -n '\]' | head -n1 | cut -d: -f1)
    if [ -n "$_ts_apps_end_rel" ]; then
        _ts_apps_end=$((_ts_apps_start + _ts_apps_end_rel - 1))

        if [ "$_ts_source_format" = "toml" ]; then
            _ts_target_list=$(awk '/^scoop = \[/{f=1;next} f && /\]/{f=0;next} f{gsub(/[",]/,"");gsub(/^[ \t]+|[ \t]+$/,"");if(length($0))print}' "$_ts_source_targets" 2>/dev/null)
        else
            _ts_target_list=$(cat "$_ts_source_targets" 2>/dev/null)
        fi

        _ts_apps_body="$MODDIR/.teesim_apps_$$"
        : > "$_ts_apps_body"
        _ts_first=1
        printf '%s\n' "$_ts_target_list" | while IFS= read -r _ts_line; do
            _ts_pkg=$(printf '%s' "$_ts_line" | tr -d '\r' | sed 's/[!?]$//')
            [ -z "$_ts_pkg" ] && continue
            _ts_pkg=$(_ts_esc_json "$_ts_pkg")
            if [ "$_ts_first" = "1" ]; then
                printf '        "%s"' "$_ts_pkg" >> "$_ts_apps_body"
                _ts_first=0
            else
                printf ',\n        "%s"' "$_ts_pkg" >> "$_ts_apps_body"
            fi
        done
        printf '\n' >> "$_ts_apps_body"

        if [ -s "$_ts_apps_body" ] && [ -n "$(tr -d '[:space:]' < "$_ts_apps_body")" ]; then
            _ts_rebuilt="$MODDIR/.teesim_rebuilt_$$"
            head -n "$_ts_apps_start" "$_ts_tmp" > "$_ts_rebuilt"
            cat "$_ts_apps_body" >> "$_ts_rebuilt"
            tail -n +"$_ts_apps_end" "$_ts_tmp" >> "$_ts_rebuilt"
            mv -f "$_ts_rebuilt" "$_ts_tmp"
        fi
        rm -f "$_ts_apps_body"
        unset _ts_target_list _ts_apps_body _ts_first _ts_rebuilt
    fi
    unset _ts_apps_end_rel _ts_apps_end
fi
unset _ts_apps_start

# Sanity check before committing: brace count must balance, or the file is
# corrupt and must not overwrite the real config.
_ts_open=$(tr -dc '{' < "$_ts_tmp" | wc -c)
_ts_close=$(tr -dc '}' < "$_ts_tmp" | wc -c)
if [ "$_ts_open" = "$_ts_close" ] && [ -s "$_ts_tmp" ]; then
    mv -f "$_ts_tmp" "$TSIM_CONFIG"
    log "TEESIM" "Synced device identity, patch date, and target list to TEESimulator config"
else
    log "TEESIM" "Sanity check failed (unbalanced braces) — config.json left unchanged"
    rm -f "$_ts_tmp"
fi

unset _ts_pif_prop _ts_brand _ts_device _ts_product _ts_manufacturer _ts_model \
      _ts_patch _ts_patch_ym _ts_tmp _ts_open _ts_close \
      _ts_source_targets _ts_source_format

log "TEESIM" "Finish"
exit 0
