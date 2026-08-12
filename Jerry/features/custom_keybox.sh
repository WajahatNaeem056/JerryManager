#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"

log "CUSTOM_KEYBOX" "Start"

CUSTOM_KEYBOX="$MODDIR/../custom_keybox.xml"

if [ ! -f "$CUSTOM_KEYBOX" ]; then
  log "CUSTOM_KEYBOX" "Error: No custom_keybox.xml found in module directory"
  log "CUSTOM_KEYBOX" "Please place your keybox.xml as custom_keybox.xml in the module folder"
  exit 1
fi

if [ ! -d "$TRICKY_DIR" ]; then
  log "CUSTOM_KEYBOX" "Error: Tricky Store data directory not found"
  exit 1
fi

mkdir -p "$TRICKY_DIR"

if [ -f "$TARGET_FILE" ] && [ ! -f "$BACKUP_FILE" ]; then
  cp "$TARGET_FILE" "$BACKUP_FILE"
  log "CUSTOM_KEYBOX" "Created backup of existing keybox"
fi

cp "$CUSTOM_KEYBOX" "$TARGET_FILE" || {
  log "CUSTOM_KEYBOX" "Error: Failed to copy custom_keybox.xml to Tricky Store"
  exit 1
}

log "CUSTOM_KEYBOX" "Custom keybox installed successfully"
log "CUSTOM_KEYBOX" "Finish"
exit 0
