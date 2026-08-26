#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/package_list.sh"

[ "$(cfg_get toggle_action_gms 1)" = "0" ] && exit 0

log "GMS" "Starting GMS management"

_installed_pkgs=$(pm list packages 2>/dev/null) || log "GMS" "Warning: Failed to list installed packages"
_count=0

for _pid in $(pgrep -f 'droidguard\|com\.google\.android\.gms\b' 2>/dev/null); do
  kill -9 "$_pid" 2>/dev/null || true
  _count=$((_count + 1))
done
unset _pid

if echo "$_installed_pkgs" | grep -q "package:com.android.vending"; then
  log "GMS" "Force-stopping Play Store (safe mode — account preserved)..."
  am force-stop com.android.vending >/dev/null 2>&1 || log "GMS" "Warning: Failed to force-stop Play Store"
  _count=$((_count + 1))

  log "GMS" "Clearing Play Store cache..."
  cmd package trim-caches 999999999 com.android.vending >/dev/null 2>&1 || log "GMS" "Warning: Failed to clear Play Store cache"
  log "GMS" "Play Store cache cleared"
fi
unset _installed_pkgs

log "GMS" "Force-stopped $_count package(s)"
exit 0
