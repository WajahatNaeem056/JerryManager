cfg_get() {
    _cg_key="$1" _cg_default="$2"
    _cg_val=$(ksud module config get "$_cg_key" 2>/dev/null) || \
        _cg_val=$(cat "$JERRYKEY_CONFIG_DIR/$_cg_key.val" 2>/dev/null)
    printf '%s' "${_cg_val:-$_cg_default}"
    unset _cg_key _cg_default _cg_val
}

cfg_set() {
    _cs_key="$1" _cs_val="$2"
    ksud module config set "$_cs_key" "$_cs_val" 2>/dev/null || {
        mkdir -p "$JERRYKEY_CONFIG_DIR" 2>/dev/null
        printf '%s' "$_cs_val" > "$JERRYKEY_CONFIG_DIR/$_cs_key.val"
    }
    unset _cs_key _cs_val
}

cfg_delete() {
    _cd_key="$1"
    ksud module config delete "$_cd_key" 2>/dev/null || {
        rm -f "$JERRYKEY_CONFIG_DIR/$_cd_key.val" 2>/dev/null
    }
    unset _cd_key
}
