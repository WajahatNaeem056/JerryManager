#!/system/bin/sh
MODDIR="${0%/*}"
MODDIR="${MODDIR%/*}"
MODDIR="${MODDIR%/*}"
. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/paths.sh"
. "$MODDIR/lib/config_env.sh"

INFO_PATH="$MODDIR/webroot/json/info.json"

# _escape_json from common.sh handles backslashes and quotes
_android_ver=$(_escape_json "$(getprop ro.build.version.release)")
_kernel_ver=$(_escape_json "$(uname -r)")
_version=$(_escape_json "$(grep '^version=' "$MODDIR/module.prop" | cut -d'=' -f2)")

# ROM identity — prefer the value cached at boot (before rom_fingerprint.sh
# stripped identifying props). If no cache exists yet (e.g. first run before
# a reboot), fall back to a live check — best-effort, may be less accurate
# once spoofing has already run this session.
_rom_status=$(cfg_get "cached_rom_status" "")
if [ -z "$_rom_status" ]; then
    . "$MODDIR/lib/rom_detect.sh"
    _rom_status="$(detect_rom)"
fi
_rom_status=$(_escape_json "$_rom_status")

# Pre-fetch all version strings once
_ksud_ver=$(ksud --version 2>/dev/null || ksud version 2>/dev/null || echo "")
_apd_ver=$(apd --version 2>/dev/null || apd version 2>/dev/null || echo "")
_ksu_prop=$(getprop "ro.kernelsu.version" 2>/dev/null || echo "")
_suki_env=$(printenv KSU_SUKISU 2>/dev/null || echo "")
_ksud_major=$(echo "$_ksud_ver" | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d'.' -f1)

_root_type="Unknown"

# APatch family
if [ -d "/data/adb/ap" ] || [ -f "/data/adb/ap/bin/busybox" ]; then
  _is_folk=false
  echo "$_apd_ver"  | grep -qi "folk"                               && _is_folk=true
  [ -f "/data/adb/ap/.folkpatch" ]                                  && _is_folk=true
  getprop "ro.folkpatch.version" 2>/dev/null | grep -q "."          && _is_folk=true
  pm list packages 2>/dev/null | grep -qi "folkpatch"               && _is_folk=true

  if [ "$_is_folk" = "true" ]; then
    _root_type="FolkPatch"
  else
    _root_type="APatch"
  fi
  unset _is_folk

# KernelSU family
elif [ -d "/data/adb/ksu" ]; then
  _is_resuki=false
  echo "$_ksud_ver" | grep -qi "resuki"                             && _is_resuki=true
  echo "$_ksu_prop" | grep -qi "resuki"                             && _is_resuki=true
  [ -f "/data/adb/ksu/.resukisu" ]                                  && _is_resuki=true
  getprop "ro.resukisu.version" 2>/dev/null | grep -q "."           && _is_resuki=true
  pm list packages 2>/dev/null | grep -qi "resukisu"                && _is_resuki=true

  _is_suki=false
  [ -n "$_ksud_major" ] && [ "$_ksud_major" -ge 4 ] 2>/dev/null    && _is_suki=true
  [ -n "$_suki_env" ]                                               && _is_suki=true
  [ -f "/data/adb/ksu/.dynamic_sign" ]                              && _is_suki=true
  [ -f "/data/adb/ksu/.sukisu" ]                                    && _is_suki=true
  echo "$_ksud_ver" | grep -qi "suki"                               && _is_suki=true
  echo "$_ksu_prop" | grep -qi "suki"                               && _is_suki=true
  getprop "ro.sukisu.version" 2>/dev/null | grep -q "."             && _is_suki=true
  [ "$(getprop ro.boot.sukisu 2>/dev/null)" = "1" ]                 && _is_suki=true
  pm list packages 2>/dev/null | grep -qi "sukisu"                  && _is_suki=true

  _is_next=false
  echo "$_ksud_ver" | grep -qi "next"                               && _is_next=true
  echo "$_ksu_prop" | grep -qi "next"                               && _is_next=true
  [ -f "/data/adb/ksu/.next" ]                                      && _is_next=true
  getprop "ro.kernelsu.next.version" 2>/dev/null | grep -q "."     && _is_next=true
  pm list packages 2>/dev/null | grep -qi "kernelsu.next"           && _is_next=true

  _is_wild=false
  echo "$_ksud_ver" | grep -qi "wild"                               && _is_wild=true
  [ -f "/data/adb/ksu/.wildkernel" ]                                && _is_wild=true
  getprop "ro.wildkernel.version" 2>/dev/null | grep -q "."         && _is_wild=true
  pm list packages 2>/dev/null | grep -qi "wildkernel\|wild_ksu\|wildksu" && _is_wild=true

  if   [ "$_is_resuki" = "true" ]; then _root_type="ReSukiSU"
  elif [ "$_is_suki"   = "true" ]; then _root_type="SukiSU-Ultra"
  elif [ "$_is_next"   = "true" ]; then _root_type="KernelSU-Next"
  elif [ "$_is_wild"   = "true" ]; then _root_type="WildKernel"
  else                                   _root_type="KernelSU"
  fi
  unset _is_resuki _is_suki _is_next _is_wild

# Magisk family
elif [ -d "/data/adb/magisk" ] || [ -f "/data/adb/magisk.db" ]; then
  _magisk_ver=$(magisk --version 2>/dev/null || echo "")
  if   echo "$_magisk_ver" | grep -qi "kitsune\|husky"; then _root_type="Magisk-Kitsune"
  elif echo "$_magisk_ver" | grep -qi "delta";           then _root_type="Magisk-Delta"
  elif echo "$_magisk_ver" | grep -qi "alpha";           then _root_type="Magisk-Alpha"
  else                                                        _root_type="Magisk"
  fi
  unset _magisk_ver
fi

unset _ksud_ver _apd_ver _ksu_prop _suki_env _ksud_major

# Output JSON — all string values safely escaped
cat <<EOF > "$INFO_PATH"
{
  "android": "$_android_ver",
  "kernel": "$_kernel_ver",
  "root": "$(_escape_json "$_root_type")",
  "rom": "$_rom_status",
  "version": "$_version"
}
EOF
unset _android_ver _kernel_ver _root_type _rom_status _version
