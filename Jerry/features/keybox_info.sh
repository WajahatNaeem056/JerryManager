#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/urls.sh"

KEYBOX_FILE="/data/adb/tricky_store/keybox.xml"
INFO_PATH="$MODDIR/../webroot/json/keybox_info.json"

_quick_fetch() {
  _qf_url="$1" _qf_oldpath="$PATH"
  PATH="/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:/data/data/com.termux/files/usr/bin:$PATH"
  busybox wget -T 5 --no-check-certificate -qO- "$_qf_url" 2>/dev/null
  PATH="$_qf_oldpath"
  unset _qf_url _qf_oldpath
}

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
    _tmp_revoked="$(mktemp 2>/dev/null || echo /data/local/tmp/.jerry_revoked_$$)"
    _tmp_latest="$(mktemp 2>/dev/null || echo /data/local/tmp/.jerry_latest_$$)"

    ( _quick_fetch "$GOOGLE_REVOCATION_URL" > "$_tmp_revoked" 2>/dev/null ) &
    _pid_revoked=$!
    ( _quick_fetch "$LATEST_KEYBOX_URL" > "$_tmp_latest" 2>/dev/null ) &
    _pid_latest=$!

    wait "$_pid_revoked" 2>/dev/null
    wait "$_pid_latest" 2>/dev/null

    _revoked_list=$(cat "$_tmp_revoked" 2>/dev/null)
    _latest_version=$(cat "$_tmp_latest" 2>/dev/null | tr -d '[:space:]')
    rm -f "$_tmp_revoked" "$_tmp_latest" 2>/dev/null

    _revoke_reason=""
    if [ -n "$_revoked_list" ]; then
      _b64=$(sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' "$KEYBOX_FILE" | head -20 | grep -v 'CERTIFICATE' | tr -d '\n')
      if [ -n "$_b64" ]; then
        _hex=$(echo "$_b64" | base64 -d 2>/dev/null | od -v -tx1 | awk 'BEGIN{ORS=""} {for(i=2;i<=NF;i++) printf "%s", $i}')
        _serial_hex=$(echo "$_hex" | grep -o "020a[0-9a-f]\{20\}" | head -1 | sed 's/^020a//')
        if [ -n "$_serial_hex" ]; then
          if echo "$_revoked_list" | grep -qi "$_serial_hex"; then
            _revoked=true; _revoke_reason="hex"
          fi
          _serial_clean="${_serial_hex#"${_serial_hex%%[!0]*}"}"; [ -z "$_serial_clean" ] && _serial_clean=0
          if echo "$_revoked_list" | grep -qi "$_serial_clean"; then
            _revoked=true; _revoke_reason="clean hex"
          fi
          if ! $_revoked && [ ${#_serial_hex} -le 16 ]; then
            _serial_dec=$((16#$_serial_clean))
            if echo "$_revoked_list" | grep -q "$_serial_dec"; then
              _revoked=true; _revoke_reason="decimal"
            fi
          fi
        fi
      fi
    fi

    if [ -n "$_version" ] && [ -n "$_latest_version" ] && [ "$_version" = "$_latest_version" ]; then
      _up_to_date=true
    fi

    if $_revoked; then
      log "KEYBOX_INFO" "Serial: $_serial_hex — REVOKED ($_revoke_reason)"
    else
      log "KEYBOX_INFO" "Serial: $_serial_hex — clean, not revoked"
    fi
    log "KEYBOX_INFO" "Installed: $_version, Latest: $_latest_version"
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

unset _installed _by_jerry _version _latest_version _up_to_date _revoked _device_id _jerry_marker _revoked_list _b64 _serial_hex _serial_clean _serial_dec _tmp_revoked _tmp_latest _pid_revoked _pid_latest _revoke_reason
