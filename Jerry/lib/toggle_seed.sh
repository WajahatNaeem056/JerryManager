#!/system/bin/sh
# Toggle default seeding — single source of truth for every toggle's default.
#
# WHY THIS EXISTS:
# cfg_get() (lib/config_env.sh) returns a fallback default when a .val file
# is missing, but NEVER writes that default to disk. That means any toggle
# the user has never manually flipped in the WebUI has correct in-memory
# *behavior* but no .val file — so the config folder looks sparse even when
# every feature is functionally "on". This is what was seen in
# /data/adb/JerryManager/config/: only a handful of .val files despite the
# WebUI reporting toggles as fully "On".
#
# A prior fix attempt (seen in boot-completed.sh's removed self-heal block)
# tried to solve this by pre-writing a single hardcoded value for every
# toggle — but that ignored the fact that some toggles have a non-standard
# default (e.g. toggle_kill_play_store defaults to "0"), so it silently
# forced them to the wrong state. That block was correctly removed.
#
# This version fixes it properly: each toggle carries its OWN default.
# Only writes a .val file if one doesn't already exist, so it never
# overwrites a user's real choice —
# it only fills in the gap for toggles that were never touched.
#
# Usage: call seed_toggle_defaults after sourcing lib/config_env.sh and
# lib/paths.sh, before any _feature_enabled() checks run.

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
