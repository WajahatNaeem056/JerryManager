#!/system/bin/sh
# Install a keybox for the active backend (OhMyKeymint, TEESimulator or Tricky Store).
# One flow for all three: custom keybox (file or URL) if one is set, otherwise the Jerry keybox.
# Every install goes through keystore_install_keybox (validation, in-place copy, backend reload).
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/urls.sh"
. "$MODDIR/../lib/catalog.sh"
. "$MODDIR/../lib/keystore.sh"

log "KEYBOX" "Start"

resolve_keystore_backend

if [ "$KEYSTORE_BACKEND" = "none" ]; then
  log "KEYBOX" "Error: No active keystore backend found"
  exit 1
fi
keystore_ready || ensure_dir "$KEYSTORE_DIR"

_kb_temp="$MODDIR/keybox.tmp"
_kb_decode="$MODDIR/keybox_decode"
trap 'rm -f "$_kb_temp" "$_kb_decode"' EXIT

_clear_custom() {
  cfg_delete kb_custom_type
  cfg_delete kb_custom_value
}

# Keep one backup of the user's own keybox (not Jerry's) before Jerry replaces it
_backup_existing() {
  if [ -f "$KEYSTORE_KEYBOX" ] && ! keybox_is_jerry "$KEYSTORE_KEYBOX" && [ -z "$(find_keybox_backup "$KEYSTORE_BACKEND")" ]; then
    cp "$KEYSTORE_KEYBOX" "$KEYSTORE_BACKUP" 2>/dev/null && log "KEYBOX" "Created backup of existing keybox"
  fi
}

# Download $1, decode base64 into $_kb_decode (a raw XML download is used as is). Prints the file to install.
_fetch_keybox() {
  download "$1" > "$_kb_temp" || { rm -f "$_kb_temp"; return 1; }
  if base64 -d "$_kb_temp" > "$_kb_decode" 2>/dev/null && [ -s "$_kb_decode" ]; then
    echo "$_kb_decode"
  elif [ -s "$_kb_temp" ]; then
    echo "$_kb_temp"
  else
    return 1
  fi
}

# Check Google's revocation list for the installed keybox and record the result
_check_revocation() {
  _serial=$(decode_keybox_serial "$KEYSTORE_KEYBOX" 2>/dev/null || echo "")
  if [ -n "$_serial" ]; then
    log "KEYBOX" "Checking Google revocation for serial $_serial"
    _rev_info=$(google_revocation_info "$_serial"); _rev_rc=$?
    case "$_rev_rc" in
      0)
        _rev_reason="${_rev_info#*|}"
        log "KEYBOX" "Warning: Keybox is revoked by Google${_rev_reason:+ ($_rev_reason)} (installed anyway — update soon)"
        cfg_set keybox_valid "No"
        ;;
      1)
        log "KEYBOX" "Keybox is not revoked — clean"
        cfg_set keybox_valid "Yes"
        ;;
      *)
        log "KEYBOX" "Warning: Google revocation list unavailable — keybox status unknown (checked again later)"
        cfg_set keybox_valid "Unknown"
        ;;
    esac
    if keybox_is_expired "$KEYSTORE_KEYBOX"; then
      log "KEYBOX" "Warning: Keybox certificate has expired (installed anyway — update soon)"
      [ "$(cfg_get keybox_valid "")" != "No" ] && cfg_set keybox_valid "Expired"
    fi
    unset _rev_info _rev_rc _rev_reason
  else
    log "KEYBOX" "Warning: Could not extract serial for revocation check"
    cfg_set keybox_valid "Unknown"
  fi
  unset _serial
}

# Offline check for a custom keybox: never claims Valid/Revoked without asking Google
_check_expiry_local() {
  if keybox_is_expired "$KEYSTORE_KEYBOX"; then
    log "KEYBOX" "Warning: Keybox certificate has expired (installed anyway)"
    cfg_set keybox_valid "Expired"
  else
    cfg_set keybox_valid "Unknown"
  fi
}

_custom_type=$(cfg_get kb_custom_type "")
_custom_value=$(cfg_get kb_custom_value "")

if [ -n "$_custom_type" ] && [ -n "$_custom_value" ]; then
  log "KEYBOX" "Using custom keybox: $_custom_type ($_custom_value) [$KEYSTORE_NAME]"
  _backup_existing
  case "$_custom_type" in
    file|path)
      if [ ! -f "$_custom_value" ]; then
        log "KEYBOX" "Error: Custom keybox file not found: $_custom_value"
        _clear_custom; exit 1
      fi
      keystore_install_keybox "$_custom_value" || { log "KEYBOX" "Error: Failed to install custom keybox"; _clear_custom; exit 1; }
      log "KEYBOX" "Custom keybox installed from $_custom_value"
      ;;
    url)
      check_network || { log "KEYBOX" "Error: No internet connection"; exit 1; }
      log "KEYBOX" "Downloading custom keybox from URL..."
      _kb_src=$(_fetch_keybox "$_custom_value") || { log "KEYBOX" "Error: Custom URL download failed"; _clear_custom; exit 1; }
      keystore_install_keybox "$_kb_src" || { log "KEYBOX" "Error: Failed to install custom keybox"; _clear_custom; exit 1; }
      log "KEYBOX" "Custom keybox installed from URL"
      ;;
    *)
      log "KEYBOX" "Error: Unknown custom keybox type: $_custom_type"
      _clear_custom; exit 1
      ;;
  esac
  _clear_custom
  # Custom keybox: no network here. Offline expiry check only; revocation shows on the Keybox card
  _check_expiry_local
  log "KEYBOX" "Finish ($KEYSTORE_NAME, custom)"
  exit 0
fi

_backup_existing
check_network || { log "KEYBOX" "Error: No internet connection"; exit 1; }

# Catalog first (skips revoked / expired / softbanned); no catalog = the old single URL
_kb_url="$KEYBOX_URL"
_kb_url_fb="$KEYBOX_URL_FALLBACK"
_kb_entry=$(keybox_pick_entry 2>/dev/null) || _kb_entry=""
if [ -n "$_kb_entry" ]; then
  _kb_ver=$(_kc_field "$_kb_entry" version)
  _kb_url=$(_kc_field "$_kb_entry" url)
  _kb_url_fb=$(_kc_field "$_kb_entry" url_fallback)
  if _kc_flag "$_kb_entry" softbanned; then
    log "KEYBOX" "Warning: every catalog keybox is softbanned, using newest (v$_kb_ver)"
  else
    log "KEYBOX" "Catalog pick: v$_kb_ver"
  fi
else
  log "KEYBOX" "Catalog unavailable, using default keybox URL"
fi

log "KEYBOX" "Downloading keybox..."
_kb_src=$(_fetch_keybox "$_kb_url") || _kb_src=""
if [ -z "$_kb_src" ] && [ -n "$_kb_url_fb" ] && [ "$_kb_url_fb" != "$_kb_url" ]; then
  log "KEYBOX" "Primary download failed, trying fallback..."
  _kb_src=$(_fetch_keybox "$_kb_url_fb") || _kb_src=""
fi
[ -n "$_kb_src" ] || { log "KEYBOX" "Error: Download failed"; exit 1; }
keystore_install_keybox "$_kb_src" || { log "KEYBOX" "Error: Failed to install keybox"; exit 1; }

_check_revocation

log "KEYBOX" "Keybox installed successfully ($KEYSTORE_NAME)"
log "KEYBOX" "Finish"
exit 0
