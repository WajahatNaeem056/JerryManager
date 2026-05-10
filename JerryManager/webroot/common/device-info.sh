#!/system/bin/sh
MODDIR="${0%/*}"
MODDIR="${MODDIR%/*}"
MODDIR="${MODDIR%/*}"
. "$MODDIR/lib/common.sh"

INFO_PATH="$MODDIR/webroot/json/info.json"

_android_ver=$(getprop ro.build.version.release)
_kernel_ver=$(uname -r)
_version=$(grep '^version=' "$MODDIR/module.prop" | cut -d'=' -f2)

# Pre-fetch all version strings once
# VERSION MAP (research confirmed from GitHub + real device test):
#   ksud 0.x.x = Original KernelSU
#   ksud 3.x.x = KernelSU Next  (confirmed: ksud 3.2.0 = KSU Next)
#   ksud 4.x.x = SukiSU Ultra   (confirmed: v4.0.0, v4.1.0, v4.1.1)
_ksud_ver=$(ksud --version 2>/dev/null || ksud version 2>/dev/null || echo "")
_apd_ver=$(apd --version 2>/dev/null || apd version 2>/dev/null || echo "")
_ksu_prop=$(getprop "ro.kernelsu.version" 2>/dev/null || echo "")
_suki_env=$(printenv KSU_SUKISU 2>/dev/null || echo "")
_ksud_major=$(echo "$_ksud_ver" | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d'.' -f1)

_root_type="Unknown"

# APatch family (/data/adb/ap)
# Confirmed marker: /data/adb/ap/bin/busybox (official APatch docs)
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

# KernelSU family (/data/adb/ksu)
elif [ -d "/data/adb/ksu" ]; then

  # ReSukiSU - check FIRST (SukiSU fork, may share suki markers)
  _is_resuki=false
  echo "$_ksud_ver" | grep -qi "resuki"                             && _is_resuki=true
  echo "$_ksu_prop" | grep -qi "resuki"                             && _is_resuki=true
  [ -f "/data/adb/ksu/.resukisu" ]                                  && _is_resuki=true
  [ -f "/data/adb/ksu/resukisu" ]                                   && _is_resuki=true
  getprop "ro.resukisu.version" 2>/dev/null | grep -q "."           && _is_resuki=true
  pm list packages 2>/dev/null | grep -qi "resukisu"                && _is_resuki=true

  # SukiSU Ultra - version 4.x + KSU_SUKISU env + .dynamic_sign
  _is_suki=false
  [ -n "$_ksud_major" ] && [ "$_ksud_major" -ge 4 ] 2>/dev/null    && _is_suki=true
  [ -n "$_suki_env" ]                                               && _is_suki=true
  [ -f "/data/adb/ksu/.dynamic_sign" ]                              && _is_suki=true
  [ -f "/data/adb/ksu/.sukisu" ]                                    && _is_suki=true
  [ -f "/data/adb/ksu/sukisu" ]                                     && _is_suki=true
  [ -f "/data/adb/ksu/.sukisu_ultra" ]                              && _is_suki=true
  echo "$_ksud_ver" | grep -qi "suki"                               && _is_suki=true
  echo "$_ksu_prop" | grep -qi "suki"                               && _is_suki=true
  getprop "ro.sukisu.version" 2>/dev/null | grep -q "."             && _is_suki=true
  [ "$(getprop ro.boot.sukisu 2>/dev/null)" = "1" ]                 && _is_suki=true
  [ -f "/sys/module/kernelsu/parameters/sukisu" ]                   && _is_suki=true
  pm list packages 2>/dev/null | grep -qi "sukisu"                  && _is_suki=true

  # KernelSU Next - only detect via explicit markers, not version number alone
  _is_next=false
  echo "$_ksud_ver" | grep -qi "next"                               && _is_next=true
  echo "$_ksu_prop" | grep -qi "next"                               && _is_next=true
  # NOTE: expected_manager_size removed - exists in original KSU too (false positive)
  [ -f "/data/adb/ksu/.next" ]                                      && _is_next=true
  [ -f "/data/adb/ksu/next" ]                                       && _is_next=true
  getprop "ro.kernelsu.next.version" 2>/dev/null | grep -q "."     && _is_next=true
  pm list packages 2>/dev/null | grep -qi "kernelsu.next"           && _is_next=true

  # WildKernel
  _is_wild=false
  echo "$_ksud_ver" | grep -qi "wild"                               && _is_wild=true
  echo "$_ksu_prop" | grep -qi "wild"                               && _is_wild=true
  [ -f "/data/adb/ksu/.wildkernel" ]                                && _is_wild=true
  [ -f "/data/adb/ksu/wildkernel" ]                                 && _is_wild=true
  getprop "ro.wildkernel.version" 2>/dev/null | grep -q "."         && _is_wild=true
  pm list packages 2>/dev/null | grep -qi "wildkernel\|wild_ksu\|wildksu" && _is_wild=true

  # Final decision - priority order matters
  if   [ "$_is_resuki" = "true" ]; then _root_type="ReSukiSU"
  elif [ "$_is_suki"   = "true" ]; then _root_type="SukiSU-Ultra"
  elif [ "$_is_next"   = "true" ]; then _root_type="KernelSU-Next"
  elif [ "$_is_wild"   = "true" ]; then _root_type="WildKernel"
  else                                   _root_type="KernelSU"
  fi

  unset _is_resuki _is_suki _is_next _is_wild

# Magisk family (/data/adb/magisk)
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

# Output JSON
cat <<EOF > "$INFO_PATH"
{
  "android": "$_android_ver",
  "kernel": "$_kernel_ver",
  "root": "$_root_type",
  "version": "$_version"
}
EOF
unset _android_ver _kernel_ver _root_type _version
