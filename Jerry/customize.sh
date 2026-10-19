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

mkdir -p "$JERRYMANAGER_CONFIG_DIR" 2>/dev/null

resolve_keystore_backend
ui_print "- Keystore backend: $KEYSTORE_NAME"

# Purge known-conflicting modules (PIF handled separately, so not listed here)
PURGE_IDS="Yurikey xiaocaiye safetynet-fix vbmeta-fixer integrity_box \
SukiSU_module Reset_BootHash Tricky_store-bm Hide_Bootloader ShamikoManager \
extreme_hide_root Tricky_Store-xiaoyi tricky_store_assistant \
extreme_hide_bootloader wjw_hiderootauxiliarymod Yamabukiko TA_utl .TA_utl"
_purged=0
for _pid in $PURGE_IDS; do
  [ -d "/data/adb/modules/$_pid" ] || continue
  rm -rf "/data/adb/modules/$_pid"
  ui_print "- Purged conflicting module: $_pid"
  _purged=$((_purged + 1))
done
unset _pid PURGE_IDS
[ "$_purged" -eq 0 ] && ui_print "- No conflicting modules found"
unset _purged

if [ -d "/data/adb/modules/jerrykey" ]; then
  touch /data/adb/modules/jerrykey/remove
  ui_print "- Removed outdated module (lowercase 'jerrykey')"
fi

# ---- Built-in Play Integrity Fix (INJECT) ----
ui_print "- Built-in Play Integrity Fix (INJECT) included"

# Zygisk is required for injection; warn only, the rest of Jerry works without it
if ! find /data/adb/modules /data/adb/modules_update -name "libzygisk.so" 2>/dev/null | grep -q . \
   && [ ! -d /data/adb/magisk ]; then
  ui_print "! Zygisk not found. Install Zygisk Next / ReZygisk (or enable Zygisk in Magisk)"
  ui_print "! Built-in PIF will not work until Zygisk is active"
fi

# A standalone PIF/Fork would inject twice into GMS (pif.prop is shared and kept)
if [ -d /data/adb/modules/playintegrityfix ]; then
  touch /data/adb/modules/playintegrityfix/remove 2>/dev/null
  ui_print "- Standalone Play Integrity Fix/Fork found: scheduled for removal on reboot"
fi

# Leftovers from older PIF versions, and a script-only flag the UI can no longer clear
for _dir in /data/user_de/0/com.google.android.gms /data/data/com.google.android.gms \
            /data/user_de/0/com.android.vending /data/data/com.android.vending; do
  rm -f "$_dir/libinject.so" "$_dir/classes.dex" "$_dir/pif.prop" 2>/dev/null
done
rm -f /data/adb/pif_script_only 2>/dev/null
unset _dir

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
                  if [ "$KEYSTORE_BACKEND" != "none" ] && [ -z "$(find_keybox_backup "$KEYSTORE_BACKEND")" ] && ! grep -q "jerryroot" "$KEYSTORE_KEYBOX" 2>/dev/null; then
                      ui_print "- Previous keybox was not installed by Jerry Keybox."
                      ui_print "- Creating a backup keybox..."
                      cp "$KEYSTORE_KEYBOX" "$KEYSTORE_BACKUP"
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
    if [ "$KEYSTORE_BACKEND" != "none" ] && [ -f "$KEYSTORE_KEYBOX" ] && [ -z "$(find_keybox_backup "$KEYSTORE_BACKEND")" ]; then
      cp "$KEYSTORE_KEYBOX" "$KEYSTORE_BACKUP"
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

if [ -d "/data/adb/modules/Jerrykey" ] && ! grep -q "^id=Jerrykey$" "/data/adb/modules/Jerrykey/module.prop" 2>/dev/null; then
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

if [ -d "/data/adb/modules/Jerrykey" ] && grep -q "^id=Jerrykey$" "/data/adb/modules/Jerrykey/module.prop" 2>/dev/null; then
  if touch "/data/adb/modules/Jerrykey/remove" 2>/dev/null; then
    ui_print "- Migrated from Jerrykey to JerryManager"
    ui_print "- Old module scheduled for removal on reboot"
  else
    ui_print "- Warning: Could not schedule old Jerrykey module for removal"
    ui_print "- Please remove the old 'Jerrykey' module manually"
  fi
fi

return 0
