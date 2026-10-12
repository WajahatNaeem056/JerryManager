#!/system/bin/sh
set -e
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/package_list.sh"
. "$MODDIR/../lib/config_env.sh"
[ "$(cfg_get toggle_suspicious_props 1)" = "0" ] && exit 0

log "SUSPICIOUS" "Start"

_found_count=0
_critical_count=0

_old_ifs="$IFS"; IFS="$(printf '\n')"
for _entry in $SUSPICIOUS_PROPS; do
  _prop=$(echo "$_entry" | cut -d'|' -f1)
  _severity=$(echo "$_entry" | cut -d'|' -f2)
  _value=$(resetprop "$_prop" 2>/dev/null || echo "")

  if [ -n "$_value" ]; then
    _found_count=$((_found_count + 1))
    [ "$_severity" = "critical" ] && _critical_count=$((_critical_count + 1))
    case "$_severity" in
      critical) echo "[CRITICAL] $_prop = $_value" ;;
      warning)  echo "[WARNING] $_prop = $_value" ;;
      *)        echo "[INFO] $_prop = $_value" ;;
    esac
    hexpatch_deleteprop "$_prop"
  fi
done
IFS="$_old_ifs"; unset _old_ifs

if [ "$_found_count" -eq 0 ]; then
  log "SUSPICIOUS" "No suspicious properties found"
else
  log "SUSPICIOUS" "Found $_found_count suspicious props ($_critical_count critical)"
fi

unset _prop _severity _value _found_count _critical_count _entry
log "SUSPICIOUS" "Finish"
[ "$_found_count" -gt 0 ] && exit 1 || exit 0
