#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/keystore.sh"

log "SECURITY_PATCH" "Start"

resolve_keystore_backend
keystore_ready || die "No active keystore backend found"

current_year=$(date +%Y) || die "Failed to get year"
current_month=$(date +%m | sed 's/^0*//') || die "Failed to get month"
current_day=$(date +%d | sed 's/^0*//') || die "Failed to get day"

# Guard against a broken/unset device clock before it reaches a patch date
if [ "$current_year" -lt 2015 ] || [ "$current_year" -gt 2100 ]; then
  die "System clock looks wrong (year=$current_year) — refusing to write a security patch date"
fi

if [ "$current_day" -lt 5 ]; then
  if [ "$current_month" -eq 1 ]; then
    target_month=12
    target_year=$((current_year - 1))
  else
    target_month=$((current_month - 1))
    target_year=$current_year
  fi
else
  target_month=$current_month
  target_year=$current_year
fi

formatted_month=$(printf "%02d" "$target_month")
patch_date="${target_year}-${formatted_month}-05"

# Boot/vendor default to the system date; override only if you know yours differs
boot_offset=$(cfg_get security_patch_boot_offset 0)
vendor_offset=$(cfg_get security_patch_vendor_offset 0)

_offset_date() {
  _od_months="$1"
  if [ "$_od_months" -eq 0 ] 2>/dev/null; then
    printf '%s' "$patch_date"
    return 0
  fi
  _od_total=$(( (target_year * 12 + target_month - 1) - _od_months ))
  _od_y=$(( _od_total / 12 ))
  _od_m=$(( _od_total % 12 + 1 ))
  printf '%s-%s-05' "$_od_y" "$(printf '%02d' "$_od_m")"
  unset _od_months _od_total _od_y _od_m
}

boot_date=$(_offset_date "$boot_offset")
vendor_date=$(_offset_date "$vendor_offset")

if [ "$boot_date" = "$patch_date" ] && [ "$vendor_date" = "$patch_date" ]; then
  log "SECURITY_PATCH" "Writing $patch_date via $KEYSTORE_NAME"
else
  log "SECURITY_PATCH" "Writing system=$patch_date boot=$boot_date vendor=$vendor_date via $KEYSTORE_NAME"
fi

keystore_write_security_patch "$patch_date" "$boot_date" "$vendor_date" || die "Failed to write security patch to $KEYSTORE_SECURITY"

log "SECURITY_PATCH" "Finish"
exit 0
