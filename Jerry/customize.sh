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

# Ask whether to install the built-in PIF: Vol+ = yes, Vol- = no.
# Default is yes: no key within 5 seconds, or no getevent/timeout, installs it.
_jm_ask_pif() {
  if ! { command -v getevent >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; }; then
    ui_print "- Key input unavailable: installing built-in PIF (default)"
    return 0
  fi
  ui_print "- Install built-in PIF?"
  ui_print "  Vol+ = Yes, install"
  ui_print "  Vol- = No, skip"
  ui_print "  Default: Yes (5 seconds)"
  _ap_end=$(( $(date +%s) + 5 ))
  while [ "$(date +%s)" -lt "$_ap_end" ]; do
    _ap_key=$(timeout 1 getevent -lc 1 2>/dev/null | grep -m1 'KEY_VOLUME.* DOWN')
    case "$_ap_key" in
      *VOLUMEUP*)   unset _ap_end _ap_key; ui_print "- Vol+ pressed: installing built-in PIF"; return 0 ;;
      *VOLUMEDOWN*) unset _ap_end _ap_key; ui_print "- Vol- pressed: skipping built-in PIF"; return 1 ;;
    esac
  done
  unset _ap_end _ap_key
  ui_print "- No key pressed: installing built-in PIF (default)"
  return 0
}

_jm_pif() {
  if ! _jm_ask_pif; then
    rm -rf "$MODPATH/zygisk" "$MODPATH/dex/classes.dex" "$MODPATH/pif.prop" 2>/dev/null
    ui_print "- Built-in PIF skipped. To add it later, flash Jerry again and press Vol+"
    return 0
  fi

  if [ -f "$MODPATH/dex/classes.dex" ] && ls "$MODPATH"/zygisk/*.so >/dev/null 2>&1; then
    ui_print "- Built-in PIF included"
  else
    ui_print "! Built-in PIF files missing from this zip"
  fi

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
  return 0
}

if [ ! -d "/data/adb/modules/tricky_store" ] && [ ! -d "/data/adb/modules_update/tricky_store" ] && \
   [ ! -d "/data/adb/modules/oh_my_keymint" ] && [ ! -d "/data/adb/modules_update/oh_my_keymint" ]; then
  ui_print "- Error: No supported keystore backend is installed"
  ui_print "- Please install Tricky Store or OhMyKeymint first."
  ui_print "- After installing one of them, install the keybox from the action button or WebUI."
  _jm_pif
  return 0
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

_jm_pif

mkdir -p "$MODPATH/webroot/json"
RUNTIME_DIR=$(echo "$MODPATH" | sed 's|/modules_update/|/modules/|')
cat > "$MODPATH/webroot/json/module_paths.json" <<JSON
{"MODDIR": "$RUNTIME_DIR"}
JSON
unset RUNTIME_DIR

if [ -f "$TMPDIR/webroot/common/device-info.sh" ]; then
    sh "$TMPDIR/webroot/common/device-info.sh"
elif [ -f "$MODPATH/webroot/common/device-info.sh" ]; then
    sh "$MODPATH/webroot/common/device-info.sh"
fi

return 0
