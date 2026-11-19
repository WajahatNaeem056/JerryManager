#!/system/bin/sh
# RKP keyboxes backend: rkp_catalog.sh list | install <id>. Exit: 0 ok, 11/12 catalog, 20-24 install, 64 usage.
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/rkp_catalog.sh"

RKP_CATALOG_URL="${RKP_CATALOG_URL:-https://raw.githubusercontent.com/WajahatNaeem056/jerrybin/main/rkp.json}"
RKP_CATALOG_URL_FALLBACK="${RKP_CATALOG_URL_FALLBACK:-https://cdn.jsdelivr.net/gh/WajahatNaeem056/jerrybin@main/rkp.json}"
RKP_CATALOG_CACHE="/data/adb/JerryManager/cache/rkp_catalog.json"

# Print the raw catalog JSON, or fail.
_rkp_fetch() {
  if [ -n "$RKP_CATALOG_FILE" ]; then
    grep -q '"entries"' "$RKP_CATALOG_FILE" 2>/dev/null && cat "$RKP_CATALOG_FILE"
    return
  fi
  _rf_ttl="${RKP_CATALOG_TTL:-300}"
  if [ -s "$RKP_CATALOG_CACHE" ]; then
    _rf_age=$(( $(date +%s) - $(stat -c %Y "$RKP_CATALOG_CACHE" 2>/dev/null || echo 0) ))
    if [ "$_rf_age" -ge 0 ] && [ "$_rf_age" -lt "$_rf_ttl" ]; then
      cat "$RKP_CATALOG_CACHE"
      return 0
    fi
  fi
  for _rf_url in "$RKP_CATALOG_URL" "$RKP_CATALOG_URL_FALLBACK"; do
    [ -n "$_rf_url" ] || continue
    _rf_try=$(download "$_rf_url" 2>/dev/null) || _rf_try=""
    case "$_rf_try" in
      *'"entries"'*)
        ensure_dir "$(dirname "$RKP_CATALOG_CACHE")"
        printf '%s' "$_rf_try" > "$RKP_CATALOG_CACHE" 2>/dev/null || true
        printf '%s' "$_rf_try"
        return 0 ;;
    esac
  done
  if [ -s "$RKP_CATALOG_CACHE" ] && grep -q '"entries"' "$RKP_CATALOG_CACHE" 2>/dev/null; then
    cat "$RKP_CATALOG_CACHE"
    return 0
  fi
  return 1
}

case "$1" in
  list)
    _rkp_json=$(_rkp_fetch) || { echo "RKP catalog could not be fetched" >&2; exit 11; }
    printf '%s' "$_rkp_json" | rkp_catalog_eligible
    _rc=$?
    [ "$_rc" -eq 0 ] || { echo "RKP catalog is invalid" >&2; exit 12; }
    exit 0
    ;;
  install)
    _id="$2"
    rkp_valid_id "$_id" || { echo "usage: rkp_catalog.sh install <id>" >&2; exit 64; }
    _rkp_json=$(_rkp_fetch) || { echo "RKP catalog could not be fetched" >&2; exit 11; }
    _url=$(printf '%s' "$_rkp_json" | rkp_catalog_url_for_id "$_id")
    [ -n "$_url" ] || { echo "RKP entry not available (missing or expired)" >&2; exit 20; }

    . "$MODDIR/../lib/config_env.sh"
    . "$MODDIR/../lib/keystore.sh"
    resolve_keystore_backend
    [ "$KEYSTORE_BACKEND" != "none" ] || { echo "No keystore backend" >&2; exit 24; }

    _tmp=$(mktemp 2>/dev/null || echo "/data/local/tmp/.rkp_kb_$$")
    download "$_url" "$_tmp" >/dev/null 2>&1 || { rm -f "$_tmp"; echo "Keybox download failed" >&2; exit 21; }
    keystore_validate_keybox "$_tmp" >/dev/null 2>&1 || { rm -f "$_tmp"; echo "Keybox is invalid" >&2; exit 22; }

    # Tag the keybox with its catalog id (XML comment) so the home card shows "RKP <id>"; a failed tag only affects display
    awk -v m="<!-- RKP-KEYBOX:${_id} -->" 'NR==1 && /^<\?xml/ { print; print m; next } NR==1 { print m; print; next } { print }' "$_tmp" > "${_tmp}.tagged" \
      && mv "${_tmp}.tagged" "$_tmp" \
      || { rm -f "${_tmp}.tagged"; log "RKP" "Could not tag keybox $_id; it installs untagged and the home card shows Generic"; }

    ensure_dir "$KEYSTORE_DIR"
    if [ -f "$KEYSTORE_KEYBOX" ] && ! keybox_is_jerry "$KEYSTORE_KEYBOX" && [ -z "$(find_keybox_backup "$KEYSTORE_BACKEND")" ]; then
      cp "$KEYSTORE_KEYBOX" "$KEYSTORE_BACKUP" 2>/dev/null
    fi
    keystore_install_keybox "$_tmp" >/dev/null 2>&1; _rc=$?
    rm -f "$_tmp"
    [ "$_rc" -eq 0 ] || { echo "Keybox install failed" >&2; exit 23; }
    log "RKP" "Installed RKP keybox $_id"
    echo "Installed $_id"
    exit 0
    ;;
  *)
    echo "usage: rkp_catalog.sh list | install <id>" >&2
    exit 64
    ;;
esac
