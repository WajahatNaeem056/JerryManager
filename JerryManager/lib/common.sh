log() { echo "$(date +%Y-%m-%d\ %H:%M:%S) [$1] $2"; }

die() { log "ERROR" "$1"; exit 1; }

download() {
    _dl_url="$1" _dl_oldpath="$PATH"
    PATH="/data/adb/magisk:/data/data/com.termux/files/usr/bin:$PATH"
    if command -v curl >/dev/null 2>&1; then
        curl --connect-timeout 10 -Ls "$_dl_url"
    else
        busybox wget -T 10 --no-check-certificate -qO- "$_dl_url"
    fi
    PATH="$_dl_oldpath"
    unset _dl_url _dl_oldpath
}

check_network() {
  _cn_endpoint="https://clients3.google.com/generate_204"
  _cn_oldpath="$PATH"
  PATH="/data/adb/magisk:/data/data/com.termux/files/usr/bin:$PATH"
  if command -v curl >/dev/null 2>&1; then
    curl --connect-timeout 5 -sI "$_cn_endpoint" >/dev/null 2>&1 && PATH="$_cn_oldpath" && return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -T 5 --spider "$_cn_endpoint" >/dev/null 2>&1 && PATH="$_cn_oldpath" && return 0
  fi
  PATH="$_cn_oldpath"
  return 1
}

check_module() {
  _cm_name="$1"
  if [ ! -d "/data/adb/modules/$_cm_name" ] && [ ! -d "/data/adb/modules_update/$_cm_name" ]; then
    log "ERROR" "Required module '$1' is not installed"
    return 1
  fi
  return 0
}

check_command() {
  _cc_name="$1"
  if ! command -v "$_cc_name" >/dev/null 2>&1; then
    log "ERROR" "Required command '$1' not found on this device"
    return 1
  fi
  return 0
}

check_prop() {
    _cp_name=$1 _cp_expected=$2
    _cp_value=$(resetprop "$_cp_name")
    [ -z "$_cp_value" ] || [ "$_cp_value" = "$_cp_expected" ] || resetprop -n "$_cp_name" "$_cp_expected"
    unset _cp_name _cp_expected _cp_value
}

contains_check_prop() {
    _ccp_name=$1 _ccp_contains=$2 _ccp_newval=$3
    case "$(resetprop "$_ccp_name")" in
        *"$_ccp_contains"*) resetprop -n "$_ccp_name" "$_ccp_newval"; unset _ccp_name _ccp_contains _ccp_newval; return 0 ;;
    esac
    unset _ccp_name _ccp_contains _ccp_newval
    return 1
}

ensure_dir() { mkdir -p "$1" 2>/dev/null; }

# ── Control Tab Functions ─────────────────────────────────────────────────────

hide_recovery_folders() {
    _hrf_backup="/data/adb/recovery_backups"
    _hrf_random="" _hrf_subdirs=0 _hrf_path=""

    for _hrf_folder in TWRP OrangeFox FOX PBRP PitchBlack Recovery; do
        _hrf_path="/sdcard/$_hrf_folder"
        [ ! -d "$_hrf_path" ] && continue

        if [ -f "$_hrf_path/.twrps" ]; then
            rm -f "$_hrf_path/.twrps" 2>/dev/null || {
                _hrf_random=$(head /dev/urandom 2>/dev/null | tr -dc A-Za-z0-9 | head -c 12)
                [ -z "$_hrf_random" ] && _hrf_random="recovery_${$}"
                mv "$_hrf_path" "/sdcard/$_hrf_random" 2>/dev/null
                continue
            }
        fi

        _hrf_subdirs=$(find "$_hrf_path" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        if [ "$_hrf_subdirs" -gt 0 ]; then
            mkdir -p "$_hrf_backup" 2>/dev/null
            mv "$_hrf_path" "$_hrf_backup/" 2>/dev/null
        else
            rm -rf "$_hrf_path" 2>/dev/null
        fi
    done
    unset _hrf_backup _hrf_random _hrf_subdirs _hrf_path _hrf_folder
}

apply_boot_hardening() {
    settings put global development_settings_enabled 0
    settings put global adb_enabled 0
    settings put global oem_unlock_allowed 0
    settings put global adb_wifi_enabled 0
    settings put global adb_wifi_port -1
    resetprop --delete persist.service.adb.enable 2>/dev/null || true
    resetprop --delete persist.service.debuggable 2>/dev/null || true
    resetprop -n persist.sys.developer_options 0
    if [ "$(toybox cat /sys/fs/selinux/enforce 2>/dev/null)" = "0" ]; then
        chmod 640 /sys/fs/selinux/enforce 2>/dev/null || true
        chmod 440 /sys/fs/selinux/policy 2>/dev/null || true
    fi
}

block_rom_spoof_engines() {
    _brs_gate=false
    resetprop 2>/dev/null | grep -qE 'persist\.sys\.(pihooks|entryhooks|pixelprops)' && _brs_gate=true
    [ "$_brs_gate" = "false" ] && unset _brs_gate && return 0

    for _brs_hook in persist.sys.pihooks.first_api_level persist.sys.pihooks.security_patch; do
        resetprop 2>/dev/null | grep -q "$_brs_hook" || resetprop "$_brs_hook" "" 2>/dev/null || true
    done
    unset _brs_hook

    while IFS='|' read -r _brs_prop _brs_val; do
        resetprop "$_brs_prop" "$_brs_val" 2>/dev/null || true
    done << MAP
persist.sys.pihooks.disable.gms_props|true
persist.sys.pihooks.disable.gms_key_attestation_block|true
persist.sys.entryhooks_enabled|false
persist.sys.pixelprops.gms|false
persist.sys.pixelprops.gapps|false
persist.sys.pixelprops.google|false
persist.sys.pixelprops.pi|false
MAP
    unset _brs_gate _brs_prop _brs_val
}

disable_bootloader_spoofer() {
    if command -v cmd >/dev/null 2>&1; then
        if pm list packages 2>/dev/null | grep -q "es.chiteroman.bootloaderspoofer"; then
            cmd package uninstall --user 0 "es.chiteroman.bootloaderspoofer" >/dev/null 2>&1 || true
        fi
    else
        for _pkg in es.chiteroman.bootloaderspoofer; do
            if grep -q "$_pkg" /data/system/packages.list 2>/dev/null; then
                timeout 5 pm uninstall --user 0 "$_pkg" >/dev/null 2>&1 || true
            fi
        done
        unset _pkg
        _wpp_xml="/data/data/com.wmods.wppenhacer/shared_prefs/com.wmods.wppenhacer_preferences.xml"
        if [ -f "$_wpp_xml" ] && grep -q 'name="bootloader_spoofer" value="true"' "$_wpp_xml" 2>/dev/null; then
            sed -i 's/\(name="bootloader_spoofer" value=\)"true"/\1"false"/' "$_wpp_xml" 2>/dev/null || true
        fi
        unset _wpp_xml
    fi
}
