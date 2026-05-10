#!/system/bin/sh
MODDIR="${0%/*}"
MODDIR="${MODDIR%/*}"
MODDIR="${MODDIR%/*}"
. "$MODDIR/lib/common.sh"

OUT="$MODDIR/webroot/json/trace_scan.json"
mkdir -p "$(dirname "$OUT")"

# ── Helper ────────────────────────────────────────────────────────────────────
_bool() { [ "$1" = "true" ] && echo "true" || echo "false"; }

# ── 1. Magisk Binary ──────────────────────────────────────────────────────────
# Real check: does the magisk binary actually exist and respond?
_magisk_safe=true
if command -v magisk >/dev/null 2>&1; then
  _magisk_safe=false
elif [ -f "/sbin/magisk" ] || [ -f "/system/bin/magisk" ] || [ -f "/system/xbin/magisk" ]; then
  _magisk_safe=false
fi
log "TRACE" "magisk_binary: safe=$_magisk_safe"

# ── 2. Su Binary ──────────────────────────────────────────────────────────────
_su_safe=true
for _p in /sbin/su /system/bin/su /system/xbin/su /su/bin/su /data/adb/su; do
  if [ -f "$_p" ]; then
    _su_safe=false
    break
  fi
done
# Also check if 'su' resolves in PATH (excludes common safe symlinks)
if $_su_safe && command -v su >/dev/null 2>&1; then
  _su_path=$(command -v su 2>/dev/null)
  # /system/bin/su exists on some stock ROMs as a stub — check if it's executable and real
  if [ -x "$_su_path" ] && [ "$(stat -c '%s' "$_su_path" 2>/dev/null || echo 0)" -gt 1024 ]; then
    _su_safe=false
  fi
fi
log "TRACE" "su_binary: safe=$_su_safe"

# ── 3. LSPosed Trace (ODEX) ───────────────────────────────────────────────────
_lsposed_safe=true
for _p in \
  "/data/adb/lspd" \
  "/data/adb/modules/zygisk_lsposed" \
  "/data/adb/modules/lsposed" \
  "/system/framework/lspd.odex" \
  "/system/framework/lsposed.odex"; do
  if [ -e "$_p" ]; then
    _lsposed_safe=false
    break
  fi
done
# Check running LSPosed daemon
if $_lsposed_safe && [ -f "/proc/$(cat /data/adb/lspd/pid 2>/dev/null)/status" ] 2>/dev/null; then
  _lsposed_safe=false
fi
log "TRACE" "lsposed_odex: safe=$_lsposed_safe"

# ── 4. Developer Options ──────────────────────────────────────────────────────
# Real source: Settings.Global.DEVELOPMENT_SETTINGS_ENABLED (settings command)
_dev_safe=true
_dev_val=$(settings get global development_settings_enabled 2>/dev/null || echo "")
if [ "$_dev_val" = "1" ]; then
  _dev_safe=false
elif [ -z "$_dev_val" ]; then
  # Fallback: check if adbd is running (dev options must be on for ADB)
  _adbd_check=$(getprop init.svc.adbd 2>/dev/null || echo "")
  [ "$_adbd_check" = "running" ] && _dev_safe=false
  # Fallback 2: persist.sys.development_settings
  _dev_persist=$(getprop persist.sys.development_settings 2>/dev/null || echo "")
  [ "$_dev_persist" = "1" ] && _dev_safe=false
fi
log "TRACE" "dev_options: safe=$_dev_safe (settings=$_dev_val)"

# ── 5. USB Debugging ──────────────────────────────────────────────────────────
# Real source: Settings.Global.ADB_ENABLED
_adb_safe=true
_adb_val=$(settings get global adb_enabled 2>/dev/null || echo "")
if [ "$_adb_val" = "1" ]; then
  _adb_safe=false
fi
# Always check if adbd daemon is actually running (most reliable)
_adbd_svc=$(getprop init.svc.adbd 2>/dev/null || echo "")
if [ "$_adbd_svc" = "running" ]; then
  _adb_safe=false
fi
# Also check wireless ADB
_adb_tcp=$(getprop service.adb.tcp.port 2>/dev/null || echo "")
if [ -n "$_adb_tcp" ] && [ "$_adb_tcp" != "-1" ] && [ "$_adb_tcp" != "0" ]; then
  _adb_safe=false
fi
log "TRACE" "adb_enabled: safe=$_adb_safe (settings=$_adb_val adbd=$_adbd_svc tcp=$_adb_tcp)"

# ── 6. Bootloader State ───────────────────────────────────────────────────────
# Primary: ro.boot.flash.locked (1=locked=safe) — hardware fuse register
# Fallback: ro.boot.verifiedbootstate (green/yellow=safe)
# Never fake a default — report what the device actually says
_boot_safe=true
_flash_locked=$(getprop ro.boot.flash.locked 2>/dev/null || echo "")
if [ -n "$_flash_locked" ]; then
  [ "$_flash_locked" = "1" ] && _boot_safe=true || _boot_safe=false
else
  _vbs=$(getprop ro.boot.verifiedbootstate 2>/dev/null || echo "")
  if [ -n "$_vbs" ]; then
    case "$_vbs" in
      green|yellow) _boot_safe=true ;;
      orange|red)   _boot_safe=false ;;
      *)            _boot_safe=false ;;  # unknown = flag it
    esac
  else
    # Last resort: ro.secureboot.lockstate
    _lockstate=$(getprop ro.secureboot.lockstate 2>/dev/null || echo "")
    [ "$_lockstate" = "locked" ] && _boot_safe=true || _boot_safe=false
  fi
fi
log "TRACE" "bootloader: safe=$_boot_safe flash.locked=$_flash_locked"

# ── 7. SELinux Enforcing ──────────────────────────────────────────────────────
# PRIMARY: /sys/fs/selinux/enforce — direct kernel interface (1=enforcing=safe)
_selinux_safe=true
if [ -f "/sys/fs/selinux/enforce" ]; then
  _enforce=$(cat /sys/fs/selinux/enforce 2>/dev/null || echo "1")
  [ "$_enforce" = "0" ] && _selinux_safe=false
elif [ -f "/sys/fs/selinux/status" ]; then
  # Some devices use /sys/fs/selinux/status
  _status=$(cat /sys/fs/selinux/status 2>/dev/null | head -1 || echo "")
  echo "$_status" | grep -q "permissive" && _selinux_safe=false
else
  # Fallback: ro.boot.selinux prop
  _selinux_prop=$(getprop ro.boot.selinux 2>/dev/null || echo "enforcing")
  [ "$_selinux_prop" = "permissive" ] && _selinux_safe=false
fi
log "TRACE" "selinux: safe=$_selinux_safe"

# ── 8. ro.debuggable ─────────────────────────────────────────────────────────
# Build-time prop: 0=safe, 1=debuggable build (engineering/userdebug)
_debuggable_safe=true
_dbg=$(getprop ro.debuggable 2>/dev/null || echo "0")
[ "$_dbg" = "1" ] && _debuggable_safe=false
log "TRACE" "debuggable: safe=$_debuggable_safe (value=$_dbg)"

# ── 9. Build Type ─────────────────────────────────────────────────────────────
# ro.build.type: user=safe, userdebug/eng=unsafe
_buildtype_safe=true
_btype=$(getprop ro.build.type 2>/dev/null || echo "user")
[ "$_btype" != "user" ] && _buildtype_safe=false
log "TRACE" "build_type: safe=$_buildtype_safe (value=$_btype)"

# ── Write JSON ────────────────────────────────────────────────────────────────
_ts=$(date +%s)
cat <<JSON > "$OUT"
{
  "magisk_binary": $(_bool $_magisk_safe),
  "su_binary":     $(_bool $_su_safe),
  "lsposed_odex":  $(_bool $_lsposed_safe),
  "dev_options":   $(_bool $_dev_safe),
  "adb_enabled":   $(_bool $_adb_safe),
  "bootloader":    $(_bool $_boot_safe),
  "selinux":       $(_bool $_selinux_safe),
  "debuggable":    $(_bool $_debuggable_safe),
  "build_type":    $(_bool $_buildtype_safe),
  "timestamp":     $_ts
}
JSON

log "TRACE" "Done. Output: $OUT"
unset _magisk_safe _su_safe _lsposed_safe _dev_safe _adb_safe
unset _boot_safe _selinux_safe _debuggable_safe _buildtype_safe
unset _dev_val _adb_val _adbd_svc _flash_locked _vbs _lockstate
unset _enforce _selinux_prop _dbg _btype _ts _p _su_path
