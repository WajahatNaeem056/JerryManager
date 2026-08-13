#!/system/bin/sh
cfg_get() {
    _cg_key="$1" _cg_default="$2"
    _cg_val=$(cat "$JERRYKEY_CONFIG_DIR/$_cg_key.val" 2>/dev/null || true)
    printf '%s' "${_cg_val:-$_cg_default}"
    unset _cg_key _cg_default _cg_val
}

cfg_set() {
    mkdir -p "$JERRYKEY_CONFIG_DIR" 2>/dev/null
    printf '%s' "$2" > "$JERRYKEY_CONFIG_DIR/$1.val"
}

cfg_delete() {
    rm -f "$JERRYKEY_CONFIG_DIR/$1.val" 2>/dev/null
}

# ── Description updater — runs on Action-button press ─────────────────────────
# "Keybox: Valid   Pif: Yes   Targets: N" — JerryManager's own,
# no device model, no other module named.
update_description() {
    _ud_prop="$MODDIR/module.prop"
    [ -f "$_ud_prop" ] || return 0

    _ud_targets=0
    [ -f "$TARGET_TXT" ] && _ud_targets=$(grep -c '.' "$TARGET_TXT" 2>/dev/null | tr -d ' ')
    [ -z "$_ud_targets" ] && _ud_targets=0

    _ud_valid_raw=$(cfg_get keybox_valid "Unknown")
    case "$_ud_valid_raw" in
        Yes) _ud_valid="Valid" ;;
        No)  _ud_valid="Revoked" ;;
        *)   _ud_valid="Unknown" ;;
    esac

    _ud_pif="Not Installed"
    _ud_pif_dir="/data/adb/modules/playintegrityfix"
    if [ -d "$_ud_pif_dir" ]; then
        _ud_pif="Unknown"
        for _ud_pif_cfg in "$_ud_pif_dir/custom.pif.prop" "$_ud_pif_dir/pif.json" "$_ud_pif_dir/pif.prop"; do
            if [ -f "$_ud_pif_cfg" ]; then
                _ud_pif_model=$(grep -m1 '^MODEL=' "$_ud_pif_cfg" 2>/dev/null | cut -d= -f2-)
                [ -z "$_ud_pif_model" ] && _ud_pif_model=$(grep -m1 '"MODEL"' "$_ud_pif_cfg" 2>/dev/null | sed -n 's/.*"MODEL"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
                if [ -n "$_ud_pif_model" ]; then
                    _ud_pif="$_ud_pif_model"
                    break
                fi
            fi
        done
        unset _ud_pif_cfg _ud_pif_model
    fi
    unset _ud_pif_dir

    _ud_desc="Keybox: $_ud_valid  Pif: $_ud_pif  Targets: $_ud_targets"

    [ ! -f "$_ud_prop.bak" ] && cp "$_ud_prop" "$_ud_prop.bak" 2>/dev/null
    sed -i '/^description=/d' "$_ud_prop"
    # Guarantee a trailing newline before appending — otherwise, if the last
    # remaining line (e.g. updateJson=...) has no trailing \n, `echo >>`
    # concatenates straight onto it (updateJson=...description=... on one
    # line), which the manager app can't parse and the description silently
    # never shows.
    [ -s "$_ud_prop" ] && [ "$(tail -c1 "$_ud_prop")" != "" ] && echo >> "$_ud_prop"
    echo "description=$_ud_desc" >> "$_ud_prop"

    log "DESC" "Updated: $_ud_desc"
    unset _ud_prop _ud_targets _ud_valid _ud_valid_raw _ud_pif _ud_desc
}
