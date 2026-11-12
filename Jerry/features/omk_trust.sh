#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/keystore.sh"

resolve_keystore_backend
[ "$KEYSTORE_BACKEND" = "omk" ] || die "OhMyKeymint is not the active keystore backend"

case "${1:-}" in
    --list)
        for _key in os_version security_patch vb_key vb_hash; do
            _val=$(keystore_get_trust_field "$_key")
            printf '%s=%s\n' "$_key" "$_val"
        done
        exit 0
        ;;
    --get)
        [ -n "${2:-}" ] || die "omk_trust.sh --get requires a key (os_version|security_patch|vb_key|vb_hash)"
        _val=$(keystore_get_trust_field "$2")
        printf '%s\n' "$_val"
        exit 0
        ;;
    --set)
        [ -n "${2:-}" ] || die "omk_trust.sh --set requires key=value arguments"
        shift
        for _kv in "$@"; do
            _key="${_kv%%=*}"
            _val="${_kv#*=}"
            [ -n "$_key" ] || continue
            keystore_set_trust_field "$_key" "$_val" || die "Failed to set $_key (invalid value or config.toml missing)"
            log "OMK_TRUST" "Set $_key"
        done
        exit 0
        ;;
    *)
        die "Usage: omk_trust.sh --list|--get <key>|--set <key>=<value> [...]"
        ;;
esac
