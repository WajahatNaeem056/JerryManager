#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/urls.sh"

KEYBOX_FILE="/data/adb/tricky_store/keybox.xml"
INFO_PATH="$MODDIR/../webroot/json/keybox_info.json"

ensure_dir "$(dirname "$INFO_PATH")"

_installed=false
_by_jerry=false
_version=""
_latest_version=""
_up_to_date=false
_revoked=false

if [ -f "$KEYBOX_FILE" ]; then
  _installed=true

  _device_id=$(grep -o 'DeviceID="[^"]*"' "$KEYBOX_FILE" | head -1 | sed 's/DeviceID="//;s/"//')

  _jerry_marker=$(grep -oE 'jerryroot:[0-9]+|JERRY-KEYBOX:[0-9]+' "$KEYBOX_FILE" | head -1 | sed 's/jerryroot://;s/JERRY-KEYBOX://')
  if [ -n "$_jerry_marker" ]; then
    _by_jerry=true
    _version="$_jerry_marker"
  fi

  if check_network; then
    log "KEYBOX_INFO" "Network OK, fetching Google revocation list"
    _revoked_list=$(download "$GOOGLE_REVOCATION_URL" 2>/dev/null)
    log "KEYBOX_INFO" "Google response length: ${#_revoked_list}"

    if [ -n "$_revoked_list" ]; then
      _b64=$(sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' "$KEYBOX_FILE" | head -20 | grep -v 'CERTIFICATE' | tr -d '\n')
      if [ -n "$_b64" ]; then
        _hex=$(echo "$_b64" | base64 -d 2>/dev/null | od -v -tx1 | awk 'BEGIN{ORS=""} {for(i=2;i<=NF;i++) printf "%s", $i}')
        _serial_hex=$(echo "$_hex" | grep -o "020a[0-9a-f]\{20\}" | head -1 | sed 's/^020a//')
        log "KEYBOX_INFO" "Serial hex: $_serial_hex"
        if [ -n "$_serial_hex" ]; then
          if echo "$_revoked_list" | grep -qi "$_serial_hex"; then
            _revoked=true; log "KEYBOX_INFO" "REVOKED: matched hex"
          fi
          _serial_clean="${_serial_hex#"${_serial_hex%%[!0]*}"}"; [ -z "$_serial_clean" ] && _serial_clean=0
          if echo "$_revoked_list" | grep -qi "$_serial_clean"; then
            _revoked=true; log "KEYBOX_INFO" "REVOKED: matched clean hex"
          fi
          if ! $_revoked && [ ${#_serial_hex} -le 16 ]; then
            _serial_dec=$((16#$_serial_clean))
            if echo "$_revoked_list" | grep -q "$_serial_dec"; then
              _revoked=true; log "KEYBOX_INFO" "REVOKED: matched decimal"
            fi
          fi
        fi
      fi
    else
      log "KEYBOX_INFO" "Google response empty, skipping revocation check"
    fi

    _latest_version=$(download "$LATEST_KEYBOX_URL" 2>/dev/null | tr -d '[:space:]')
    log "KEYBOX_INFO" "Latest version: $_latest_version, Installed: $_version"
    if [ -n "$_version" ] && [ -n "$_latest_version" ] && [ "$_version" = "$_latest_version" ]; then
      _up_to_date=true
    fi
  else
    log "KEYBOX_INFO" "Network check failed, skipping online checks"
  fi
fi

cat <<EOF > "$INFO_PATH"
{
  "installed": $_installed,
  "by_jerry": $_by_jerry,
  "version": "$_version",
  "latest_version": "$_latest_version",
  "up_to_date": $_up_to_date,
  "revoked": $_revoked
}
EOF

unset _installed _by_jerry _version _latest_version _up_to_date _revoked _device_id _jerry_marker _revoked_list _b64 _serial_hex _serial_clean _serial_dec
