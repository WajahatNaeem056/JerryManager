#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/config_env.sh"

_master=$(cfg_get toggle_adb_disabler 0)
if [ "$_master" = "0" ]; then
  exit 0
fi

log "ADB" "Start"

_dev_opt=$(cfg_get toggle_adb_disabler_dev_options 0)
_usb_dbg=$(cfg_get toggle_adb_disabler_usb_debug 0)
# NOTE: sys.oem_unlock_allowed / ro.oem_unlock_supported are no longer set
# here. They're a core root-hiding signal, not an ADB-lock cosmetic feature,
# so they're now applied unconditionally in apply_boot_hardening() (lib/common.sh)
# and re-enforced in the delayed re-apply blocks (service.sh, boot-completed.sh).
# This ensures they stay hidden even when the user disables ADB Lock entirely.

if [ "$_dev_opt" != "0" ]; then
  settings put global development_settings_enabled 0 2>/dev/null && log "ADB" "development_settings_enabled -> 0"
  resetprop -n persist.sys.development_settings_enabled 0 2>/dev/null && log "ADB" "persist.sys.development_settings_enabled -> 0"
fi

if [ "$_usb_dbg" != "0" ]; then
  resetprop -n ro.debuggable 0 2>/dev/null
  resetprop -n ro.force.debuggable 0 2>/dev/null
  resetprop -n ro.adb.secure 1 2>/dev/null
  resetprop -n persist.sys.usb.config mtp 2>/dev/null
  resetprop -n sys.usb.config mtp 2>/dev/null
  resetprop -n service.adb.root 0 2>/dev/null
  # Jerry was only resetting props, never actually marking the adbd daemon
  # itself as stopped, so a checker reading init.svc.adbd directly could
  # still see it "running".
  resetprop -n init.svc.adbd stopped 2>/dev/null && log "ADB" "init.svc.adbd -> stopped"
  resetprop -n init.svc_debug_pid.adbd "" 2>/dev/null && log "ADB" "init.svc_debug_pid.adbd -> ''"
  settings put global adb_enabled 0 2>/dev/null
  log "ADB" "USB debugging props reset"
fi

log "ADB" "Finish"
exit 0
