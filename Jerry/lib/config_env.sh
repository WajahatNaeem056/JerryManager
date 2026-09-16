#!/system/bin/sh
cfg_get() {
    _cg_key="$1" _cg_default="$2"
    _cg_val=$(cat "$JERRYMANAGER_CONFIG_DIR/$_cg_key.val" 2>/dev/null || true)
    printf '%s' "${_cg_val:-$_cg_default}"
    unset _cg_key _cg_default _cg_val
}

cfg_set() {
    mkdir -p "$JERRYMANAGER_CONFIG_DIR" 2>/dev/null
    printf '%s' "$2" > "$JERRYMANAGER_CONFIG_DIR/$1.val"
}

cfg_delete() {
    rm -f "$JERRYMANAGER_CONFIG_DIR/$1.val" 2>/dev/null
}

# Config-key migration: rename an old toggle/setting key to a new one,
# preserving whatever value the user already had. Safe to call every boot —
# it's a no-op once the old file is gone. Add "old_key:new_key" pairs to
# migrate_config_keys() below whenever a key is renamed in an update, so
# existing users don't lose their saved setting.
_cfg_migrate_pair() {
    _cmp_old="$1" _cmp_new="$2"
    _cmp_old_file="$JERRYMANAGER_CONFIG_DIR/$_cmp_old.val"
    _cmp_new_file="$JERRYMANAGER_CONFIG_DIR/$_cmp_new.val"
    if [ -f "$_cmp_old_file" ] && [ ! -f "$_cmp_new_file" ]; then
        mv "$_cmp_old_file" "$_cmp_new_file" 2>/dev/null
        log "SERVICE" "Migrated config key: $_cmp_old -> $_cmp_new"
    fi
    unset _cmp_old _cmp_new _cmp_old_file _cmp_new_file
}

migrate_config_keys() {
    [ -d "$JERRYMANAGER_CONFIG_DIR" ] || return 0
    # Add "old_key:new_key" pairs here as toggles/settings get renamed:
    for _mck_pair in \
        _placeholder_none:_placeholder_none
    do
        _mck_old="${_mck_pair%%:*}"
        _mck_new="${_mck_pair#*:}"
        [ "$_mck_old" = "_placeholder_none" ] && continue
        _cfg_migrate_pair "$_mck_old" "$_mck_new"
    done
    unset _mck_pair _mck_old _mck_new
}

update_description() {
    _ud_prop="$MODDIR/module.prop"
    [ -f "$_ud_prop" ] || return 0

    if [ -z "$KEYSTORE_BACKEND" ] && [ -f "$MODDIR/lib/keystore.sh" ]; then
        . "$MODDIR/lib/keystore.sh"
        resolve_keystore_backend
    fi

    _ud_targets=0
    if [ "$KEYSTORE_BACKEND" = "omk" ]; then
        [ -f "$OMK_INJECTOR" ] && _ud_targets=$(awk '/^scoop = \[/{f=1;next} f && /\]/{f=0;next} f{gsub(/[",]/,"");gsub(/^[ \t]+|[ \t]+$/,"");if(length($0))c++} END{print c+0}' "$OMK_INJECTOR" 2>/dev/null)
    else
        [ -f "$TARGET_TXT" ] && _ud_targets=$(grep -c '.' "$TARGET_TXT" 2>/dev/null | tr -d ' ')
    fi
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

    if [ ! -f "$_ud_prop.bak" ]; then
        cp "$_ud_prop" "$_ud_prop.bak" 2>/dev/null
    fi
    sed -i '/^description=/d' "$_ud_prop"
    if [ -s "$_ud_prop" ] && [ "$(tail -c1 "$_ud_prop")" != "" ]; then
        echo >> "$_ud_prop"
    fi
    echo "description=$_ud_desc" >> "$_ud_prop"

    log "DESC" "Updated: $_ud_desc"
    unset _ud_prop _ud_targets _ud_valid _ud_valid_raw _ud_pif _ud_desc
}
