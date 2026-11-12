#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/keystore.sh"

# Usage: security_patch.sh                   boot behaviour: PIF date, device date, bulletin, or computed date
#        security_patch.sh --set YYYY-MM-DD  write this date now (one-shot, boot still runs as usual)
#        security_patch.sh --show            print the last written date as DATE=...
#        security_patch.sh --fetch           read the latest patch date from the Pixel bulletin as DATE=... (writes nothing)

mode="auto"
manual_date=""
case "$1" in
  "") ;;
  --show|--fetch) mode="${1#--}" ;;
  --set)
    mode="set"
    manual_date=$(printf '%s' "$2" | tr -d ' \r\n')
    ;;
  *) die "Unknown option: $1" ;;
esac

# YYYY-MM-DD with year 2015-2100, month 01-12, day 01-31 (pattern match, no octal pitfalls)
_valid_date() {
  case "$1" in
    201[5-9]-*|20[2-9][0-9]-*|2100-*) ;;
    *) return 1 ;;
  esac
  case "${1#????-}" in
    0[1-9]-0[1-9]|0[1-9]-[12][0-9]|0[1-9]-3[01]|1[0-2]-0[1-9]|1[0-2]-[12][0-9]|1[0-2]-3[01]) return 0 ;;
  esac
  return 1
}

# Built-in/standalone PIF spoofs SECURITY_PATCH from pif.prop; keep the keystore patch identical so Play Integrity sees no mismatch.
# Returns 1 (no output) when no PIF is active or pif.prop has no valid date -> caller falls back to bulletin/computed.
_pif_patch_date() {
  _pp_prop="${JERRY_PIF_PROP:-/data/adb/pif.prop}"
  _pp_active=0
  [ -d "${MODDIR%/*}/zygisk" ] && _pp_active=1
  _pp_sa=/data/adb/modules/playintegrityfix
  [ -d "$_pp_sa" ] && [ ! -f "$_pp_sa/disable" ] && [ ! -f "$_pp_sa/remove" ] && _pp_active=1
  if [ "$_pp_active" != "1" ] || [ ! -s "$_pp_prop" ]; then
    unset _pp_prop _pp_active _pp_sa
    return 1
  fi
  _pp_d=$(grep -m1 '^SECURITY_PATCH=' "$_pp_prop" 2>/dev/null | cut -d= -f2- | tr -d ' \r\n')
  unset _pp_prop _pp_active _pp_sa
  _valid_date "$_pp_d" || { unset _pp_d; return 1; }
  printf '%s' "$_pp_d"
  unset _pp_d
  return 0
}

# Real device patch level: system build.prop files, then vendor.
# Returns 1 (no output) when none holds a valid date -> caller falls back to bulletin/computed.
_device_patch_date() {
  for _dp_f in /system/build.prop /system/system/build.prop; do
    [ -f "$_dp_f" ] || continue
    _dp_d=$(grep -m1 '^ro.build.version.security_patch=' "$_dp_f" 2>/dev/null | cut -d= -f2- | tr -d ' \r\n')
    if _valid_date "$_dp_d"; then
      printf '%s' "$_dp_d"
      unset _dp_f _dp_d
      return 0
    fi
  done
  _dp_d=$(getprop ro.vendor.build.security_patch 2>/dev/null | tr -d ' \r\n')
  if ! _valid_date "$_dp_d" && [ -f /vendor/build.prop ]; then
    _dp_d=$(grep -m1 '^ro.vendor.build.security_patch=' /vendor/build.prop 2>/dev/null | cut -d= -f2- | tr -d ' \r\n')
  fi
  if _valid_date "$_dp_d"; then
    printf '%s' "$_dp_d"
    unset _dp_f _dp_d
    return 0
  fi
  unset _dp_f _dp_d
  return 1
}

case "$mode" in
  show)
    printf 'DATE=%s\n' "$(cfg_get security_patch_last "")"
    exit 0
    ;;
  set)
    _valid_date "$manual_date" || die "Invalid date '$manual_date' (use YYYY-MM-DD)"
    ;;
esac

log "SECURITY_PATCH" "Start"

current_year=$(date +%Y) || die "Failed to get year"
current_month=$(date +%m | sed 's/^0*//') || die "Failed to get month"
current_day=$(date +%d | sed 's/^0*//') || die "Failed to get day"

# Guard against a broken/unset device clock before it reaches a patch date (a typed date doesn't depend on the clock)
if [ "$mode" != "set" ] && { [ "$current_year" -lt 2015 ] || [ "$current_year" -gt 2100 ]; }; then
  die "System clock looks wrong (year=$current_year) — refusing to write a security patch date"
fi

# ---- Fallback: compute from device date ----
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

# One quick, time-capped attempt: a slow page must never stall the action.
_bulletin_fetch() {
  _bf_oldpath="$PATH"
  PATH="/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:/data/data/com.termux/files/usr/bin:$PATH"
  _bf_ua="Mozilla/5.0 (Linux; Android 14) JerryManager"
  # Page goes to a file: it is far bigger than one argument may be (printf "Argument list too long")
  ensure_dir "$JERRYMANAGER_DIR"
  _bf_tmp="$JERRYMANAGER_DIR/bulletin_page.tmp"
  rm -f "$_bf_tmp" 2>/dev/null
  # Try curl first (has TLS), then busybox wget; each attempt is time-capped.
  # Stock busybox wget usually has no HTTPS support, which made this fail silently.
  if command -v curl >/dev/null 2>&1 && curl --version >/dev/null 2>&1; then
    curl -Ls --connect-timeout 6 -m 12 -A "$_bf_ua" -o "$_bf_tmp" "$BULLETIN_URL" 2>/dev/null
  fi
  if [ ! -s "$_bf_tmp" ]; then
    if busybox timeout 1 true >/dev/null 2>&1; then
      busybox timeout 12 busybox wget -T 6 --no-check-certificate -qO "$_bf_tmp" -U "$_bf_ua" "$BULLETIN_URL" 2>/dev/null
    else
      busybox wget -T 6 --no-check-certificate -qO "$_bf_tmp" -U "$_bf_ua" "$BULLETIN_URL" 2>/dev/null
    fi
  fi
  unset _bf_ua
  PATH="$_bf_oldpath"
  unset _bf_oldpath
  [ -s "$_bf_tmp" ] || { log "SECURITY_PATCH" "Bulletin fetch returned empty page (no curl or no HTTPS support in wget?)"; rm -f "$_bf_tmp" 2>/dev/null; unset _bf_tmp; return 1; }
  # Bulletin list is newest-first and now shows YYYY-MM-01; Pixel devices report YYYY-MM-05
  _bf_date=$(grep -oE '20[0-9]{2}-[01][0-9]-[0-3][0-9]' "$_bf_tmp" | head -n1)
  rm -f "$_bf_tmp" 2>/dev/null
  unset _bf_tmp
  [ -n "$_bf_date" ] && _bf_date="${_bf_date%??}05"
  [ -n "$_bf_date" ] || { log "SECURITY_PATCH" "Bulletin page fetched but no patch date found (page layout changed?)"; return 1; }
  _bf_year=$(printf '%s' "$_bf_date" | cut -d- -f1)
  # sanity check: must be this year or last (not a stale/garbage match)
  if [ "$_bf_year" -ge $((current_year - 1)) ] 2>/dev/null && [ "$_bf_year" -le "$current_year" ] 2>/dev/null; then
    printf '%s' "$_bf_date"
    unset _bf_date _bf_year
    return 0
  fi
  unset _bf_date _bf_year
  return 1
}

# --fetch: live lookup only, no keystore backend needed and nothing is written
if [ "$mode" = "fetch" ]; then
  check_network || die "No internet connection"
  _fetched=$(_bulletin_fetch)
  _valid_date "$_fetched" || die "Could not read the date from the Pixel bulletin"
  _bulletin_cache_write "$_fetched"
  log "SECURITY_PATCH" "Fetched bulletin date $_fetched on request"
  printf 'DATE=%s\n' "$_fetched"
  exit 0
fi

resolve_keystore_backend
keystore_ready || die "No active keystore backend found"

if [ "$mode" = "set" ]; then
  patch_date="$manual_date"
  patch_source="manual"
elif _pif_date=$(_pif_patch_date) && [ -n "$_pif_date" ]; then
  patch_date="$_pif_date"
  patch_source=""
  log "SECURITY_PATCH" "Matching PIF pif.prop SECURITY_PATCH $patch_date (bulletin/computed $fallback_patch_date ignored)"
elif _dev_date=$(_device_patch_date) && [ -n "$_dev_date" ]; then
  patch_date="$_dev_date"
  patch_source="device"
  log "SECURITY_PATCH" "Using device build.prop patch level $patch_date (bulletin/computed $fallback_patch_date ignored)"
elif [ "$(cfg_get toggle_security_patch_bulletin 1)" = "0" ]; then
  log "SECURITY_PATCH" "Bulletin fetch disabled by toggle — using computed date"
elif _bulletin_fresh=$(_bulletin_cache_read) && [ -n "$_bulletin_fresh" ]; then
  patch_date="$_bulletin_fresh"
  patch_source="cache"
  log "SECURITY_PATCH" "Using cached bulletin date $patch_date"
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
  log "SECURITY_PATCH" "Writing $patch_date${patch_source:+ (source: $patch_source)} via $KEYSTORE_NAME"
else
  log "SECURITY_PATCH" "Writing system=$patch_date boot=$boot_date vendor=$vendor_date${patch_source:+ (source: $patch_source)} via $KEYSTORE_NAME"
fi

keystore_write_security_patch "$patch_date" "$boot_date" "$vendor_date" || die "Failed to write security patch to $KEYSTORE_SECURITY"

cfg_set security_patch_last "$patch_date"
[ "$mode" = "set" ] && printf 'DATE=%s\n' "$patch_date"

log "SECURITY_PATCH" "Finish"
exit 0
