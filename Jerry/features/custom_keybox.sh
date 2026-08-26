#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/keystore.sh"

log "CUSTOM_KEYBOX" "Start"

resolve_keystore_backend

CUSTOM_KEYBOX="$MODDIR/../custom_keybox.xml"

if [ ! -f "$CUSTOM_KEYBOX" ]; then
  log "CUSTOM_KEYBOX" "Error: No custom_keybox.xml found in module directory"
  log "CUSTOM_KEYBOX" "Please place your keybox.xml as custom_keybox.xml in the module folder"
  exit 1
fi

if [ "$KEYSTORE_BACKEND" = "none" ]; then
  log "CUSTOM_KEYBOX" "Error: No active keystore backend found (Tricky Store / OhMyKeymint)"
  exit 1
fi

ensure_dir "$KEYSTORE_DIR"

if [ "$KEYSTORE_BACKEND" = "trickystore" ] && [ -f "$KEYSTORE_KEYBOX" ] && [ ! -f "$BACKUP_FILE" ]; then
  cp "$KEYSTORE_KEYBOX" "$BACKUP_FILE"
  log "CUSTOM_KEYBOX" "Created backup of existing keybox"
fi

keystore_install_keybox "$CUSTOM_KEYBOX" || {
  log "CUSTOM_KEYBOX" "Error: Failed to copy custom_keybox.xml to $KEYSTORE_NAME"
  exit 1
}

log "CUSTOM_KEYBOX" "Custom keybox installed successfully ($KEYSTORE_NAME)"
log "CUSTOM_KEYBOX" "Finish"
exit 0
