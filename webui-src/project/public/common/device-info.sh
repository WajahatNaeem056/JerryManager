#!/system/bin/sh
MODDIR="${0%/*}"
MODDIR="${MODDIR%/*}"
MODDIR="${MODDIR%/*}"
. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/paths.sh"
. "$MODDIR/lib/config_env.sh"
. "$MODDIR/lib/keystore.sh"

INFO_PATH="$MODDIR/webroot/json/info.json"

resolve_keystore_backend

_android_ver=$(_escape_json "$(getprop ro.build.version.release)")
_version=$(_escape_json "$(grep '^version=' "$MODDIR/module.prop" | cut -d'=' -f2)")

# ROM and root are detected live once per boot: service.sh clears the cache at boot, the first WebUI open
# detects and saves them, and every later refresh in that boot only reads the cache (no ksud/pm).
_rom_status=$(cfg_get "cached_rom_status" "")
if [ -z "$_rom_status" ]; then
    . "$MODDIR/lib/rom_detect.sh"
    _rom_status="$(detect_rom)"
    [ -n "$_rom_status" ] && cfg_set "cached_rom_status" "$_rom_status"
fi
_rom_status=$(_escape_json "$_rom_status")

_root_type=$(cfg_get "cached_root_type" "")
if [ -z "$_root_type" ]; then
    . "$MODDIR/lib/root_detect.sh"
    _root_type="$(detect_root)"
    [ -n "$_root_type" ] && [ "$_root_type" != "Unknown" ] && cfg_set "cached_root_type" "$_root_type"
fi

cat <<EOF > "$INFO_PATH"
{
  "android": "$_android_ver",
  "root": "$(_escape_json "$_root_type")",
  "rom": "$_rom_status",
  "version": "$_version",
  "keystore_backend": "$(_escape_json "$KEYSTORE_NAME")"
}
EOF
write_state_snapshot

unset _android_ver _root_type _rom_status _version
