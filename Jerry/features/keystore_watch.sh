#!/system/bin/sh
# Started from service.sh. Keeps the active keystore engine in sync with no toggles:
#  - OhMyKeymint (active backend) -> omk_sync.sh
#  - TEESimulator (installed)     -> teesim_sync.sh
# Runs once at boot (retried until the engine's files exist) and again whenever the PIF
# config or target.txt changes. Exits at once when neither engine is present.
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/keystore.sh"
. "$MODDIR/../lib/toggle_seed.sh"

resolve_keystore_backend
if _feature_enabled toggle_keystore_singleton; then
    keystore_enforce_singleton
else
    keystore_warn_multiple
fi
_kw_omk=0; _kw_tee=0
[ "$KEYSTORE_BACKEND" = "omk" ] && _kw_omk=1
{ [ -d /data/adb/modules/teesim ] || [ -d /data/adb/modules_update/teesim ] || [ -f "$TEESIM_CONFIG" ]; } && _kw_tee=1
[ "$_kw_omk$_kw_tee" = "00" ] && exit 0

[ "$_kw_omk" = "1" ] && log "KS_WATCH" "OhMyKeymint detected — auto sync active"
[ "$_kw_tee" = "1" ] && log "KS_WATCH" "TEESimulator detected — auto sync active"

_kw_last=""
while true; do
    _kw_sig="$(cksum /data/adb/pif.prop /data/adb/custom.pif.prop "$MODDIR/../pif.prop" "$TARGET_TXT" 2>/dev/null | tr '\n' ' ')"
    [ -f "$OMK_CONFIG" ] && _kw_sig="${_kw_sig}ocfg"
    [ -f "$OMK_INJECTOR" ] && _kw_sig="${_kw_sig}oinj"
    [ -f "$TEESIM_CONFIG" ] && _kw_sig="${_kw_sig}tcfg"
    if [ "$_kw_sig" != "$_kw_last" ]; then
        _kw_last="$_kw_sig"
        [ "$_kw_omk" = "1" ] && sh "$MODDIR/omk_sync.sh" 2>/dev/null
        [ "$_kw_tee" = "1" ] && sh "$MODDIR/teesim_sync.sh" 2>/dev/null
    fi
    sleep 15
done
