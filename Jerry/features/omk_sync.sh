#!/system/bin/sh
# OhMyKeymint advanced sync:
#  - device identity (+ security patch) from PIF config -> config.toml
#  - merge target.txt packages into injector.toml scoop
#  - make sure interceptor / filter flags exist in injector.toml (existing values kept)
# Runs automatically whenever OhMyKeymint is the active keystore backend (no toggles).
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/keystore.sh"
. "$MODDIR/../lib/toggle_seed.sh"
. "$MODDIR/../lib/package_list.sh"

resolve_keystore_backend
if [ "$KEYSTORE_BACKEND" != "omk" ]; then
    log "OMK_SYNC" "OhMyKeymint is not the active backend — skipped"
    exit 0
fi
[ -d "$OMK_DIR" ] || { log "OMK_SYNC" "OMK data dir missing — skipped"; exit 0; }

log "OMK_SYNC" "Start"
_os_cfg_before=$(cksum "$OMK_CONFIG" 2>/dev/null)
_os_inj_before=$(cksum "$OMK_INJECTOR" 2>/dev/null)

# ---- 1) PIF identity -> config.toml ----
if [ -f "$OMK_CONFIG" ]; then
    _os_pif=""
    for _os_c in /data/adb/pif.prop /data/adb/custom.pif.prop "$MODDIR/../pif.prop"; do
        [ -f "$_os_c" ] && { _os_pif="$_os_c"; break; }
    done
    if [ -z "$_os_pif" ]; then
        log "OMK_SYNC" "No PIF config found — identity sync skipped"
    else
        _os_get() { grep -m1 -i "^$1=" "$_os_pif" 2>/dev/null | cut -d= -f2- | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }
        _os_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
        _os_brand=$(_os_get BRAND);  _os_device=$(_os_get DEVICE);  _os_product=$(_os_get PRODUCT)
        _os_manuf=$(_os_get MANUFACTURER); _os_model=$(_os_get MODEL); _os_patch=$(_os_get SECURITY_PATCH)
        # Jerry's pif.prop is fingerprint-based: derive brand/product/device from it
        _os_fp=$(_os_get FINGERPRINT)
        if [ -n "$_os_fp" ]; then
            _os_fpa="${_os_fp%%:*}"
            [ -z "$_os_brand" ]   && _os_brand=$(printf '%s' "$_os_fpa" | cut -d/ -f1)
            [ -z "$_os_product" ] && _os_product=$(printf '%s' "$_os_fpa" | cut -d/ -f2)
            [ -z "$_os_device" ]  && _os_device=$(printf '%s' "$_os_fpa" | cut -d/ -f3)
        fi
        _os_n=0
        for _os_pair in "brand:$_os_brand" "device:$_os_device" "product:$_os_product" \
                        "manufacturer:$_os_manuf" "model:$_os_model"; do
            _os_k="${_os_pair%%:*}"; _os_v="${_os_pair#*:}"
            [ -z "$_os_v" ] && continue
            omk_toml_set "$OMK_CONFIG" device "$_os_k" "\"$(_os_esc "$_os_v")\"" && _os_n=$((_os_n + 1))
        done
        # Security Patch feature owns this value when it is on
        if [ -n "$_os_patch" ]; then
            if _feature_enabled toggle_action_security_patch 2>/dev/null; then
                log "OMK_SYNC" "Security patch left to the Security Patch feature"
            else
                omk_toml_set "$OMK_CONFIG" trust security_patch "\"$_os_patch\"" && _os_n=$((_os_n + 1))
            fi
        fi
        log "OMK_SYNC" "Synced $_os_n identity field(s) from $(basename "$_os_pif")"
    fi
fi

# ---- 2) target.txt -> injector scoop (merge, never removes) ----
if [ -f "$OMK_INJECTOR" ] && [ -f "$TARGET_TXT" ]; then
    if omk_has_toplevel_scoop "$OMK_INJECTOR"; then
        _os_added=0
        _os_bl=0
        auto_target_blacklist_active && _os_bl=1
        while IFS= read -r _os_line || [ -n "$_os_line" ]; do
            _os_pkg=$(printf '%s' "$_os_line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[!?]$//')
            case "$_os_pkg" in ''|\#*) continue ;; esac
            [ "$_os_bl" = "1" ] && is_auto_target_blacklisted "$_os_pkg" && continue
            grep -q "\"$_os_pkg\"" "$OMK_INJECTOR" 2>/dev/null && continue
            omk_scoop_add "$OMK_INJECTOR" "$_os_pkg" && _os_added=$((_os_added + 1))
        done < "$TARGET_TXT"
        log "OMK_SYNC" "Scoop: added $_os_added package(s) from target.txt"
        if [ "$_os_bl" = "1" ]; then
            _os_rm=0
            while IFS= read -r _os_b; do
                [ -z "$_os_b" ] && continue
                case " $(echo $FIXED_TARGETS) " in *" $_os_b "*) continue ;; esac
                grep -q "\"$_os_b\"" "$OMK_INJECTOR" 2>/dev/null || continue
                omk_scoop_remove "$OMK_INJECTOR" "$_os_b" && _os_rm=$((_os_rm + 1))
            done <<EOF2
$(tr -d '\r' < "$AUTO_TARGET_BLACKLIST_FILE" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -vE '^(#|$)')
EOF2
            [ "$_os_rm" -gt 0 ] && log "OMK_SYNC" "Scoop: removed $_os_rm blacklisted package(s)"
        fi
    else
        log "OMK_SYNC" "injector.toml has no top-level scoop array — target merge skipped"
    fi
fi

# ---- 3) Interceptor / filter flags: add what is missing, never override ----
if [ -f "$OMK_INJECTOR" ]; then
    for _os_f in get_security_level get_key_entry update_subcomponent list_entries delete_key \
                 grant ungrant get_number_of_entries list_entries_batched get_supplementary_attestation_info; do
        omk_toml_set "$OMK_INJECTOR" intercept "$_os_f" true keep
    done
    omk_toml_set "$OMK_INJECTOR" filter block_android_package true keep
    omk_toml_set "$OMK_INJECTOR" filter allow_unknown_package false keep
fi

[ "$(cksum "$OMK_CONFIG" 2>/dev/null)" != "$_os_cfg_before" ] && { keystore_reload_keymint; log "OMK_SYNC" "config.toml changed — keymint reload requested"; }
[ "$(cksum "$OMK_INJECTOR" 2>/dev/null)" != "$_os_inj_before" ] && { keystore_reload_injector; log "OMK_SYNC" "injector.toml changed — injector reload requested"; }

log "OMK_SYNC" "Finish"
exit 0
