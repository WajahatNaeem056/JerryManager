#!/system/bin/sh
. "$MODPATH/lib/common.sh"
. "$MODPATH/lib/urls.sh"
. "$MODPATH/lib/paths.sh"
. "$MODPATH/lib/config_env.sh"
. "$MODPATH/lib/keystore.sh"

_jm_section() {
  ui_print ""
  ui_print "→ $1"
}

# ---------- Header ----------
_jm_ver=$(sed -n 's/^version=//p' "$MODPATH/module.prop" 2>/dev/null | head -n1 | sed 's/-g[0-9a-f]*$//')
ui_print ""
ui_print "*********************************"
ui_print "******  Jerry Manager $_jm_ver  ******"
ui_print "*********************************"
unset _jm_ver

mkdir -p "$JERRYMANAGER_CONFIG_DIR" 2>/dev/null

if [ ! -d /data/adb/modules/JerryManager ]; then
  for _ks_old in $TEESIM_MODULE_IDS $OMK_MODULE_IDS $TS_CONFLICT_IDS; do
    for _ks_d in "/data/adb/modules/$_ks_old" "/data/adb/modules_update/$_ks_old"; do
      [ -d "$_ks_d" ] || continue
      touch "$_ks_d/remove" 2>/dev/null
      ui_print "⚠ Existing keystore module $_ks_old found"
      ui_print "Removal scheduled on reboot"
    done
  done
  unset _ks_old _ks_d
fi

resolve_keystore_backend

# ---------- Keystore ----------
_jm_ts_fail() {
  if [ "$KEYSTORE_BUILTIN" = "1" ]; then abort "$1"; fi
  ui_print "⚠ Built-in Tricky Store OSS not prepared: $1"
}

_jm_install_ts() {
  case "$ARCH" in
    arm64) _ts_abi="arm64-v8a" ;;
    arm)   _ts_abi="armeabi-v7a" ;;
    x64)   _ts_abi="x86_64" ;;
    x86)   _ts_abi="x86" ;;
    *)     _jm_ts_fail "Unsupported architecture: $ARCH"; _ts_abi="" ;;
  esac
  if [ -n "$_ts_abi" ]; then
    if [ "$API" -lt 29 ]; then
      _jm_ts_fail "Unsupported SDK: $API (Tricky Store OSS needs Android 10+)"
    elif [ "$KSU" = true ] && [ "$KSU_VER_CODE" -lt 10670 ]; then
      _jm_ts_fail "Please update KernelSU and KernelSU Manager"
    elif [ ! -f "$MODPATH/ts/lib/$_ts_abi/libTrickyStoreOSS.so" ] || [ ! -f "$MODPATH/ts/lib/$_ts_abi/libinject.so" ]; then
      _jm_ts_fail "Tricky Store OSS files for $_ts_abi are missing from this zip"
    else
      [ "$KEYSTORE_BUILTIN" = "1" ] && ui_print "Built-in: Tricky Store OSS"
      ui_print "Platform: $ARCH • SDK $API"
      mv "$MODPATH/ts/lib/$_ts_abi/libTrickyStoreOSS.so" "$MODPATH/ts/libTrickyStoreOSS.so"
      mv "$MODPATH/ts/lib/$_ts_abi/libinject.so" "$MODPATH/ts/inject"
      rm -rf "$MODPATH/ts/lib"
      chmod 755 "$MODPATH/ts/daemon" "$MODPATH/ts/inject" "$MODPATH/ts/supervisor.sh"
    fi
  fi
  [ -f "$MODPATH/dex/duckd" ] && chmod 755 "$MODPATH/dex/duckd"

  ensure_dir "$TRICKY_DIR"
  [ -f "$TARGET_TXT" ] || touch "$TARGET_TXT"
  unset _ts_abi
}

_jm_section "Keystore"
_jm_install_ts
ui_print "Backend: $KEYSTORE_NAME"
if [ "$KEYSTORE_BUILTIN" != "1" ] && [ "$KEYSTORE_BACKEND" != "trickystore" ]; then
  ui_print "Detected external $KEYSTORE_NAME — built-in Tricky Store OSS stays off"
fi

# ---------- Keybox ----------
DECODE_FILE="$MODPATH/keybox_decode"
TEMP_FILE="$MODPATH/keybox.tmp"

_jm_section "Keybox"
if check_network; then
  ui_print "Fetching remote keybox..."
  download "$KEYBOX_URL" > "$TEMP_FILE"

  if [ ! -f "$TEMP_FILE" ] || [ ! -s "$TEMP_FILE" ]; then
      ui_print "✕ Keybox download failed"
      ui_print "Upload one manually via WebUI"
      rm -f "$TEMP_FILE"
  else
      ensure_dir "$KEYSTORE_DIR"

      if ! base64 -d "$TEMP_FILE" > "$DECODE_FILE" 2>/dev/null; then
          ui_print "✕ Downloaded keybox is corrupted or invalid"
          ui_print "Try again later"
          rm -f "$TEMP_FILE"
      else
          if [ -f "$KEYSTORE_KEYBOX" ]; then
              if cmp -s "$KEYSTORE_KEYBOX" "$DECODE_FILE"; then
                  ui_print "Status: up to date"
                  rm -f "$TEMP_FILE" "$DECODE_FILE"
              else
                  if [ "$KEYSTORE_BACKEND" != "none" ] && [ -z "$(find_keybox_backup "$KEYSTORE_BACKEND")" ] && ! keybox_is_jerry "$KEYSTORE_KEYBOX"; then
                      ui_print "Previous keybox: not from Jerry"
                      ui_print "Backup: created"
                      cp "$KEYSTORE_KEYBOX" "$KEYSTORE_BACKUP"
                  fi
                  keystore_install_keybox "$DECODE_FILE"
                  rm -f "$TEMP_FILE" "$DECODE_FILE"
                  ui_print "Status: installed • $KEYSTORE_NAME"
              fi
          else
              ui_print "No keybox found, creating new"
              keystore_install_keybox "$DECODE_FILE"
              rm -f "$TEMP_FILE" "$DECODE_FILE"
              ui_print "Status: installed • $KEYSTORE_NAME"
          fi
      fi
  fi
else
  ui_print "⚠ No internet connection"
  ui_print "Keybox not installed"
  ui_print "Install it later from the action button or WebUI"
fi

# ---------- PIF ----------
_jm_ask_pif() {
  if ! { command -v getevent >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; }; then
    ui_print "Key input unavailable, default Yes"
    return 0
  fi
  ui_print "Install built-in PIF?"
  ui_print "• Vol+ = Yes"
  ui_print "• Vol- = No"
  _ap_end=$(( $(date +%s) + 5 ))
  while [ "$(date +%s)" -lt "$_ap_end" ]; do
    _ap_key=$(timeout 1 getevent -lc 1 2>/dev/null | grep -m1 'KEY_VOLUME.* DOWN')
    case "$_ap_key" in
      *VOLUMEUP*)   unset _ap_end _ap_key; return 0 ;;
      *VOLUMEDOWN*) unset _ap_end _ap_key; return 1 ;;
    esac
  done
  unset _ap_end _ap_key
  ui_print "No key pressed, default Yes"
  return 0
}

_jm_pif_on=0

_jm_pif() {
  _jm_section "PIF"
  if ! _jm_ask_pif; then
    rm -rf "$MODPATH/zygisk" "$MODPATH/dex/classes.dex" "$MODPATH/pif.prop" 2>/dev/null
    ui_print "Built-in PIF: skipped"
    ui_print "To add it later, flash Jerry again and press Vol+"
    return 0
  fi

  if [ -f "$MODPATH/dex/classes.dex" ] && ls "$MODPATH"/zygisk/*.so >/dev/null 2>&1; then
    ui_print "Built-in PIF: included"
    _jm_pif_on=1
  else
    ui_print "⚠ Built-in PIF files missing from this zip"
  fi

  if [ -d /data/adb/modules/playintegrityfix ]; then
    touch /data/adb/modules/playintegrityfix/remove 2>/dev/null
    ui_print "⚠ Standalone PIF/Fork found"
    ui_print "Removal scheduled on reboot"
  fi

  for _dir in /data/user_de/0/com.google.android.gms /data/data/com.google.android.gms \
              /data/user_de/0/com.android.vending /data/data/com.android.vending; do
    rm -f "$_dir/libinject.so" "$_dir/classes.dex" "$_dir/pif.prop" 2>/dev/null
  done
  rm -f /data/adb/pif_script_only 2>/dev/null
  unset _dir
  return 0
}

# ---------- Zygisk (needed only when built-in PIF is installed) ----------
_jm_zygisk_info() {
  for _zid in zygisksu rezygisk; do
    _zp="/data/adb/modules/$_zid/module.prop"
    if [ -f "$_zp" ]; then
      _zn=$(sed -n 's/^name=//p' "$_zp" | head -n1)
      _zv=$(sed -n 's/^version=//p' "$_zp" | head -n1 | sed 's/ (.*)$//')
      echo "$_zn $_zv"
      unset _zid _zp _zn _zv
      return 0
    fi
  done
  unset _zid _zp
  return 1
}

_jm_zygisk() {
  _jm_section "Zygisk"
  if find /data/adb/modules /data/adb/modules_update -name "libzygisk.so" 2>/dev/null | grep -q . \
     || [ -d /data/adb/magisk ]; then
    _zinfo=$(_jm_zygisk_info)
    ui_print "Status: found"
    [ -n "$_zinfo" ] && ui_print "Module: $_zinfo"
    unset _zinfo
  else
    ui_print "⚠ Zygisk not found"
    ui_print "Install Zygisk Next / ReZygisk, or enable Zygisk in Magisk"
    ui_print "Built-in PIF will not work until Zygisk is active"
  fi
}

_jm_pif
[ "$_jm_pif_on" = 1 ] && _jm_zygisk

# ---------- WebUI paths ----------
mkdir -p "$MODPATH/webroot/json"
RUNTIME_DIR=$(echo "$MODPATH" | sed 's|/modules_update/|/modules/|')
cat > "$MODPATH/webroot/json/module_paths.json" <<JSON
{"MODDIR": "$RUNTIME_DIR"}
JSON
unset RUNTIME_DIR

if [ -f "$TMPDIR/webroot/common/device-info.sh" ]; then
    sh "$TMPDIR/webroot/common/device-info.sh" >/dev/null 2>&1
elif [ -f "$MODPATH/webroot/common/device-info.sh" ]; then
    sh "$MODPATH/webroot/common/device-info.sh" >/dev/null 2>&1
fi

ui_print ""
return 0
