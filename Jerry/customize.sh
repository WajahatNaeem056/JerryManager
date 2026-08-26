#!/system/bin/sh
. "$MODPATH/lib/common.sh"
. "$MODPATH/lib/urls.sh"
. "$MODPATH/lib/paths.sh"
. "$MODPATH/lib/config_env.sh"
. "$MODPATH/lib/keystore.sh"

ui_print ""
ui_print "*********************************"
ui_print "*****Jerry Manager ******"
ui_print "*********************************"
ui_print ""

mkdir -p "$JERRYKEY_CONFIG_DIR" 2>/dev/null

resolve_keystore_backend
ui_print "- Keystore backend: $KEYSTORE_NAME"

if [ -d "/data/adb/modules/jerrykey" ]; then
  touch /data/adb/modules/jerrykey/remove
  ui_print "- Removed outdated module (lowercase 'jerrykey')"
fi

if [ ! -d "/data/adb/modules/tricky_store" ] && [ ! -d "/data/adb/modules_update/tricky_store" ] && \
   [ ! -d "/data/adb/modules/oh_my_keymint" ] && [ ! -d "/data/adb/modules_update/oh_my_keymint" ]; then
  ui_print "- Error: No supported keystore backend is installed"
  ui_print "- Please install Tricky Store or OhMyKeymint first."
  ui_print "- After installing one of them, install the keybox from the action button or WebUI."
  return 0
fi

if [ -d "/data/adb/Jerrykey/bin" ]; then
  rm -rf /data/adb/Jerrykey/bin
  ui_print "- Cleaned up old binary directory"
fi

DECODE_FILE="$MODPATH/keybox_decode"
TEMP_FILE="$MODPATH/keybox.tmp"

if check_network; then
  ui_print "- Fetching remote keybox..."
  download "$KEYBOX_URL" > "$TEMP_FILE"

  if [ ! -f "$TEMP_FILE" ] || [ ! -s "$TEMP_FILE" ]; then
      ui_print "- Error: Keybox download failed. You can upload a keybox manually via the WebUI."
      rm -f "$TEMP_FILE"
  else
      ensure_dir "$KEYSTORE_DIR"

      if ! base64 -d "$TEMP_FILE" > "$DECODE_FILE" 2>/dev/null; then
          ui_print "- Error: Downloaded keybox is corrupted or invalid. Try again later."
          rm -f "$TEMP_FILE"
      else
          if [ -f "$KEYSTORE_KEYBOX" ]; then
              if cmp -s "$KEYSTORE_KEYBOX" "$DECODE_FILE"; then
                  ui_print "- Current keybox is already up to date. No changes needed."
                  rm -f "$TEMP_FILE" "$DECODE_FILE"
              else
                  if [ "$KEYSTORE_BACKEND" = "trickystore" ] && ! grep -q "jerryroot" "$KEYSTORE_KEYBOX" 2>/dev/null; then
                      ui_print "- Previous keybox was not installed by Jerry Keybox."
                      ui_print "- Creating a backup keybox..."
                      cp "$KEYSTORE_KEYBOX" "$BACKUP_FILE"
                  fi
                  keystore_install_keybox "$DECODE_FILE"
                  rm -f "$TEMP_FILE" "$DECODE_FILE"
                  ui_print "- Keybox installed successfully ($KEYSTORE_NAME)"
              fi
          else
              ui_print "- No keybox found! Creating a new one..."
              keystore_install_keybox "$DECODE_FILE"
              rm -f "$TEMP_FILE" "$DECODE_FILE"
              ui_print "- Keybox installed successfully ($KEYSTORE_NAME)"
          fi
      fi
  fi
else
  ui_print "- No internet connection detected."
  if [ -f "$MODPATH/keybox.xml" ]; then
    ui_print "- Installing bundled keybox (Offline)..."
    ensure_dir "$KEYSTORE_DIR"
    if [ "$KEYSTORE_BACKEND" = "trickystore" ] && [ -f "$KEYSTORE_KEYBOX" ] && [ ! -f "$BACKUP_FILE" ]; then
      cp "$KEYSTORE_KEYBOX" "$BACKUP_FILE"
      ui_print "- Backup of existing keybox created."
    fi
    keystore_install_keybox "$MODPATH/keybox.xml"
    ui_print "- Bundled keybox installed successfully! ($KEYSTORE_NAME)"
  else
    ui_print "- No bundled keybox found. Use the Offline button in WebUI after reboot."
  fi
fi

mkdir -p "$MODPATH/webroot/json"
RUNTIME_DIR=$(echo "$MODPATH" | sed 's|/modules_update/|/modules/|')
cat > "$MODPATH/webroot/json/module_paths.json" <<JSON
{"MODDIR": "$RUNTIME_DIR"}
JSON
unset RUNTIME_DIR

if [ -d "/data/adb/modules/Jerrykey" ]; then
  if [ -d "/data/adb/modules/Jerrykey/Jerry" ] || [ -f "/data/adb/modules/Jerrykey/webroot/common/clear_all_detection_traces.sh" ] || [ -f "/data/adb/modules/Jerrykey/webroot/common/widevinel1.sh" ] || [ -f "/data/adb/modules/Jerrykey/webroot/common/boot_hash.sh" ]; then
    ui_print "- Detected outdated files from JerryKey v3"
    ui_print "- Cleaning up obsolete files..."
    rm -rf /data/adb/modules/Jerrykey 2>/dev/null
    ui_print "- Removed old JerryKey v3 module directory"
  fi
fi

if [ -f "$TMPDIR/webroot/common/device-info.sh" ]; then
    sh "$TMPDIR/webroot/common/device-info.sh"
elif [ -f "$MODPATH/webroot/common/device-info.sh" ]; then
    sh "$MODPATH/webroot/common/device-info.sh"
elif [ -f /data/adb/modules_update/Jerrykey/webroot/common/device-info.sh ]; then
    sh /data/adb/modules_update/Jerrykey/webroot/common/device-info.sh
elif [ -f /data/adb/modules/Jerrykey/webroot/common/device-info.sh ]; then
    sh /data/adb/modules/Jerrykey/webroot/common/device-info.sh
fi

return 0
