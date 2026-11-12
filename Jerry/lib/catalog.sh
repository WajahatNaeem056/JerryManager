# Keybox catalog helpers (softban / revoked / expiry flags from the online catalog).
# Needs: lib/common.sh (log, download, ensure_dir) and lib/urls.sh.
#
# Catalog format (catalog.json in the jerrybin repo, one flat object per entry):
#   {"entries":[
#     {"version":"12","url":"https://.../key","url_fallback":"https://.../key",
#      "softbanned":false,"revoked":false,"expires_at":""}
#   ]}
# "version" must be numeric and equal to the number in the keybox marker
# (jerryroot:NN / JERRY-KEYBOX:NN). url_fallback and expires_at are optional.

KEYBOX_CATALOG_CACHE="/data/adb/JerryManager/cache/keybox_catalog.json"

# Field / flag of one catalog entry (entry is a single-line flat JSON object)
_kc_field() { printf '%s' "$1" | sed -n 's/.*"'"$2"'":"\([^"]*\)".*/\1/p'; }
_kc_flag()  { printf '%s' "$1" | grep -q '"'"$2"'":true'; }

# Flatten to one line and drop spaces around ':' so grep/sed can parse it
_kc_normalize() {
  tr -d '\r\n\t' | sed 's/"[[:space:]]*:[[:space:]]*/":/g; s/,[[:space:]]*"/,"/g; s/{[[:space:]]*"/{"/g'
}

# Print the catalog JSON (5 min cache; a stale valid copy beats no catalog)
keybox_catalog() {
  _kc_ttl="${KEYBOX_CATALOG_TTL:-300}"
  if [ -s "$KEYBOX_CATALOG_CACHE" ]; then
    _kc_age=$(( $(date +%s) - $(stat -c %Y "$KEYBOX_CATALOG_CACHE" 2>/dev/null || echo 0) ))
    if [ "$_kc_age" -ge 0 ] && [ "$_kc_age" -lt "$_kc_ttl" ]; then
      cat "$KEYBOX_CATALOG_CACHE"
      unset _kc_ttl _kc_age
      return 0
    fi
  fi

  _kc_json=""
  for _kc_url in "$CATALOG_URL" "$CATALOG_URL_FALLBACK"; do
    [ -n "$_kc_url" ] || continue
    _kc_try=$(download "$_kc_url" 2>/dev/null | _kc_normalize) || _kc_try=""
    case "$_kc_try" in
      *'"entries"'*) _kc_json="$_kc_try"; break ;;
    esac
  done

  if [ -n "$_kc_json" ]; then
    ensure_dir "$(dirname "$KEYBOX_CATALOG_CACHE")"
    printf '%s' "$_kc_json" > "$KEYBOX_CATALOG_CACHE" 2>/dev/null || true
    printf '%s' "$_kc_json"
    unset _kc_ttl _kc_age _kc_json _kc_url _kc_try
    return 0
  fi

  if [ -s "$KEYBOX_CATALOG_CACHE" ] && grep -q '"entries"' "$KEYBOX_CATALOG_CACHE" 2>/dev/null; then
    cat "$KEYBOX_CATALOG_CACHE"
    unset _kc_ttl _kc_age _kc_json _kc_url _kc_try
    return 0
  fi

  unset _kc_ttl _kc_age _kc_json _kc_url _kc_try
  return 1
}

# One entry per line
keybox_catalog_entries() {
  _kce_json=$(keybox_catalog) || { unset _kce_json; return 1; }
  printf '%s' "$_kce_json" | grep -o '{[^{}]*}'
  unset _kce_json
}

# True if the entry has an expires_at that is already in the past (UTC ISO compare)
keybox_entry_expired() {
  _kee_exp=$(_kc_field "$1" expires_at | sed 's/\.[0-9]*Z$/Z/')
  [ -n "$_kee_exp" ] || { unset _kee_exp; return 1; }
  case "$_kee_exp" in *Z) ;; *) _kee_exp="${_kee_exp}Z" ;; esac
  _kee_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  awk -v e="$_kee_exp" -v n="$_kee_now" 'BEGIN { exit !(e <= n) }'
  _kee_rc=$?
  unset _kee_exp _kee_now
  return $_kee_rc
}

# Best entry: skip revoked / expired / url-less ones, prefer not softbanned,
# highest version first. Only softbanned left -> the newest softbanned one.
keybox_pick_entry() {
  _kp_all=$(keybox_catalog_entries) || { unset _kp_all; return 1; }
  [ -n "$_kp_all" ] || { unset _kp_all; return 1; }

  _kp_ok=""
  while IFS= read -r _kp_e; do
    [ -n "$_kp_e" ] || continue
    _kc_flag "$_kp_e" revoked && continue
    keybox_entry_expired "$_kp_e" && continue
    [ -n "$(_kc_field "$_kp_e" url)" ] || continue
    [ -n "$(_kc_field "$_kp_e" version)" ] || continue
    _kp_ok="${_kp_ok}${_kp_e}
"
  done <<CATALOG_EOF
$_kp_all
CATALOG_EOF

  _kp_pool=$(printf '%s' "$_kp_ok" | grep -v '"softbanned":true')
  [ -n "$_kp_pool" ] || _kp_pool=$(printf '%s' "$_kp_ok" | grep '"softbanned":true')
  [ -n "$_kp_pool" ] || { unset _kp_all _kp_ok _kp_pool _kp_e; return 1; }

  _kp_best=$(printf '%s\n' "$_kp_pool" | while IFS= read -r _kp_l; do
    [ -n "$_kp_l" ] || continue
    printf '%s %s\n' "$(_kc_field "$_kp_l" version)" "$_kp_l"
  done | sort -rn | head -n1 | cut -d' ' -f2-)

  [ -n "$_kp_best" ] || { unset _kp_all _kp_ok _kp_pool _kp_e _kp_best; return 1; }
  printf '%s\n' "$_kp_best"
  unset _kp_all _kp_ok _kp_pool _kp_e _kp_best
}

# True if the catalog entry with this version is softbanned
keybox_version_softbanned() {
  _kv_e=$(keybox_catalog_entries 2>/dev/null | grep '"version":"'"$1"'"' | head -n1)
  [ -n "$_kv_e" ] && _kc_flag "$_kv_e" softbanned
  _kv_rc=$?
  unset _kv_e
  return $_kv_rc
}

# Version number Jerry wrote into an installed keybox ("" if not from Jerry)
keybox_file_version() {
  grep -oE 'jerryroot:[0-9]+|JERRY-KEYBOX:[0-9]+' "$1" 2>/dev/null | head -n1 | sed 's/jerryroot://;s/JERRY-KEYBOX://'
}

# True if the installed keybox is softbanned AND a better (not softbanned) one exists
keybox_softban_replaceable() {
  _ks_ver=$(keybox_file_version "$1")
  [ -n "$_ks_ver" ] || { unset _ks_ver; return 1; }
  keybox_version_softbanned "$_ks_ver" || { unset _ks_ver; return 1; }
  _ks_pick=$(keybox_pick_entry 2>/dev/null) || { unset _ks_ver _ks_pick; return 1; }
  if _kc_flag "$_ks_pick" softbanned || [ "$(_kc_field "$_ks_pick" version)" = "$_ks_ver" ]; then
    unset _ks_ver _ks_pick
    return 1
  fi
  unset _ks_ver _ks_pick
  return 0
}
