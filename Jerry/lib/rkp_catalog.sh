# shellcheck shell=sh
# RKP catalog filter: keeps entries with valid id, https url, future expires_at, rkp not false.
# Input: catalog JSON on stdin. RKP_NOW (UTC ISO) overrides the clock for tests.

# Entry id rule, shared by the catalog filter and "rkp_catalog.sh install <id>"
rkp_valid_id() { printf '%s' "$1" | grep -Eq '^[A-Za-z0-9._-]{1,64}$'; }

# One line, no blanks around ':' and ','
_rk_normalize() {
    tr -d '\r\n\t' | sed 's/"[[:space:]]*:[[:space:]]*/":/g; s/,[[:space:]]*"/,"/g; s/{[[:space:]]*"/{"/g'
}

_rk_field() { printf '%s' "$1" | sed -n 's/.*"'"$2"'":"\([^"]*\)".*/\1/p' | head -n1; }
_rk_has()   { printf '%s' "$1" | grep -q "$2"; }

_rkp_catalog_lines() {
    _rk_json=$(_rk_normalize)
    case "$_rk_json" in
        *'"entries":['*) ;;
        *) unset _rk_json; return 2 ;;
    esac
    _rk_now="${RKP_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

    printf '%s' "$_rk_json" | grep -o '{[^{}]*}' | while IFS= read -r _rk_e; do
        _rk_has "$_rk_e" '"rkp":false' && continue

        _rk_id=$(_rk_field "$_rk_e" id)
        rkp_valid_id "$_rk_id" || continue

        _rk_exp=$(_rk_field "$_rk_e" expires_at | sed 's/\.[0-9]*Z$/Z/')
        printf '%s' "$_rk_exp" | grep -Eq '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$' || continue
        awk -v e="$_rk_exp" -v n="$_rk_now" 'BEGIN { exit !(e > n) }' || continue

        _rk_url=$(_rk_field "$_rk_e" url)
        printf '%s' "$_rk_url" | grep -Eq '^https://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]+$' || continue

        _rk_name=$(_rk_field "$_rk_e" name | tr -d '|\\' | cut -c1-40)
        printf '%s|%s|%s|%s\n' "$_rk_id" "$_rk_name" "$_rk_exp" "$_rk_url"
    done | sort -t'|' -k3,3r -k1,1 | awk -F'|' '!seen[$1]++'

    unset _rk_json _rk_now _rk_e _rk_id _rk_exp _rk_name _rk_url
    return 0
}

# "id|name|expires_at" lines (what the panel lists). Exit 2 if the input is not a catalog.
rkp_catalog_eligible() {
    _rk_out=$(_rkp_catalog_lines) || { unset _rk_out; return 2; }
    [ -z "$_rk_out" ] || printf '%s\n' "$_rk_out" | cut -d'|' -f1-3
    unset _rk_out
    return 0
}

# Keybox url of one eligible entry (catalog on stdin); prints nothing if not listed / expired
rkp_catalog_url_for_id() {
    _rk_out=$(_rkp_catalog_lines) || { unset _rk_out; return 2; }
    printf '%s\n' "$_rk_out" | awk -F'|' -v id="$1" '$1==id { print $4; exit }'
    unset _rk_out
    return 0
}
