# shellcheck shell=sh
# TEESimulator config.json helpers (default profile block, keybox field, patchLevel, apps list)

# Line range of the "default" profile's { ... } block in config.json
_teesim_default_range() {
    _tdr_cfg="$1"
    _tdr_start=$(grep -n '"default"[[:space:]]*:' "$_tdr_cfg" | head -n1 | cut -d: -f1)
    [ -n "$_tdr_start" ] || { unset _tdr_cfg _tdr_start; return 1; }

    _tdr_depth=0 _tdr_end="" _tdr_lineno=0
    while IFS= read -r _tdr_line; do
        _tdr_lineno=$((_tdr_lineno + 1))
        [ "$_tdr_lineno" -lt "$_tdr_start" ] && continue
        _tdr_open=$(printf '%s' "$_tdr_line" | tr -dc '{' | wc -c)
        _tdr_close=$(printf '%s' "$_tdr_line" | tr -dc '}' | wc -c)
        _tdr_depth=$((_tdr_depth + _tdr_open - _tdr_close))
        if [ "$_tdr_lineno" -gt "$_tdr_start" ] && [ "$_tdr_depth" -le 0 ]; then
            _tdr_end=$_tdr_lineno
            break
        fi
    done < "$_tdr_cfg"
    [ -n "$_tdr_end" ] || { unset _tdr_cfg _tdr_start _tdr_end _tdr_depth _tdr_lineno _tdr_line; return 1; }
    printf '%s %s\n' "$_tdr_start" "$_tdr_end"
    unset _tdr_cfg _tdr_start _tdr_end _tdr_depth _tdr_lineno _tdr_open _tdr_close _tdr_line
}

# Set "keybox" to "keybox.xml" inside the "default" profile block only
_teesim_set_keybox_field() {
    _tskf_cfg="$1"
    [ -f "$_tskf_cfg" ] || { unset _tskf_cfg; return 1; }
    _tskf_range=$(_teesim_default_range "$_tskf_cfg") || { unset _tskf_cfg _tskf_range; return 1; }
    set -- $_tskf_range; _tskf_start=$1; _tskf_end=$2

    if sed -n "${_tskf_start},${_tskf_end}p" "$_tskf_cfg" | grep -q '"keybox"[[:space:]]*:[[:space:]]*"'; then
        sed -i "${_tskf_start},${_tskf_end}s|\"keybox\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"keybox\": \"keybox.xml\"|" "$_tskf_cfg"
    else
        sed -i "${_tskf_start}a\\    \"keybox\": \"keybox.xml\"," "$_tskf_cfg"
    fi
    unset _tskf_cfg _tskf_range _tskf_start _tskf_end
}

# Write system/boot/vendor patch dates ($3/$4 default to $2) into patchLevel
_teesim_set_patch() {
    _tsp_cfg="$1" _tsp_date="$2" _tsp_boot="${3:-$2}" _tsp_vendor="${4:-$2}"
    [ -f "$_tsp_cfg" ] && [ -n "$_tsp_date" ] || { unset _tsp_cfg _tsp_date _tsp_boot _tsp_vendor; return 1; }
    for _tsp_check in "$_tsp_date" "$_tsp_boot" "$_tsp_vendor"; do
        case "$_tsp_check" in
            [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
            *) unset _tsp_cfg _tsp_date _tsp_boot _tsp_vendor _tsp_check; return 1 ;;
        esac
    done
    unset _tsp_check
    _tsp_ym=$(printf '%s' "$_tsp_date" | cut -d'-' -f1-2)
    _tsp_range=$(_teesim_default_range "$_tsp_cfg") || { unset _tsp_cfg _tsp_date _tsp_boot _tsp_vendor _tsp_ym; return 1; }
    set -- $_tsp_range; _tsp_start=$1; _tsp_end=$2

    if sed -n "${_tsp_start},${_tsp_end}p" "$_tsp_cfg" | grep -q '"patchLevel"'; then
        sed -i "${_tsp_start},${_tsp_end}s|\"patchLevel\"[[:space:]]*:[[:space:]]*{[^}]*}|\"patchLevel\": { \"system\": \"$_tsp_ym\", \"vendor\": \"$_tsp_vendor\", \"boot\": \"$_tsp_boot\" }|" "$_tsp_cfg"
    else
        sed -i "${_tsp_start}a\\    \"patchLevel\": { \"system\": \"$_tsp_ym\", \"vendor\": \"$_tsp_vendor\", \"boot\": \"$_tsp_boot\" }," "$_tsp_cfg"
    fi
    unset _tsp_cfg _tsp_date _tsp_boot _tsp_vendor _tsp_ym _tsp_range _tsp_start _tsp_end
}

# Add a package to the "apps" array (no-op if already present)
_teesim_add_app() {
    _taa_cfg="$1" _taa_pkg="$2"
    [ -f "$_taa_cfg" ] && [ -n "$_taa_pkg" ] || { unset _taa_cfg _taa_pkg; return 1; }
    grep -q "\"$_taa_pkg\"" "$_taa_cfg" 2>/dev/null && { unset _taa_cfg _taa_pkg; return 0; }

    _taa_start=$(grep -n '"apps"' "$_taa_cfg" | head -n1 | cut -d: -f1)
    [ -n "$_taa_start" ] || { unset _taa_cfg _taa_pkg _taa_start; return 1; }
    _taa_line=$(sed -n "${_taa_start}p" "$_taa_cfg")
    case "$_taa_line" in
        *'[]'*|*'[ ]'*) sed -i "${_taa_start}s|\[[[:space:]]*\]|[\"$_taa_pkg\"]|" "$_taa_cfg" ;;
        *) sed -i "${_taa_start}a\\        \"$_taa_pkg\"," "$_taa_cfg" ;;
    esac
    unset _taa_cfg _taa_pkg _taa_start _taa_line
}
