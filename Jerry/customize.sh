#!/system/bin/sh
. "$MODPATH/lib/common.sh"
. "$MODPATH/lib/urls.sh"
. "$MODPATH/lib/paths.sh"

ui_print ""
ui_print "*********************************"
ui_print "*****Jerry Manager Installer******"
ui_print "*********************************"
ui_print ""

mkdir -p "$JERRYKEY_CONFIG_DIR" 2>/dev/null

if [ -d "/data/adb/modules/jerrykey" ]; then
  touch /data/adb/modules/jerrykey/remove
  ui_print "- Removed outdated module (lowercase 'jerrykey')"
fi

if [ ! -d "/data/adb/modules/tricky_store" ] && [ ! -d "/data/adb/modules_update/tricky_store" ]; then
  ui_print "- Error: Tricky Store dependency is not installed"
  ui_print "- Please install Tricky Store first."
  ui_print "- After installing Tricky Store, install the keybox from the action button or WebUI."
  return 0
fi

if [ -d "/data/adb/Jerrykey/bin" ]; then
  rm -rf /data/adb/Jerrykey/bin
  ui_print "- Cleaned up old binary directory"
fi

DECODE_FILE="$TRICKY_DIR/keybox_decode"
TEMP_FILE="$MODPATH/keybox.tmp"

if check_network; then
  ui_print "- Fetching remote keybox..."
  download "$KEYBOX_URL" > "$TEMP_FILE"

  if [ ! -f "$TEMP_FILE" ] || [ ! -s "$TEMP_FILE" ]; then
      ui_print "- Error: Keybox download failed. You can upload a keybox manually via the WebUI."
      rm -f "$TEMP_FILE"
  else
      mkdir -p "$TRICKY_DIR"

      if ! base64 -d "$TEMP_FILE" > "$DECODE_FILE" 2>/dev/null; then
          ui_print "- Error: Downloaded keybox is corrupted or invalid. Try again later."
          rm -f "$TEMP_FILE"
      else
          if [ -f "$TARGET_FILE" ]; then
              if cmp -s "$TARGET_FILE" "$DECODE_FILE"; then
                  ui_print "- Current keybox is already up to date. No changes needed."
                  rm -f "$TEMP_FILE" "$DECODE_FILE"
              else
                  if ! grep -q "jerryroot" "$TARGET_FILE" 2>/dev/null; then
                      ui_print "- Previous keybox was not installed by Jerry Keybox."
                      ui_print "- Creating a backup keybox..."
                      cp "$TARGET_FILE" "$BACKUP_FILE"
                  fi
                  mv "$DECODE_FILE" "$TARGET_FILE"
                  rm -f "$TEMP_FILE"
                  ui_print "- Keybox installed successfully"
              fi
          else
              ui_print "- No keybox found! Creating a new one..."
              mv "$DECODE_FILE" "$TARGET_FILE"
              rm -f "$TEMP_FILE"
              ui_print "- Keybox installed successfully"
          fi
      fi
  fi
else
  ui_print "- No internet connection detected."
  if [ -f "$MODPATH/keybox.xml" ]; then
    ui_print "- Installing bundled keybox (Offline)..."
    mkdir -p "$TRICKY_DIR"
    if [ -f "$TARGET_FILE" ] && [ ! -f "$BACKUP_FILE" ]; then
      cp "$TARGET_FILE" "$BACKUP_FILE"
      ui_print "- Backup of existing keybox created."
    fi
    cp "$MODPATH/keybox.xml" "$TARGET_FILE"
    ui_print "- Bundled keybox installed successfully!"
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
