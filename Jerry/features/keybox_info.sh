#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/urls.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/keystore.sh"
. "$MODDIR/../lib/catalog.sh"

resolve_keystore_backend
KEYBOX_FILE="$KEYSTORE_KEYBOX"
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
_by_rkp=false
_rkp_id=""
_version=""
_latest_version=""
_up_to_date=false
_revoked=false
_softbanned=false
_expired=false
_expires_at=""
_online_checked=false
_rev_checked=false
_checked_at=""

if [ -f "$KEYBOX_FILE" ]; then
  _installed=true

  _device_id=$(grep -o 'DeviceID="[^"]*"' "$KEYBOX_FILE" | head -1 | sed 's/DeviceID="//;s/"//')

  # Certificate expiry is read from the file itself, so it works offline
  _exp_raw=$(decode_keybox_expiry "$KEYBOX_FILE" 2>/dev/null || true)
  if [ -n "$_exp_raw" ]; then
    _expires_at=$(printf '%s' "$_exp_raw" | sed 's/^\(....\)\(..\)\(..\)\(..\)\(..\)\(..\)$/\1-\2-\3T\4:\5:\6Z/')
    keybox_is_expired "$KEYBOX_FILE" && _expired=true
    if $_expired; then
      log "KEYBOX_INFO" "Keybox certificate expired on $_expires_at"
    else
      log "KEYBOX_INFO" "Keybox certificate valid until $_expires_at"
    fi
  fi

  _jerry_marker=$(grep -oE 'jerryroot:[0-9]+|JERRY-KEYBOX:[0-9]+' "$KEYBOX_FILE" | head -1 | sed 's/jerryroot://;s/JERRY-KEYBOX://')
  if [ -n "$_jerry_marker" ]; then
    _by_jerry=true
    _version="$_jerry_marker"
  fi

  # RKP-installed keybox: tagged by rkp_catalog.sh install, independent of the jerryroot scheme
  _rkp_marker=$(grep -oE 'RKP-KEYBOX:[A-Za-z0-9._-]{1,64}' "$KEYBOX_FILE" | head -1 | sed 's/RKP-KEYBOX://')
  if [ -n "$_rkp_marker" ]; then
    _by_rkp=true
    _rkp_id="$_rkp_marker"
  fi
fi

if [ "$_installed" = "true" ]; then
  if check_network; then
    _online_checked=true
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
    if [ -n "$_revoked_list" ] && [ "$_by_rkp" != "true" ]; then
      _b64=$(sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' "$KEYBOX_FILE" | head -20 | grep -v 'CERTIFICATE' | tr -d '\n')
      if [ -n "$_b64" ]; then
        _hex=$(echo "$_b64" | base64 -d 2>/dev/null | od -v -tx1 | awk 'BEGIN{ORS=""} {for(i=2;i<=NF;i++) printf "%s", $i}')
        _serial_hex=$(echo "$_hex" | grep -o "020a[0-9a-f]\{20\}" | head -1 | sed 's/^020a//')
        if [ -z "$_serial_hex" ]; then
          _sr=$(echo "$_hex" | sed -n 's/.*a00302010202\([0-9a-f][0-9a-f]\)\([0-9a-f]*\)$/\1 \2/p' | head -1)
          _sl=${_sr%% *}; _sb=${_sr#* }
          if [ -n "$_sl" ] && [ "$_sl" != "$_sr" ]; then
            _sn=$((16#$_sl * 2))
            [ "$_sn" -gt 0 ] && [ "$_sn" -le 40 ] && _serial_hex=$(echo "$_sb" | cut -c1-$_sn)
          fi
          unset _sr _sl _sb _sn
        fi
        if [ -n "$_serial_hex" ]; then
          _rev_checked=true
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

    # Catalog (if reachable) overrides the single latest_keybox number and adds softban status
    _cat_pick=$(keybox_pick_entry 2>/dev/null) || _cat_pick=""
    if [ -n "$_cat_pick" ]; then
      # Never go below the latest_keybox number: if the catalog was not touched for a
      # newer key, the newer number still wins and the card does not show a false "update".
      _cat_ver=$(_kc_field "$_cat_pick" version)
      case "$_cat_ver" in
        ''|*[!0-9]*) ;;
        *)
          case "$_latest_version" in
            ''|*[!0-9]*) _latest_version="$_cat_ver" ;;
            *) [ "$_cat_ver" -gt "$_latest_version" ] && _latest_version="$_cat_ver" ;;
          esac
          ;;
      esac
      if [ -n "$_version" ] && keybox_version_softbanned "$_version"; then
        _softbanned=true
        log "KEYBOX_INFO" "Installed keybox v$_version is softbanned in the catalog"
      fi
    fi

    if [ -n "$_version" ] && [ -n "$_latest_version" ] && [ "$_version" = "$_latest_version" ]; then
      _up_to_date=true
    fi

    if $_revoked; then
      log "KEYBOX_INFO" "Serial: $_serial_hex — REVOKED ($_revoke_reason)"
    elif $_rev_checked; then
      log "KEYBOX_INFO" "Serial: $_serial_hex — clean, not revoked"
    else
      log "KEYBOX_INFO" "Revocation not checked (list unavailable or serial not found)"
    fi
    log "KEYBOX_INFO" "Installed: $_version, Latest: $_latest_version"
  else
    log "KEYBOX_INFO" "Network check failed, skipping online checks"
  fi
fi

_gen_ts=$(date +%s%N 2>/dev/null || date +%s)
_checked_at=$(date +%s 2>/dev/null)

cat <<EOF > "$INFO_PATH"
{
  "installed": $_installed,
  "by_jerry": $_by_jerry,
  "by_rkp": $_by_rkp,
  "rkp_id": "$_rkp_id",
  "version": "$_version",
  "latest_version": "$_latest_version",
  "up_to_date": $_up_to_date,
  "revoked": $_revoked,
  "softbanned": $_softbanned,
  "expired": $_expired,
  "expires_at": "$_expires_at",
  "online_checked": $_online_checked,
  "revocation_checked": $_rev_checked,
  "checked_at": "$_checked_at",
  "backend": "$KEYSTORE_NAME",
  "generated_at": "$_gen_ts"
}
EOF

unset _hex _rev_checked _checked_at _online_checked _cat_pick _cat_ver _softbanned _gen_ts _installed _by_jerry _by_rkp _rkp_id _rkp_marker _version _latest_version _up_to_date _revoked _expired _expires_at _exp_raw _device_id _jerry_marker _revoked_list _b64 _serial_hex _serial_clean _serial_dec _tmp_revoked _tmp_latest _pid_revoked _pid_latest _revoke_reason
