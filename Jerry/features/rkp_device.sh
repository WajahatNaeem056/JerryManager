#!/system/bin/sh
# Device RKP Issuer backend: rkp_device.sh status | provision [auto|v1|v2|v1-native]
# Exit: 0 ok, 2 unsupported arch, 21 provision failed, 22 keybox invalid, 23 install failed,
#       24 no keystore backend, 64 usage
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/rkp_device.sh"

case "$1" in
  status)
    rkp_device_status
    exit $?
    ;;
  provision)
    log "RKP_DEVICE" "Start"
    _protocol="${2:-auto}"

    rkp_device_supported || { echo "Device RKP Issuer needs arm64-v8a" >&2; exit 2; }

    . "$MODDIR/../lib/config_env.sh"
    . "$MODDIR/../lib/keystore.sh"
    resolve_keystore_backend
    [ "$KEYSTORE_BACKEND" != "none" ] || { echo "No keystore backend" >&2; exit 24; }

    rkp_device_provision "$_protocol"
    _rc=$?
    if [ "$_rc" -ne 0 ]; then
      log "RKP_DEVICE" "Provision failed (exit $_rc)"
      echo "Device RKP provisioning failed" >&2
      exit 21
    fi

    [ -s "$RKP_DEVICE_OUTPUT" ] || { echo "No keybox produced" >&2; exit 22; }
    keystore_validate_keybox "$RKP_DEVICE_OUTPUT" >/dev/null 2>&1 || { echo "Keybox is invalid" >&2; exit 22; }

    # Tag so the home card shows "RKP Device" (same convention as rkp_catalog.sh)
    awk 'NR==1 && /^<\?xml/ { print; print "<!-- RKP-KEYBOX:device -->"; next } NR==1 { print "<!-- RKP-KEYBOX:device -->"; print; next } { print }' \
      "$RKP_DEVICE_OUTPUT" > "${RKP_DEVICE_OUTPUT}.tagged" \
      && mv "${RKP_DEVICE_OUTPUT}.tagged" "$RKP_DEVICE_OUTPUT" \
      || { rm -f "${RKP_DEVICE_OUTPUT}.tagged"; log "RKP_DEVICE" "Could not tag keybox; home card shows Generic"; }

    ensure_dir "$KEYSTORE_DIR"
    if [ -f "$KEYSTORE_KEYBOX" ] && ! keybox_is_jerry "$KEYSTORE_KEYBOX" && [ -z "$(find_keybox_backup "$KEYSTORE_BACKEND")" ]; then
      cp "$KEYSTORE_KEYBOX" "$KEYSTORE_BACKUP" 2>/dev/null
      log "RKP_DEVICE" "Created backup of existing keybox"
    fi

    keystore_install_keybox "$RKP_DEVICE_OUTPUT" >/dev/null 2>&1; _rc=$?
    [ "$_rc" -eq 0 ] || { echo "Keybox install failed" >&2; exit 23; }

    log "RKP_DEVICE" "Installed device-signed keybox ($KEYSTORE_NAME)"
    log "RKP_DEVICE" "Finish"
    echo "Installed"
    exit 0
    ;;
  *)
    echo "usage: rkp_device.sh status | provision [auto|v1|v2|v1-native]" >&2
    exit 64
    ;;
esac
