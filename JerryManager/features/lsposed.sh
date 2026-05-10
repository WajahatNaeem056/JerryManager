#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/config_env.sh"
[ "$(cfg_get toggle_lsposed 1)" = "0" ] && exit 0

log "LSPOSED" "Start"

_count=0
_failed=0

for _f in $(find /data/app -type f -name base.odex 2>/dev/null); do
  rm -f "$_f" 2>/dev/null && _count=$((_count + 1)) || _failed=$((_failed + 1))
done

if [ "$_count" -gt 0 ]; then
  log "LSPOSED" "Deleted $_count base.odex files"
fi
if [ "$_failed" -gt 0 ]; then
  log "LSPOSED" "Warning: Failed to delete $_failed base.odex files"
fi
if [ "$_count" -eq 0 ] && [ "$_failed" -eq 0 ]; then
  log "LSPOSED" "No base.odex files found"
fi

unset _f _count _failed
log "LSPOSED" "Finish"
exit 0
