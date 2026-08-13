
seed_toggle_defaults() {
  for _std_pair in \
    toggle_boot_hardening:1 \
    toggle_recovery:1 \
    toggle_rom_spoof:1 \
    toggle_bootloader_spoofer:1 \
    toggle_adb_disabler:0 \
    toggle_rom_fingerprint:1 \
    toggle_suspicious_props:1 \
    toggle_lsposed:1 \
    toggle_action_gms:1 \
    toggle_action_target:1 \
    toggle_auto_target:1 \
    toggle_action_security_patch:1 \
    toggle_action_boot_hash:1 \
    toggle_action_pif:1 \
    toggle_hide_lineage:1 \
    toggle_nuke_lineage:0 \
    toggle_hide_custom_rom:1 \
    toggle_remove_custom_rom_props:1 \
  ; do
    _std_key="${_std_pair%%:*}"
    _std_default="${_std_pair#*:}"
    [ -f "$JERRYKEY_CONFIG_DIR/$_std_key.val" ] || cfg_set "$_std_key" "$_std_default"
  done
  unset _std_pair _std_key _std_default
}
