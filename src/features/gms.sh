#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/package_list.sh"

[ "$(cfg_get toggle_action_gms 1)" = "0" ] && exit 0

_force_stop=$(cfg_get toggle_action_gms_force_stop 1)
_clear_data=$(cfg_get toggle_action_gms_clear_data 0)

[ "$_force_stop$_clear_data" = "00" ] && exit 0

log "GMS" "Starting GMS management"

_installed_pkgs=$(pm list packages 2>/dev/null) || log "GMS" "Warning: Failed to list installed packages"
_count=0

if [ "$_force_stop" != "0" ]; then
  # Two separate pgrep calls instead of one '\|' alternation pattern —
  # toybox pgrep's basic-regex support for '\|' is inconsistent across
  # builds, so a single alternation pattern can silently match nothing.
  for _pid in $(pgrep -f 'droidguard' 2>/dev/null) $(pgrep -f 'com\.google\.android\.gms\b' 2>/dev/null); do
    kill -9 "$_pid" 2>/dev/null || true
    _count=$((_count + 1))
  done
  unset _pid

  for _pkg in $GMS_APPS; do
    echo "$_installed_pkgs" | grep -Fq "package:$_pkg" || continue
    am force-stop "$_pkg" >/dev/null 2>&1 || { log "GMS" "Warning: Failed to force-stop $_pkg"; continue; }
    log "GMS" "Force-stopped $_pkg"
    _count=$((_count + 1))
  done
  unset _pkg

  if echo "$_installed_pkgs" | grep -q "package:com.android.vending"; then
    log "GMS" "Clearing Play Store cache..."
    cmd package trim-caches 999999999 com.android.vending >/dev/null 2>&1 || log "GMS" "Warning: Failed to clear Play Store cache"
    log "GMS" "Play Store cache cleared"
  fi
fi

if [ "$_clear_data" != "0" ] && echo "$_installed_pkgs" | grep -q "package:com.android.vending"; then
  log "GMS" "Clearing Play Store data (full wipe — account sign-in will be lost)..."
  pm clear com.android.vending >/dev/null 2>&1 || log "GMS" "Warning: Failed to clear Play Store data"
  log "GMS" "Play Store data cleared"
fi

unset _installed_pkgs

log "GMS" "Force-stopped $_count package(s)"
exit 0
