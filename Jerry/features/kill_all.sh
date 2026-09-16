#!/system/bin/sh
set -e
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/package_list.sh"

log "KILL_ALL" "Start"

_count=0
NON_GMS_PKGS="$DETECTOR_APPS $REMOTE_CONTROL_APPS $TOOL_APPS"
_installed_pkgs=$(pm list packages 2>/dev/null) || log "KILL_ALL" "Warning: Failed to list installed packages"

for pkg in $NON_GMS_PKGS; do
  echo "$_installed_pkgs" | grep -Fq "package:$pkg" || continue
  am force-stop "$pkg" >/dev/null 2>&1 || log "KILL_ALL" "Warning: Failed to force-stop $pkg"
  pm clear "$pkg" >/dev/null 2>&1 || log "KILL_ALL" "Warning: Failed to clear $pkg"
  _count=$((_count + 1))
done

for pkg in $GMS_APPS; do
  echo "$_installed_pkgs" | grep -Fq "package:$pkg" || continue
  am force-stop "$pkg" >/dev/null 2>&1 || log "KILL_ALL" "Warning: Failed to force-stop $pkg"
  cmd package trim-caches 999999999 "$pkg" >/dev/null 2>&1 || true
  rm -rf "/data/data/$pkg/app_dg_cache"   2>/dev/null || true
  rm -rf "/data/data/$pkg/app_droidguard" 2>/dev/null || true
  rm -rf "/data/data/$pkg/cache/dg_cache" 2>/dev/null || true
  rm -rf "/data/data/$pkg/cache/integrity" 2>/dev/null || true
  _count=$((_count + 1))
done
unset _installed_pkgs

log "KILL_ALL" "Cleared $_count packages (GMS: cache only, accounts preserved)"
log "KILL_ALL" "Finish"
exit 0
