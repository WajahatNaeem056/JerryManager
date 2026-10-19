#!/system/bin/sh
# Built-in Play Integrity Fix: fetch a fresh Pixel Canary fingerprint into /data/adb/pif.prop.
# Env: PIF_FORCE=1   run even if the boot toggle is off
#      PIF_DEVICE    <codename>_beta, or empty/random
#      PIF_SOURCE    github | autopif | auto (GitHub first, autopif as fallback)
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/config_env.sh"

[ "$PIF_FORCE" != "1" ] && [ "$(cfg_get toggle_action_pif 1)" = "0" ] && exit 0

PIF_ROOT="${MODDIR%/*}"
. "$MODDIR/../lib/pif_lib.sh"
. "$MODDIR/../lib/pif_devices.sh"

if [ ! -f "$PIF_ROOT/dex/classes.dex" ] || [ ! -d "$PIF_ROOT/zygisk" ]; then
  log "PIF" "Warning: built-in PIF files missing, skipping"
  exit 0
fi

log "PIF" "Start"
# Shown by action.sh and the orchestrator. Fork only if a standalone PIF module is still active next to the built-in one.
if [ -d /data/adb/modules/playintegrityfix ] && [ ! -f /data/adb/modules/playintegrityfix/disable ] && [ ! -f /data/adb/modules/playintegrityfix/remove ]; then
    log "PIF" "Detected Fork (standalone module) variant"
else
    log "PIF" "Detected Built-in variant"
fi
check_network || { log "PIF" "Error: No internet connection"; exit 1; }

PIF_TMP="/data/adb/JerryManager/.pif_fetch_$$.tmp"

# Fetch <product>.prop from the KOWX712 bot branch (3 mirrors) into $PIF_PROP, keeping the user's spoof flags
fetch_github() {
  for _url in \
    "https://fastly.jsdelivr.net/gh/KOWX712/PlayIntegrityFix@bot/device_prop/$1.prop" \
    "https://raw.githubusercontent.com/KOWX712/PlayIntegrityFix/bot/device_prop/$1.prop" \
    "https://gh.sevencdn.com/https://raw.githubusercontent.com/KOWX712/PlayIntegrityFix/bot/device_prop/$1.prop"
  do
    if download "$_url" "$PIF_TMP" \
       && grep -q '^FINGERPRINT=' "$PIF_TMP" && grep -q '^MODEL=' "$PIF_TMP"; then
      pif_merge_flags "$PIF_TMP" "$PIF_PROP"
      cp "$PIF_TMP" "$PIF_PROP" && { rm -f "$PIF_TMP"; return 0; }
    fi
  done
  rm -f "$PIF_TMP"
  return 1
}

# Picks the (n+1)-th device after a random start, so retries try different ones
random_product() {
  _count=$(printf '%s\n' "$PIF_DEVICE_LIST" | grep -c '|')
  _seed="${RANDOM:-$$}"
  case "$_seed" in *[!0-9]*) _seed="$$" ;; esac
  printf '%s\n' "$PIF_DEVICE_LIST" | sed -n "$(( (_seed + $1) % _count + 1 ))p" | cut -d'|' -f2
}

run_autopif() {
  [ -f "$MODDIR/pif_autopif.sh" ] || return 1
  log "PIF" "Using autopif (Google Pixel Beta pages)..."
  if [ "$PIF_FORCE" = "1" ]; then
    PRODUCT="$1" sh "$MODDIR/pif_autopif.sh"
  else
    PRODUCT="$1" sh "$MODDIR/pif_autopif.sh" >/dev/null 2>&1
  fi
}

device="$PIF_DEVICE"
[ "$device" = "random" ] && device=""
source="${PIF_SOURCE:-auto}"
product=""
ok=0

if [ "$source" = "autopif" ]; then
  run_autopif "$device" && ok=1
else
  if [ -n "$device" ]; then
    fetch_github "$device" && { ok=1; product="$device"; }
  else
    # A random pick may not exist on GitHub yet, so try a few
    for try in 0 1 2 3; do
      _candidate="$(random_product "$try")"
      fetch_github "$_candidate" && { ok=1; product="$_candidate"; break; }
    done
  fi
  if [ "$ok" -eq 0 ] && [ "$source" = "auto" ]; then
    log "PIF" "GitHub fetch failed, falling back to autopif"
    run_autopif "$device" && ok=1
  fi
fi

if [ "$ok" -eq 0 ]; then
  log "PIF" "Warning: could not fetch fingerprint, keeping current pif.prop"
  exit 1
fi

pif_kill_gms

if [ -n "$product" ]; then
  model="$(pif_model_of "$product")"
else
  model="$(pif_prop_get "$PIF_PROP" MODEL)"
fi
[ -n "$model" ] && log "PIF" "Selected device: $model"
log "PIF" "Finish"
exit 0
