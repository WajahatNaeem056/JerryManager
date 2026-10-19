#!/system/bin/sh
# Backend for the PIF Settings page (WebUI).
#   get                         spoof flags as JSON
#   set <flag> <0|1>            change one spoof flag in /data/adb/pif.prop
#   view                        print /data/adb/pif.prop
#   devices                     "Model|product" list for the device picker
#   fetch [device] [source]     device: random | <codename>_beta, source: github | autopif | auto
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/config_env.sh"
PIF_ROOT="${MODDIR%/*}"
. "$MODDIR/../lib/pif_lib.sh"
. "$MODDIR/../lib/pif_devices.sh"

_json_bool() { [ "$(pif_prop_get "$PIF_PROP" "$1")" = "true" ] && printf true || printf false; }

case "$1" in
  get)
    pif_ensure_prop
    printf '{"spoofBuild":%s,"spoofVendingBuild":%s,"spoofProps":%s,"spoofProvider":%s,"spoofSignature":%s,"spoofVendingSdk":%s}\n' \
      "$(_json_bool spoofBuild)" "$(_json_bool spoofVendingBuild)" "$(_json_bool spoofProps)" \
      "$(_json_bool spoofProvider)" "$(_json_bool spoofSignature)" "$(_json_bool spoofVendingSdk)"
    ;;
  set)
    case "$2" in
      spoofBuild|spoofVendingBuild|spoofProps|spoofProvider|spoofSignature|spoofVendingSdk) ;;
      *) echo "invalid flag"; exit 1 ;;
    esac
    pif_ensure_prop || { echo "no pif.prop"; exit 1; }
    _value=false; [ "$3" = "1" ] && _value=true
    pif_prop_set "$PIF_PROP" "$2" "$_value"
    pif_kill_gms
    log "PIF" "Set $2=$_value"
    echo "$2=$_value"
    ;;
  view)
    pif_ensure_prop
    cat "$PIF_PROP" 2>/dev/null || echo "pif.prop not found"
    ;;
  devices)
    printf '%s\n' "$PIF_DEVICE_LIST"
    ;;
  fetch)
    _device="${2:-random}"
    _source="${3:-auto}"
    case "$_device" in random|[a-z0-9]*_beta) ;; *) echo "invalid device"; exit 1 ;; esac
    case "$_source" in github|autopif|auto) ;; *) echo "invalid source"; exit 1 ;; esac
    PIF_FORCE=1 PIF_DEVICE="$_device" PIF_SOURCE="$_source" sh "$MODDIR/pif.sh"
    _rc=$?
    if [ "$_rc" -eq 0 ]; then
      echo "Fetch done"
      cat "$PIF_PROP" 2>/dev/null
    else
      echo "Fetch failed (check internet). Current pif.prop kept."
    fi
    exit "$_rc"
    ;;
  *)
    echo "usage: pif_config.sh get|set|view|devices|fetch"
    exit 1
    ;;
esac
exit 0
