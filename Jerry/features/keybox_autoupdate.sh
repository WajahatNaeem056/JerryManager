#!/system/bin/sh
# Auto keybox update (all backends): a few minutes after boot, then every 12h.
# Installs a fresh keybox only when the current one is missing, revoked by Google, expired or softbanned (when a better keybox exists).
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/urls.sh"
. "$MODDIR/../lib/keystore.sh"
. "$MODDIR/../lib/catalog.sh"
. "$MODDIR/../lib/toggle_seed.sh"

INTERVAL=43200
sleep 180

while true; do
    _ka_sleep="$INTERVAL"
    if _feature_enabled toggle_auto_keybox_update; then
        resolve_keystore_backend
        if [ "$KEYSTORE_BACKEND" != "none" ] && check_network; then
            _ka_need=""
            if [ ! -f "$KEYSTORE_KEYBOX" ]; then
                _ka_need="missing"
            else
                _ka_serial=$(decode_keybox_serial "$KEYSTORE_KEYBOX" 2>/dev/null || echo "")
                _ka_rev=1
                [ -n "$_ka_serial" ] && { check_google_revocation "$_ka_serial"; _ka_rev=$?; }
                if [ "$_ka_rev" = "0" ]; then
                    _ka_need="revoked"
                elif keybox_is_expired "$KEYSTORE_KEYBOX"; then
                    _ka_need="expired"
                elif keybox_softban_replaceable "$KEYSTORE_KEYBOX"; then
                    _ka_need="softbanned"
                fi
            fi
            if [ -n "$_ka_need" ]; then
                log "KEYBOX_AUTO" "Keybox $_ka_need — installing a new one"
                sh "$MODDIR/keybox.sh" >/dev/null 2>&1 \
                    && log "KEYBOX_AUTO" "Keybox updated" \
                    || log "KEYBOX_AUTO" "Update failed, will retry in 12h"
            elif [ "$_ka_rev" = "2" ]; then
                # Google's list could not be fetched: do not call the keybox OK, look again in 1h
                log "KEYBOX_AUTO" "Revocation list unavailable — status unknown, checking again in 1h"
                _ka_sleep=3600
            else
                log "KEYBOX_AUTO" "Keybox OK — nothing to do"
                [ "$(cfg_get keybox_valid "")" = "Unknown" ] && ! keybox_is_expired "$KEYSTORE_KEYBOX" \
                    && [ -n "$_ka_serial" ] && cfg_set keybox_valid "Yes"
            fi
            unset _ka_need _ka_serial _ka_rev
        fi
    fi
    sleep "$_ka_sleep"
done
