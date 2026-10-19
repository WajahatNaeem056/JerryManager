#!/system/bin/sh
# Called by inotifyd (see service.sh). Args: $1=event $2=watched path $3=file name (dir watch only)
MODDIR="${0%/*}"
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/toggle_seed.sh"

case "$2" in
  /data/app|/data/app/)
    # Install/uninstall in /data/app fires before PackageManager registers the app,
    # so scan twice: ~3s and ~8s after the event
    _stages="3 5"
    ;;
  *)
    # packages.xml / packages.list is rewritten once PackageManager has the app
    _n="${3:-${2##*/}}"
    case "$_n" in
      packages.xml|packages.list) _stages="2" ;;
      *) exit 0 ;;
    esac
    ;;
esac

_feature_enabled toggle_auto_target || exit 0

# Return to inotifyd at once; overlapping scans are coalesced by auto_target.sh's own lock
(
  for _s in $_stages; do
    sleep "$_s"
    sh "$MODDIR/auto_target.sh" >/dev/null 2>&1
  done
) >/dev/null 2>&1 &
exit 0
