#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/package_list.sh"

# Single toggle controls both force-stop and cache-clear together — matches
# the single "Kill Play Store" switch exposed in the WebUI (toggle_action_gms).
[ "$(cfg_get toggle_action_gms 1)" = "0" ] && exit 0

log "GMS" "Starting GMS management"

_installed_pkgs=$(pm list packages 2>/dev/null) || log "GMS" "Warning: Failed to list installed packages"
_count=0

# Kill any live DroidGuard / GMS core process directly by PID first —
# catches processes that survive a plain am force-stop.
for _pid in $(pgrep -f 'droidguard\|com\.google\.android\.gms\b' 2>/dev/null); do
  kill -9 "$_pid" 2>/dev/null || true
  _count=$((_count + 1))
done
unset _pid

# GMS_KILL_LIST (lib/package_list.sh) extends GMS_APPS with the
# persistent/unstable GMS processes, RKPD attestation daemon, Chrome, and
# the Google app — covers the broader GMS ecosystem instead of Play Store only.
for _pkg in $GMS_KILL_LIST; do
  echo "$_installed_pkgs" | grep -Fq "package:$_pkg" || continue
  am force-stop "$_pkg" >/dev/null 2>&1 || true
  log "GMS" "Force-stopped $_pkg"
  _count=$((_count + 1))
done

if echo "$_installed_pkgs" | grep -q "package:com.android.vending"; then
  log "GMS" "Clearing Play Store cache..."
  cmd package trim-caches 999999999 com.android.vending >/dev/null 2>&1 || log "GMS" "Warning: Failed to clear Play Store cache"
  log "GMS" "Play Store cache cleared"
fi
unset _installed_pkgs

log "GMS" "Force-stopped $_count package(s)"
exit 0
