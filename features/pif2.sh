#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"

log "PIF2" "Start"

_count=0
while IFS= read -r prop; do
  [ -z "$prop" ] && continue
  if resetprop -p -d "$prop" 2>/dev/null; then
    _count=$((_count + 1))
  else
    log "PIF2" "Warning: Failed to delete prop $prop"
  fi
done <<EOF
$(getprop | grep -E "pihook|pixelprops" | sed -E "s/^\[(.*)\]:.*/\1/")
EOF

log "PIF2" "Cleaned $_count props"
log "PIF2" "Finish"
exit 0