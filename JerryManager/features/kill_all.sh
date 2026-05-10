#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/package_list.sh"

log "KILL_ALL" "Start"

_count=0
ALL_PKGS="$DETECTOR_APPS $GMS_APPS"

for pkg in $ALL_PKGS; do
  if ! pm list packages | grep -Fq "package:$pkg"; then
    continue
  fi
  am force-stop "$pkg" >/dev/null 2>&1 || true
  pm clear "$pkg" >/dev/null 2>&1 || true
  _count=$((_count + 1))
done

log "KILL_ALL" "Cleared $_count packages"
log "KILL_ALL" "Finish"
exit 0
