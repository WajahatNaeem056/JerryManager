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

# ---- Fallback: compute from device date (old behavior) ----
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
fallback_patch_date="${target_year}-${formatted_month}-05"
patch_date="$fallback_patch_date"
patch_source="computed"

# ---- Bulletin fetch: real patch level instead of guessing ----
BULLETIN_URL="https://source.android.com/docs/security/bulletin/pixel"
BULLETIN_CACHE="$JERRYMANAGER_DIR/bulletin_cache"
BULLETIN_MAX_AGE=72000   # 20h -- long enough to skip refetching every boot, short enough to catch a new bulletin within a day

_bulletin_cache_read() {
  [ -f "$BULLETIN_CACHE" ] || return 1
  _bc_ts=$(cut -d' ' -f1 "$BULLETIN_CACHE" 2>/dev/null)
  _bc_val=$(cut -d' ' -f2 "$BULLETIN_CACHE" 2>/dev/null)
  case "$_bc_ts" in ''|*[!0-9]*) unset _bc_ts _bc_val; return 1 ;; esac
  _bc_now=$(date +%s 2>/dev/null || echo 0)
  if [ "$((_bc_now - _bc_ts))" -lt "$BULLETIN_MAX_AGE" ] 2>/dev/null && [ -n "$_bc_val" ]; then
    printf '%s' "$_bc_val"
    unset _bc_ts _bc_val _bc_now
    return 0
  fi
  unset _bc_ts _bc_val _bc_now
  return 1
}

_bulletin_cache_write() {
  ensure_dir "$JERRYMANAGER_DIR"
  printf '%s %s\n' "$(date +%s 2>/dev/null || echo 0)" "$1" > "$BULLETIN_CACHE" 2>/dev/null
}

_bulletin_fetch() {
  _bf_try=0
  while [ "$_bf_try" -lt 3 ]; do
    _bf_page=$(download "$BULLETIN_URL" 2>/dev/null)
    if [ -n "$_bf_page" ]; then
      _bf_date=$(printf '%s' "$_bf_page" | grep -oE '20[0-9]{2}-[01][0-9]-05' | head -n1)
      if [ -n "$_bf_date" ]; then
        _bf_year=$(printf '%s' "$_bf_date" | cut -d- -f1)
        # sanity check: must be this year or last (not a stale/garbage match)
        if [ "$_bf_year" -ge $((current_year - 1)) ] 2>/dev/null && [ "$_bf_year" -le "$current_year" ] 2>/dev/null; then
          printf '%s' "$_bf_date"
          unset _bf_try _bf_page _bf_date _bf_year
          return 0
        fi
      fi
    fi
    unset _bf_page _bf_date _bf_year
    _bf_try=$((_bf_try + 1))
    sleep $((_bf_try * 3))
  done
  unset _bf_try
  return 1
}

if [ "$(cfg_get toggle_security_patch_bulletin 1)" = "0" ]; then
  log "SECURITY_PATCH" "Bulletin fetch disabled by toggle — using computed date"
elif ! check_network; then
  _bulletin_cached=$(_bulletin_cache_read)
  if [ -n "$_bulletin_cached" ]; then
    patch_date="$_bulletin_cached"
    patch_source="cache"
    log "SECURITY_PATCH" "No network — using cached bulletin date $patch_date"
  else
    log "SECURITY_PATCH" "No network and no cached bulletin — using computed date"
  fi
  unset _bulletin_cached
else
  _bulletin_live=$(_bulletin_fetch)
  if [ -n "$_bulletin_live" ]; then
    patch_date="$_bulletin_live"
    patch_source="bulletin"
    _bulletin_cache_write "$_bulletin_live"
    log "SECURITY_PATCH" "Fetched live bulletin date $patch_date"
  else
    _bulletin_cached=$(_bulletin_cache_read)
    if [ -n "$_bulletin_cached" ]; then
      patch_date="$_bulletin_cached"
      patch_source="cache"
      log "SECURITY_PATCH" "Bulletin fetch failed after retries — using cached date $patch_date"
    else
      log "SECURITY_PATCH" "Bulletin fetch failed after retries, no cache — using computed date"
    fi
    unset _bulletin_cached
  fi
  unset _bulletin_live
fi

# Re-anchor target_year/target_month to whatever patch_date actually won
target_year=$(printf '%s' "$patch_date" | cut -d- -f1)
target_month=$(printf '%s' "$patch_date" | cut -d- -f2 | sed 's/^0*//')

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
  log "SECURITY_PATCH" "Writing $patch_date (source: $patch_source) via $KEYSTORE_NAME"
else
  log "SECURITY_PATCH" "Writing system=$patch_date boot=$boot_date vendor=$vendor_date (source: $patch_source) via $KEYSTORE_NAME"
fi

keystore_write_security_patch "$patch_date" "$boot_date" "$vendor_date" || die "Failed to write security patch to $KEYSTORE_SECURITY"

log "SECURITY_PATCH" "Finish"
exit 0
