#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/urls.sh"
. "$MODDIR/../lib/keystore.sh"

log "KEYBOX" "Start"

resolve_keystore_backend

if [ "$KEYSTORE_BACKEND" = "none" ]; then
  log "KEYBOX" "Error: No active keystore backend found"
  exit 1
fi

if [ "$KEYSTORE_BACKEND" = "omk" ]; then
  log "KEYBOX" "OhMyKeymint active — using simplified install path"
  _omk_custom_type=$(cfg_get kb_custom_type "")
  _omk_custom_value=$(cfg_get kb_custom_value "")
  _omk_temp="$MODDIR/keybox.tmp"
  _omk_decode="$MODDIR/keybox_decode"

  if [ -n "$_omk_custom_type" ] && [ -n "$_omk_custom_value" ]; then
    if [ -f "$OMK_KEYBOX" ] && [ -z "$(find_keybox_backup omk)" ]; then
      cp "$OMK_KEYBOX" "$OMK_BACKUP"
      log "KEYBOX" "Created backup of existing keybox"
    fi
    case "$_omk_custom_type" in
      file|path)
        [ -f "$_omk_custom_value" ] || { log "KEYBOX" "Error: Custom keybox file not found: $_omk_custom_value"; cfg_delete kb_custom_type; cfg_delete kb_custom_value; exit 1; }
        keystore_install_keybox "$_omk_custom_value" || { log "KEYBOX" "Error: Failed to copy custom keybox"; exit 1; }
        log "KEYBOX" "Custom keybox installed from $_omk_custom_value"
        ;;
      url)
        check_network || { log "KEYBOX" "Error: No internet connection"; exit 1; }
        download "$_omk_custom_value" > "$_omk_temp" || { log "KEYBOX" "Error: Custom URL download failed"; rm -f "$_omk_temp"; exit 1; }
        if base64 -d "$_omk_temp" > "$_omk_decode" 2>/dev/null && [ -s "$_omk_decode" ]; then
          keystore_install_keybox "$_omk_decode" || { log "KEYBOX" "Error: Failed to install keybox"; rm -f "$_omk_temp" "$_omk_decode"; exit 1; }
          rm -f "$_omk_temp" "$_omk_decode"
          log "KEYBOX" "Custom keybox installed from URL"
        else
          log "KEYBOX" "Error: Custom keybox decode failed, not a valid base64 blob"
          rm -f "$_omk_temp" "$_omk_decode"
          exit 1
        fi
        ;;
    esac
    cfg_delete kb_custom_type
    cfg_delete kb_custom_value
    unset _omk_custom_type _omk_custom_value _omk_temp _omk_decode
    log "KEYBOX" "Finish (OhMyKeymint, custom)"
    exit 0
  fi
  unset _omk_custom_type _omk_custom_value

  if [ -f "$OMK_KEYBOX" ] && [ -z "$(find_keybox_backup omk)" ]; then
    cp "$OMK_KEYBOX" "$OMK_BACKUP"
    log "KEYBOX" "Created backup of existing keybox"
  fi

  check_network || { log "KEYBOX" "Error: No internet connection"; exit 1; }
  log "KEYBOX" "Downloading keybox..."
  download "$KEYBOX_URL" > "$_omk_temp" || { log "KEYBOX" "Error: Download failed"; rm -f "$_omk_temp"; exit 1; }

  if base64 -d "$_omk_temp" > "$_omk_decode" 2>/dev/null && [ -s "$_omk_decode" ]; then
    keystore_install_keybox "$_omk_decode" || { log "KEYBOX" "Error: Failed to install keybox"; exit 1; }
  else
    keystore_install_keybox "$_omk_temp" || { log "KEYBOX" "Error: Failed to install keybox"; exit 1; }
  fi
  rm -f "$_omk_temp" "$_omk_decode"

  _serial=$(decode_keybox_serial "$KEYSTORE_KEYBOX" 2>/dev/null || echo "")
  if [ -n "$_serial" ]; then
    log "KEYBOX" "Checking Google revocation for serial $_serial"
    if check_google_revocation "$_serial"; then
      log "KEYBOX" "Warning: Keybox is revoked by Google (installed anyway — update soon)"
      cfg_set keybox_valid "No"
    else
      cfg_set keybox_valid "Yes"
    fi
  fi
  unset _serial

  log "KEYBOX" "Finish (OhMyKeymint)"
  exit 0
fi

if [ "$KEYSTORE_BACKEND" = "teesim" ]; then
  log "KEYBOX" "$KEYSTORE_NAME active — installing raw keybox.xml"
  _tee_custom_type=$(cfg_get kb_custom_type "")
  _tee_custom_value=$(cfg_get kb_custom_value "")
  _tee_temp="$MODDIR/keybox.tmp"
  _tee_decode="$MODDIR/keybox_decode"

  _tee_install() {
    mkdir -p "$TEESIM_DIR" 2>/dev/null
    if [ -f "$TEESIM_KEYBOX" ] && [ -z "$(find_keybox_backup teesim)" ]; then
      cp "$TEESIM_KEYBOX" "$TEESIM_BACKUP" 2>/dev/null
      log "KEYBOX" "Created backup of existing keybox"
    fi
    cp "$1" "$TEESIM_KEYBOX" 2>/dev/null || return 1
    [ -f "$TEESIM_CONFIG" ] && _teesim_set_keybox_field "$TEESIM_CONFIG"
    return 0
  }

  if [ -n "$_tee_custom_type" ] && [ -n "$_tee_custom_value" ]; then
    case "$_tee_custom_type" in
      file|path)
        [ -f "$_tee_custom_value" ] || { log "KEYBOX" "Error: Custom keybox file not found: $_tee_custom_value"; cfg_delete kb_custom_type; cfg_delete kb_custom_value; exit 1; }
        _tee_install "$_tee_custom_value" || { log "KEYBOX" "Error: Failed to copy custom keybox"; exit 1; }
        log "KEYBOX" "Custom keybox installed from $_tee_custom_value"
        ;;
      url)
        check_network || { log "KEYBOX" "Error: No internet connection"; exit 1; }
        download "$_tee_custom_value" > "$_tee_temp" || { log "KEYBOX" "Error: Custom URL download failed"; rm -f "$_tee_temp"; exit 1; }
        if base64 -d "$_tee_temp" > "$_tee_decode" 2>/dev/null && [ -s "$_tee_decode" ]; then
          _tee_install "$_tee_decode" || { log "KEYBOX" "Error: Failed to install keybox"; rm -f "$_tee_temp" "$_tee_decode"; exit 1; }
          rm -f "$_tee_temp" "$_tee_decode"
          log "KEYBOX" "Custom keybox installed from URL"
        else
          log "KEYBOX" "Error: Custom keybox decode failed, not a valid base64 blob"
          rm -f "$_tee_temp" "$_tee_decode"
          exit 1
        fi
        ;;
    esac
    cfg_delete kb_custom_type
    cfg_delete kb_custom_value
    unset _tee_custom_type _tee_custom_value _tee_temp _tee_decode
    log "KEYBOX" "Finish (TEESimulator, custom)"
    exit 0
  fi
  unset _tee_custom_type _tee_custom_value

  check_network || { log "KEYBOX" "Error: No internet connection"; exit 1; }
  log "KEYBOX" "Downloading keybox..."
  download "$KEYBOX_URL" > "$_tee_temp" || { log "KEYBOX" "Error: Download failed"; rm -f "$_tee_temp"; exit 1; }

  if base64 -d "$_tee_temp" > "$_tee_decode" 2>/dev/null && [ -s "$_tee_decode" ]; then
    _tee_install "$_tee_decode" || { log "KEYBOX" "Error: Failed to install keybox"; exit 1; }
  else
    log "KEYBOX" "Error: Base64 decode failed"
    rm -f "$_tee_temp" "$_tee_decode"
    exit 1
  fi
  rm -f "$_tee_temp" "$_tee_decode"

  log "KEYBOX" "Keybox installed successfully ($KEYSTORE_NAME)"
  log "KEYBOX" "Finish"
  exit 0
fi

DECODE_FILE="$TRICKY_DIR/keybox_decode"
TEMP_FILE="$TRICKY_DIR/keybox.tmp"

_custom_type=$(cfg_get kb_custom_type "")
_custom_value=$(cfg_get kb_custom_value "")

_clear_custom() {
  cfg_delete kb_custom_type
  cfg_delete kb_custom_value
}

if [ -n "$_custom_type" ] && [ -n "$_custom_value" ]; then
  log "KEYBOX" "Using custom keybox: $_custom_type ($_custom_value)"
  case "$_custom_type" in
    file|path)
      if [ ! -d "$TRICKY_DIR" ]; then
        log "KEYBOX" "Error: Tricky Store data directory not found"
        _clear_custom; exit 1
      fi
      if [ -f "$TARGET_FILE" ] && [ -z "$(find_keybox_backup trickystore)" ]; then
        cp "$TARGET_FILE" "$BACKUP_FILE"
        log "KEYBOX" "Created backup of existing keybox"
      fi
      if [ -f "$_custom_value" ]; then
        cp "$_custom_value" "$TARGET_FILE" || { log "KEYBOX" "Error: Failed to copy custom keybox"; _clear_custom; exit 1; }
        log "KEYBOX" "Custom keybox installed from $_custom_value"
        _clear_custom
        exit 0
      fi
      log "KEYBOX" "Error: Custom keybox file not found: $_custom_value"
      _clear_custom
      exit 1
      ;;
    url)
      if [ ! -d "$TRICKY_DIR" ]; then
        log "KEYBOX" "Error: Tricky Store data directory not found"
        _clear_custom; exit 1
      fi
      if [ -f "$TARGET_FILE" ] && [ -z "$(find_keybox_backup trickystore)" ]; then
        cp "$TARGET_FILE" "$BACKUP_FILE"
        log "KEYBOX" "Created backup of existing keybox"
      fi
      check_network || { log "KEYBOX" "Error: No internet connection"; _clear_custom; exit 1; }
      log "KEYBOX" "Downloading custom keybox from URL..."
      download "$_custom_value" > "$TEMP_FILE" || {
        log "KEYBOX" "Error: Custom URL download failed"
        _clear_custom
        [ -f "$BACKUP_FILE" ] && cp "$BACKUP_FILE" "$TARGET_FILE"
        exit 1
      }
      if base64 -d "$TEMP_FILE" > "$DECODE_FILE" 2>/dev/null && [ -s "$DECODE_FILE" ]; then
        mv "$DECODE_FILE" "$TARGET_FILE" || { log "KEYBOX" "Error: Failed to move decoded keybox"; rm -f "$TEMP_FILE"; _clear_custom; exit 1; }
        rm -f "$TEMP_FILE"
        log "KEYBOX" "Custom keybox installed from URL"
        _clear_custom
        exit 0
      fi
      log "KEYBOX" "Error: Custom keybox decode failed, not a valid base64 blob"
      rm -f "$TEMP_FILE" "$DECODE_FILE"
      _clear_custom
      [ -f "$BACKUP_FILE" ] && cp "$BACKUP_FILE" "$TARGET_FILE"
      exit 1
      ;;
  esac
fi

if [ ! -d "$TRICKY_DIR" ]; then
  log "KEYBOX" "Error: Tricky Store data directory not found"
  exit 1
fi

if [ -f "$TARGET_FILE" ] && [ -z "$(find_keybox_backup trickystore)" ]; then
  cp "$TARGET_FILE" "$BACKUP_FILE"
  log "KEYBOX" "Created backup of existing keybox"
fi

check_network || { log "KEYBOX" "Error: No internet connection"; exit 1; }

log "KEYBOX" "Downloading keybox..."
download "$KEYBOX_URL" > "$TEMP_FILE" || {
  log "KEYBOX" "Error: Download failed"
  rm -f "$TEMP_FILE"
  [ -f "$BACKUP_FILE" ] && cp "$BACKUP_FILE" "$TARGET_FILE"
  exit 1
}

if ! base64 -d "$TEMP_FILE" > "$DECODE_FILE" 2>/dev/null; then
  log "KEYBOX" "Error: Base64 decode failed"
  rm -f "$TEMP_FILE"
  [ -f "$BACKUP_FILE" ] && cp "$BACKUP_FILE" "$TARGET_FILE"
  exit 1
fi

mv "$DECODE_FILE" "$TARGET_FILE" || { log "KEYBOX" "Error: Failed to move keybox"; exit 1; }

_serial=$(decode_keybox_serial "$TARGET_FILE" 2>/dev/null || echo "")
if [ -n "$_serial" ]; then
    log "KEYBOX" "Checking Google revocation for serial $_serial"
    if check_google_revocation "$_serial"; then
        log "KEYBOX" "Warning: Keybox is revoked by Google (installed anyway — update soon)"
        cfg_set keybox_valid "No"
    else
        log "KEYBOX" "Keybox is not revoked — clean"
        cfg_set keybox_valid "Yes"
    fi
else
    log "KEYBOX" "Warning: Could not extract serial for revocation check"
    cfg_set keybox_valid "Unknown"
fi
unset _serial

log "KEYBOX" "Keybox installed successfully"
rm -f "$TEMP_FILE"
log "KEYBOX" "Finish"
exit 0
