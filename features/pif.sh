#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/config_env.sh"

[ "$(cfg_get toggle_action_pif 1)" = "0" ] && exit 0

PIF_DIR="/data/adb/modules/playintegrityfix"

if [ ! -d "$PIF_DIR" ]; then
  log "PIF" "Warning: Play Integrity Fix not installed, skipping"
  exit 0
fi

log "PIF" "Start"

check_network || { log "PIF" "Error: No internet connection"; exit 1; }

MODULE_NAME=$(grep "^name=" "$PIF_DIR/module.prop" 2>/dev/null | cut -d= -f2-)
[ -z "$MODULE_NAME" ] && { log "PIF" "Error: Cannot read module.prop"; exit 1; }

_PIF_CANARY_DEVICES="Pixel 6|oriole_beta
Pixel 6 Pro|raven_beta
Pixel 6a|bluejay_beta
Pixel 7|panther_beta
Pixel 7 Pro|cheetah_beta
Pixel 7a|lynx_beta
Pixel Fold|felix_beta
Pixel Tablet|tangorpro_beta
Pixel 8|shiba_beta
Pixel 8 Pro|husky_beta
Pixel 8a|akita_beta
Pixel 9|tokay_beta
Pixel 9 Pro|caiman_beta
Pixel 9 Pro XL|komodo_beta
Pixel 9 Pro Fold|comet_beta
Pixel 9a|tegu_beta"

_pif_prop_valid() {
  grep -q '^FINGERPRINT=' "$1" 2>/dev/null || return 1
  grep -q '^MODEL=' "$1" 2>/dev/null || return 1
  return 0
}


_pif_fetch_github_prop() {
  _pfg_product="$1"
  _pfg_dest="$2"
  _pfg_tmp="/data/adb/JerryManager/.pif_fetch_$$.tmp"

  for _pfg_url in \
    "https://fastly.jsdelivr.net/gh/KOWX712/PlayIntegrityFix@bot/device_prop/${_pfg_product}.prop" \
    "https://raw.githubusercontent.com/KOWX712/PlayIntegrityFix/bot/device_prop/${_pfg_product}.prop" \
    "https://gh.sevencdn.com/https://raw.githubusercontent.com/KOWX712/PlayIntegrityFix/bot/device_prop/${_pfg_product}.prop"
  do
    if download "$_pfg_url" "$_pfg_tmp" && _pif_prop_valid "$_pfg_tmp"; then
      cp "$_pfg_tmp" "$_pfg_dest" 2>/dev/null
      rm -f "$_pfg_tmp"
      unset _pfg_product _pfg_dest _pfg_tmp _pfg_url
      return 0
    fi
  done

  rm -f "$_pfg_tmp"
  unset _pfg_product _pfg_dest _pfg_tmp _pfg_url
  return 1
}


_pif_run_fallback() {
  _prf_script="$1"
  [ -f "$_prf_script" ] || return 1
  shift
  log "PIF" "Direct fetch unavailable, falling back to autopif..."
  sh "$_prf_script" "$@" >/dev/null 2>&1
  _prf_rc=$?
  unset _prf_script
  return "$_prf_rc"
}

_pif_selected_device=""

case "$MODULE_NAME" in
  "Play Integrity Fix [INJECT]")
    log "PIF" "Detected INJECT variant"
    _pif_seed="${RANDOM:-$$}"
    case "$_pif_seed" in *[!0-9]*) _pif_seed="$$" ;; esac
    _pif_count=$(printf '%s\n' "$_PIF_CANARY_DEVICES" | grep -c '|')
    _pif_pick=$((_pif_seed % _pif_count))
    _pif_choice=$(printf '%s\n' "$_PIF_CANARY_DEVICES" | sed -n "$((_pif_pick + 1))p")
    _pif_model="${_pif_choice%%|*}"
    _pif_product="${_pif_choice##*|}"

    if _pif_fetch_github_prop "$_pif_product" "/data/adb/pif.prop"; then
      _pif_selected_device="$_pif_model"
    else
      _pif_run_fallback "$PIF_DIR/autopif_ota.sh"
      _pif_run_fallback "$PIF_DIR/autopif.sh" || log "PIF" "Warning: autopif.sh failed"
    fi
    unset _pif_seed _pif_count _pif_pick _pif_choice _pif_model _pif_product
    ;;
  "Play Integrity Fork")
    log "PIF" "Detected Fork variant"
    _pif_run_fallback "$PIF_DIR/autopif4.sh" -m || log "PIF" "Warning: autopif4.sh failed"
    ;;
  "Play Integrity Fix")
    log "PIF" "Detected original PIF variant"
    if [ -f "$PIF_DIR/autopif.sh" ]; then
      _pif_run_fallback "$PIF_DIR/autopif.sh" || log "PIF" "Warning: autopif.sh failed"
    else
      log "PIF" "Warning: autopif.sh not found"
    fi
    ;;
  *)
    log "PIF" "Warning: Unknown module variant: $MODULE_NAME — skipping safely"
    exit 0
    ;;
esac

if [ -z "$_pif_selected_device" ]; then
  for _pif_prop_candidate in \
      "$PIF_DIR/custom.pif.prop" \
      "$PIF_DIR/pif.prop" \
      "/data/adb/custom.pif.prop" \
      "/data/adb/pif.prop"
  do
      if [ -f "$_pif_prop_candidate" ]; then
          _pif_selected_device=$(awk -F= '/^MODEL=/{print $2}' "$_pif_prop_candidate" | head -1)
          break
      fi
  done
  unset _pif_prop_candidate
fi

[ -n "$_pif_selected_device" ] && log "PIF" "Selected device: $_pif_selected_device"
unset _pif_selected_device

log "PIF" "Finish"
exit 0
