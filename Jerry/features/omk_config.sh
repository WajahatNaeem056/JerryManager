#!/system/bin/sh
# OhMyKeymint config page backend: read/write config.toml + injector.toml, restart services.
#   omk_config.sh --read <config|injector>
#   omk_config.sh --write <config|injector> <base64> [restart]
#   omk_config.sh --restart <injector|keymint|both>
#   omk_config.sh --restore <config|injector> <orig|bak>
#   omk_config.sh --status
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/keystore.sh"

resolve_keystore_backend
if [ "$KEYSTORE_BACKEND" != "omk" ]; then
    # --status is the WebUI's silent probe on every start: answer without logging an error
    [ "${1:-}" = "--status" ] && exit 1
    die "OhMyKeymint is not the active keystore backend"
fi

OMK_BAK_DIR="${OMK_BAK_DIR:-/data/adb/JerryManager/omk_backup}"

_omk_target() {
    case "$1" in
        config)   printf '%s' "$OMK_CONFIG" ;;
        injector) printf '%s' "$OMK_INJECTOR" ;;
        *) return 1 ;;
    esac
}

_omk_reload() {
    case "$1" in
        config)   keystore_reload_keymint ;;
        injector) keystore_reload_injector ;;
    esac
}

# [crypto] secrets must never change: they protect every key OMK has created.
_omk_secrets() {
    grep -E '^[[:space:]]*(root_kek_seed|kak_seed|shared_secret_seed|shared_secret_nonce|auth_token_hmac_key)[[:space:]]*=' "$1" 2>/dev/null | sed 's/[[:space:]]//g' | sort
}

_omk_b64d() {
    base64 -d 2>/dev/null || busybox base64 -d 2>/dev/null
}

case "${1:-}" in
    --read)
        _f=$(_omk_target "${2:-}") || die "Usage: omk_config.sh --read <config|injector>"
        [ -f "$_f" ] || die "$2.toml not found ($_f) — start OhMyKeymint once first"
        cat "$_f"
        ;;
    --write)
        _f=$(_omk_target "${2:-}") || die "Usage: omk_config.sh --write <config|injector> <base64>"
        [ -n "${3:-}" ] || die "No data to write"
        ensure_dir "$OMK_BAK_DIR"
        _tmp="$OMK_BAK_DIR/.incoming.$$"
        printf '%s' "$3" | _omk_b64d > "$_tmp" || { rm -f "$_tmp"; die "Could not decode data"; }
        [ -s "$_tmp" ] || { rm -f "$_tmp"; die "Refusing to write an empty $2.toml"; }
        if [ "$2" = config ] && [ -f "$_f" ]; then
            [ "$(_omk_secrets "$_f")" = "$(_omk_secrets "$_tmp")" ] || { rm -f "$_tmp"; die "Refusing to change the [crypto] secrets in config.toml"; }
        fi
        if [ -f "$_f" ]; then
            [ -f "$OMK_BAK_DIR/$2.orig" ] || cat "$_f" > "$OMK_BAK_DIR/$2.orig"
            cat "$_f" > "$OMK_BAK_DIR/$2.bak"
        fi
        # cat into the existing file keeps its owner and SELinux label
        cat "$_tmp" > "$_f" || { rm -f "$_tmp"; die "Failed to write $_f (previous copy kept in $OMK_BAK_DIR)"; }
        rm -f "$_tmp"
        # OMK watches both files and hot-applies valid changes; only restart when asked
        [ "${4:-}" = restart ] && _omk_reload "$2"
        log "OMK_CONFIG" "Wrote $2.toml (restart=${4:-no})"
        ;;
    --restore)
        _f=$(_omk_target "${2:-}") || die "Usage: omk_config.sh --restore <config|injector> <orig|bak>"
        case "${3:-}" in orig|bak) ;; *) die "Restore source must be orig or bak" ;; esac
        _src="$OMK_BAK_DIR/$2.$3"
        [ -s "$_src" ] || die "No $3 copy of $2.toml saved yet"
        if [ "$2" = config ] && [ -f "$_f" ]; then
            [ "$(_omk_secrets "$_f")" = "$(_omk_secrets "$_src")" ] || die "Refusing to restore: the [crypto] secrets differ from the saved copy"
        fi
        cat "$_src" > "$_f" || die "Failed to restore $_f"
        _omk_reload "$2"
        log "OMK_CONFIG" "Restored $2.toml from $3"
        ;;
    --restart)
        case "${2:-}" in
            injector) keystore_reload_injector ;;
            keymint)  keystore_reload_keymint ;;
            both)     keystore_reload_injector; keystore_reload_keymint ;;
            *) die "Usage: omk_config.sh --restart <injector|keymint|both>" ;;
        esac
        log "OMK_CONFIG" "Restart requested: $2"
        ;;
    --status)
        for _n in config injector; do
            for _k in orig bak; do
                [ -s "$OMK_BAK_DIR/$_n.$_k" ] && printf '%s.%s=1\n' "$_n" "$_k" || printf '%s.%s=0\n' "$_n" "$_k"
            done
        done
        ;;
    *)
        die "Usage: omk_config.sh --read|--write|--restart|--restore|--status"
        ;;
esac
exit 0
