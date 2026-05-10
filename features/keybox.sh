#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/urls.sh"

log "KEYBOX" "Start"

DECODE_FILE="$TRICKY_DIR/keybox_decode"
TEMP_FILE="$TRICKY_DIR/keybox.tmp"

# --- Custom Keybox Support ---
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
# --- End Custom Keybox ---

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

mv "$DECODE_FILE" "$TARGET_FILE" || { log "KEYBOX" "Error: Failed to move keybox"; exit 1; }
rm -f "$TEMP_FILE"
log "KEYBOX" "Keybox installed successfully"
log "KEYBOX" "Finish"
exit 0
