#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/urls.sh"

log "KEYBOX" "Start"

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
      if [ -f "$TARGET_FILE" ] && [ ! -f "$BACKUP_FILE" ]; then
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
      if [ -f "$TARGET_FILE" ] && [ ! -f "$BACKUP_FILE" ]; then
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
        mv "$DECODE_FILE" "$TARGET_FILE" || { log "KEYBOX" "Error: Failed to move decoded keybox"; exit 1; }
      else
        cp "$TEMP_FILE" "$TARGET_FILE" || { log "KEYBOX" "Error: Failed to copy keybox"; exit 1; }
      fi
      rm -f "$TEMP_FILE"
      log "KEYBOX" "Custom keybox installed from URL"
      _clear_custom
      exit 0
      ;;
  esac
fi

if [ ! -d "$TRICKY_DIR" ]; then
  log "KEYBOX" "Error: Tricky Store data directory not found"
  exit 1
fi

if [ -f "$TARGET_FILE" ] && [ ! -f "$BACKUP_FILE" ]; then
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

_install_teesimulator() {
  log "KEYBOX" "TEESimulator detected — generating locked.xml format"

  _tee_serial=$(decode_keybox_serial "$DECODE_FILE" 2>/dev/null || echo "unknown")
  _tee_random=$(hexdump -n 4 -e '4/4 "%08X"' /dev/urandom 2>/dev/null || echo "$$")
  _tee_ecdsa=$(sed -n '/<Key algorithm="ecdsa">/,/<\/Key>/p' "$DECODE_FILE" 2>/dev/null)
  _tee_rsa=$(sed -n '/<Key algorithm="rsa">/,/<\/Key>/p' "$DECODE_FILE" 2>/dev/null)

  if [ -f "$LOCKED_FILE" ] && [ ! -f "$LOCKED_BACKUP" ]; then
    cp "$LOCKED_FILE" "$LOCKED_BACKUP"
    log "KEYBOX" "Backup created: locked.xml.bak"
  fi

  if [ -z "$_tee_ecdsa" ]; then
    log "KEYBOX" "Warning: No ECDSA key found — writing placeholder locked.xml"
    {
      echo '<?xml version="1.0" encoding="UTF-8"?>'
      echo '<AndroidAttestation>'
      echo '<NumberOfKeyboxes>1</NumberOfKeyboxes>'
      echo '<Keybox>'
      echo '# No valid ECDSA key available — placeholder only'
      echo '</Keybox>'
      echo '</AndroidAttestation>'
    } > "$LOCKED_FILE"
    log "KEYBOX" "Placeholder locked.xml written"
    unset _tee_serial _tee_random _tee_ecdsa _tee_rsa
    return
  fi

  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<AndroidAttestation>'
    echo '<NumberOfKeyboxes>1</NumberOfKeyboxes>'
    echo "<Keybox DeviceID=\"$_tee_serial\">"
    printf '%s\n' "$_tee_ecdsa"
    echo "  <serial>${_tee_serial}_${_tee_random}</serial>"
    [ -n "$_tee_rsa" ] && printf '%s\n' "$_tee_rsa"
    echo '</Keybox>'
    echo '</AndroidAttestation>'
  } > "$LOCKED_FILE"

  log "KEYBOX" "locked.xml written to $LOCKED_FILE"
  unset _tee_serial _tee_random _tee_ecdsa _tee_rsa
}

if _is_teesimulator; then
  log "KEYBOX" "TEESimulator module detected"
  _install_teesimulator
  rm -f "$TEMP_FILE" "$DECODE_FILE" 2>/dev/null
  log "KEYBOX" "Finish"
  exit 0
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
