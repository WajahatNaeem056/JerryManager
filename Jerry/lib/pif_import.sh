# shellcheck shell=sh
# Import a user-supplied fingerprint (pif.json / pif.prop) into the built-in PIF.
# Callers must already have sourced lib/common.sh and lib/pif_lib.sh.
#
#   pif_import_file <path>
#
# Output contract (read by the WebUI): human readable lines, then exactly one of
#   IMPORT_OK            exit 0 - /data/adb/pif.prop was rewritten and read back
#   IMPORT_ERR: <why>    exit 1 - /data/adb/pif.prop is unchanged (or restored)
#
# Flow: validate file -> detect format -> parse -> map to pif.prop keys ->
# validate values -> backup -> atomic write -> read back through pif_prop_get ->
# restart GMS. The user's spoof* / DEBUG toggles are kept, never taken from the file.

PIF_IMPORT_MAX_BYTES=65536
PIF_IMPORT_KEEP_BACKUPS=5
PIF_IMPORT_BACKUP_DIR="${PIF_IMPORT_BACKUP_DIR:-/data/adb/JerryManager/PifBackup}"
PIF_IMPORT_WORK_ROOT="${PIF_IMPORT_WORK_ROOT:-/data/adb/JerryManager}"
# Identity keys the built-in PIF reads from pif.prop, in the order they are written
PIF_IMPORT_KEYS="FINGERPRINT MANUFACTURER MODEL BRAND PRODUCT DEVICE INCREMENTAL RELEASE TYPE TAGS SECURITY_PATCH DEVICE_INITIAL_SDK_INT"

_pi_err() {
  echo "IMPORT_ERR: $1"
  log "PIF" "Import failed: $1" >/dev/null 2>&1
}

# Map a key from a pif.json / pif.prop to a pif.prop key.
# Prints the canonical key, "FLAG" for spoof*/DEBUG (kept from the current config), or nothing if unknown.
_pi_normkey() {
  case "$1" in
    FINGERPRINT|MANUFACTURER|MODEL|BRAND|PRODUCT|DEVICE|INCREMENTAL|RELEASE|TYPE|TAGS|SECURITY_PATCH|DEVICE_INITIAL_SDK_INT)
      printf '%s' "$1" ;;
    VERSION.SECURITY_PATCH|*.security_patch|*.SECURITY_PATCH) printf SECURITY_PATCH ;;
    VERSION.DEVICE_INITIAL_SDK_INT|FIRST_API_LEVEL|first_api_level|*.first_api_level|*.FIRST_API_LEVEL)
      printf DEVICE_INITIAL_SDK_INT ;;
    VERSION.RELEASE) printf RELEASE ;;
    VERSION.INCREMENTAL) printf INCREMENTAL ;;
    spoofBuild|spoofProps|spoofProvider|spoofSignature|spoofVendingBuild|spoofVendingSdk|DEBUG)
      printf FLAG ;;
  esac
}

# Add one parsed key/value to $_pi_w/kv. Returns 1 (with $_pi_msg set) on a conflict.
_pi_add() {
  _pa_canon="$(_pi_normkey "$1")"
  case "$_pa_canon" in
    "")   _pi_unknown=$((_pi_unknown + 1))
          if [ "$_pi_unknown" -le 5 ]; then
            _pa_name="$(printf '%s' "$1" | tr -cd '[:print:]' | cut -c1-40)"
            _pi_unknown_names="${_pi_unknown_names:+$_pi_unknown_names, }$_pa_name"
          fi
          return 0 ;;
    FLAG) _pi_flags=$((_pi_flags + 1)); return 0 ;;
  esac
  [ -z "$2" ] && return 0
  if grep -q "^${_pa_canon}=" "$_pi_w/kv" 2>/dev/null; then
    _pa_prev="$(grep -m1 "^${_pa_canon}=" "$_pi_w/kv" | cut -d= -f2-)"
    if [ "$_pa_prev" != "$2" ]; then
      _pi_msg="Conflicting duplicate values for $_pa_canon"
      return 1
    fi
    return 0
  fi
  printf '%s=%s\n' "$_pa_canon" "$2" >> "$_pi_w/kv"
}

# pif.prop style: KEY=VALUE per line, # comments, optional quotes around the value
_pi_parse_prop() {
  _pp_n=0
  tr -d '\r' < "$1" > "$_pi_w/prop.txt"
  while IFS= read -r _pp_line || [ -n "$_pp_line" ]; do
    _pp_n=$((_pp_n + 1))
    _pp_line="${_pp_line#"${_pp_line%%[![:space:]]*}"}"
    case "$_pp_line" in ""|"#"*) continue ;; esac
    case "$_pp_line" in
      *=*) ;;
      *) _pi_msg="Line $_pp_n is not KEY=VALUE"; return 1 ;;
    esac
    _pp_key="${_pp_line%%=*}"
    _pp_val="${_pp_line#*=}"
    _pp_key="${_pp_key%"${_pp_key##*[![:space:]]}"}"
    _pp_val="${_pp_val#"${_pp_val%%[![:space:]]*}"}"
    _pp_val="${_pp_val%"${_pp_val##*[![:space:]]}"}"
    case "$_pp_val" in \"*\") _pp_val="${_pp_val#\"}"; _pp_val="${_pp_val%\"}" ;; esac
    if ! printf '%s' "$_pp_key" | grep -qE '^[A-Za-z0-9_.*]+$'; then
      _pi_msg="Line $_pp_n has an invalid key"
      return 1
    fi
    _pi_add "$_pp_key" "$_pp_val" || return 1
  done < "$_pi_w/prop.txt"
  return 0
}

# pif.json style: one flat JSON object. Without jq on the device, the object is checked
# structurally: every "key": value pair is cut out, and what is left must be only
# braces and commas (so nesting, arrays, trailing garbage and missing commas are rejected).
_pi_parse_json() {
  _pj_str='"([^"\\]|\\.)*"'
  _pj_val="(${_pj_str}|-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?|true|false|null)"
  _pj_pair="\"[^\"\\\\]*\"[[:space:]]*:[[:space:]]*${_pj_val}"
  _pj_bom="$(printf '\357\273\277')"
  tr -d '\r' < "$1" | tr '\n\t' '  ' | sed "1s/^${_pj_bom}//" > "$_pi_w/flat.txt"

  grep -oE "$_pj_pair" "$_pi_w/flat.txt" > "$_pi_w/pairs.txt" 2>/dev/null
  _pj_count=$(wc -l < "$_pi_w/pairs.txt")
  _pj_count=$((_pj_count))
  _pj_rest="$(sed -E "s/${_pj_pair}//g" "$_pi_w/flat.txt")"
  if ! printf '%s' "$_pj_rest" | grep -qE '^[[:space:]]*\{[[:space:],]*\}[[:space:]]*$'; then
    _pi_msg="Malformed JSON (expected one flat object of \"key\": value pairs)"
    return 1
  fi
  _pj_commas=$(printf '%s' "$_pj_rest" | tr -dc ',' | wc -c)
  _pj_commas=$((_pj_commas))
  if [ "$_pj_count" -eq 0 ] || [ "$_pj_commas" -ne $((_pj_count - 1)) ]; then
    _pi_msg="Malformed JSON (missing or extra comma)"
    return 1
  fi

  while IFS= read -r _pj_p; do
    _pj_key="$(printf '%s' "$_pj_p" | sed -E 's/^"([^"\\]*)"[[:space:]]*:.*$/\1/')"
    _pj_v="$(printf '%s' "$_pj_p" | sed -E 's/^"[^"\\]*"[[:space:]]*:[[:space:]]*//')"
    case "$_pj_v" in
      \"*) _pj_v="${_pj_v#\"}"; _pj_v="${_pj_v%\"}"
           _pj_v="$(printf '%s' "$_pj_v" | sed -e 's/\\\//\//g' -e 's/\\"/"/g' -e 's/\\\\/\\/g')" ;;
      null) _pj_v="" ;;
    esac
    _pi_add "$_pj_key" "$_pj_v" || return 1
  done < "$_pi_w/pairs.txt"
  return 0
}

# Value checks on the collected identity keys
_pi_validate() {
  _pv_fp="$(grep -m1 '^FINGERPRINT=' "$_pi_w/kv" 2>/dev/null | cut -d= -f2-)"
  if [ -z "$_pv_fp" ]; then
    _pi_msg="No FINGERPRINT found in file"
    return 1
  fi
  _pv_f='[^/:[:space:]]+'
  if ! printf '%s' "$_pv_fp" | grep -qE "^${_pv_f}/${_pv_f}/${_pv_f}:${_pv_f}/${_pv_f}/${_pv_f}:${_pv_f}/${_pv_f}$"; then
    _pi_msg="FINGERPRINT is not in brand/product/device:release/id/incremental:type/tags format"
    return 1
  fi
  for _pv_k in $PIF_IMPORT_KEYS; do
    _pv_v="$(grep -m1 "^${_pv_k}=" "$_pi_w/kv" 2>/dev/null | cut -d= -f2-)"
    [ -z "$_pv_v" ] && continue
    if [ "${#_pv_v}" -gt 256 ]; then _pi_msg="$_pv_k is too long"; return 1; fi
    if printf '%s' "$_pv_v" | grep -q '[\\"]' || printf '%s' "$_pv_v" | grep -q '[[:cntrl:]]'; then
      _pi_msg="$_pv_k contains unsupported characters"
      return 1
    fi
    case "$_pv_k" in
      SECURITY_PATCH)
        printf '%s' "$_pv_v" | grep -qE '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$' \
          || { _pi_msg="SECURITY_PATCH must be YYYY-MM-DD"; return 1; } ;;
      DEVICE_INITIAL_SDK_INT)
        printf '%s' "$_pv_v" | grep -qE '^[0-9]{2,3}$' \
          || { _pi_msg="DEVICE_INITIAL_SDK_INT must be a number"; return 1; } ;;
    esac
  done
  return 0
}

# New pif.prop content: imported identity + the user's current spoof toggles
_pi_compose() {
  : > "$_pi_w/new"
  for _pc_k in $PIF_IMPORT_KEYS; do
    _pc_v="$(grep -m1 "^${_pc_k}=" "$_pi_w/kv" 2>/dev/null | cut -d= -f2-)"
    [ -n "$_pc_v" ] && printf '%s=%s\n' "$_pc_k" "$_pc_v" >> "$_pi_w/new"
  done
  for _pc_k in $PIF_FLAG_KEYS; do
    _pc_v=""
    [ -f "$PIF_PROP" ] && _pc_v="$(pif_prop_get "$PIF_PROP" "$_pc_k")"
    case "$_pc_v" in true|false) ;; *)
      _pc_v=""
      [ -f "$PIF_ROOT/pif.prop" ] && _pc_v="$(pif_prop_get "$PIF_ROOT/pif.prop" "$_pc_k")"
      case "$_pc_v" in true|false) ;; *) _pc_v="" ;; esac ;;
    esac
    [ -n "$_pc_v" ] && printf '%s=%s\n' "$_pc_k" "$_pc_v" >> "$_pi_w/new"
  done
  [ -s "$_pi_w/new" ]
}

# Replace $PIF_PROP with $1 atomically (same-directory temp file + rename)
_pi_install() {
  _pn_dir="$(dirname "$PIF_PROP")"
  _pn_tmp="$_pn_dir/.pif.prop.new.$$"
  cp "$1" "$_pn_tmp" 2>/dev/null || return 1
  _pn_mode="$(stat -c %a "$PIF_PROP" 2>/dev/null)"
  chmod "${_pn_mode:-644}" "$_pn_tmp" 2>/dev/null
  chown 0:0 "$_pn_tmp" 2>/dev/null
  [ -f "$PIF_PROP" ] && chcon --reference="$PIF_PROP" "$_pn_tmp" 2>/dev/null
  mv -f "$_pn_tmp" "$PIF_PROP" 2>/dev/null || { rm -f "$_pn_tmp"; return 1; }
  return 0
}

_pi_cleanup() {
  [ -n "$_pi_w" ] && rm -rf "$_pi_w" 2>/dev/null
}

pif_import_file() {
  _pi_src="$1"
  _pi_msg=""
  _pi_unknown=0
  _pi_unknown_names=""
  _pi_flags=0
  _pi_w=""

  [ -n "$_pi_src" ] || { _pi_err "No file selected"; return 1; }
  [ -f "$_pi_src" ] && [ -r "$_pi_src" ] || { _pi_err "File not found or not readable"; return 1; }

  _pi_name="${_pi_src##*/}"
  _pi_ext="$(printf '%s' "${_pi_name##*.}" | tr 'A-Z' 'a-z')"
  [ "$_pi_name" = "${_pi_name##*.}" ] && _pi_ext=""
  case "$_pi_ext" in
    json|prop|txt) ;;
    *) _pi_err "Unsupported file type (.${_pi_ext:-none}), choose a pif.json or pif.prop file"; return 1 ;;
  esac

  _pi_size=$(wc -c < "$_pi_src" 2>/dev/null)
  _pi_size=$((_pi_size))
  [ "$_pi_size" -gt 0 ] || { _pi_err "File is empty"; return 1; }
  [ "$_pi_size" -le "$PIF_IMPORT_MAX_BYTES" ] || { _pi_err "File is too large for a fingerprint file"; return 1; }
  _pi_nonul=$(tr -d '\000' < "$_pi_src" | wc -c)
  [ $((_pi_nonul)) -eq "$_pi_size" ] || { _pi_err "File is binary, not a text fingerprint"; return 1; }

  mkdir -p "$PIF_IMPORT_WORK_ROOT" 2>/dev/null
  _pi_w="$PIF_IMPORT_WORK_ROOT/.pif_import.$$"
  rm -rf "$_pi_w"
  mkdir -p "$_pi_w" 2>/dev/null || { _pi_err "Cannot create a work directory"; return 1; }
  : > "$_pi_w/kv"

  # Format comes from the content ('{' = JSON); the extension must agree with it
  _pi_first="$(tr -d '\r' < "$_pi_src" | sed "1s/^$(printf '\357\273\277')//" | tr -d ' \t\n' | head -c 1)"
  case "$_pi_first" in
    "{") _pi_fmt=json ;;
    "[") _pi_err "JSON arrays are not supported, expected one object"; _pi_cleanup; return 1 ;;
    *)   _pi_fmt=prop ;;
  esac
  if [ "$_pi_ext" = "json" ] && [ "$_pi_fmt" != "json" ]; then
    _pi_err "Not valid JSON (the file does not start with '{')"; _pi_cleanup; return 1
  fi
  echo "Format: pif.$_pi_fmt ($_pi_name)"

  if [ "$_pi_fmt" = "json" ]; then
    _pi_parse_json "$_pi_src" || { _pi_err "$_pi_msg"; _pi_cleanup; return 1; }
  else
    _pi_parse_prop "$_pi_src" || { _pi_err "$_pi_msg"; _pi_cleanup; return 1; }
  fi
  _pi_validate || { _pi_err "$_pi_msg"; _pi_cleanup; return 1; }
  _pi_compose || { _pi_err "Could not build the new configuration"; _pi_cleanup; return 1; }

  # Backup of the file that is about to change
  _pi_bak=""
  if [ -s "$PIF_PROP" ]; then
    mkdir -p "$PIF_IMPORT_BACKUP_DIR" 2>/dev/null
    _pi_bak="$PIF_IMPORT_BACKUP_DIR/pif.prop.$(date +%Y%m%d_%H%M%S).bak"
    if ! cp -p "$PIF_PROP" "$_pi_bak" 2>/dev/null; then
      _pi_err "Could not back up the current pif.prop, nothing changed"
      _pi_cleanup; return 1
    fi
    ls -1t "$PIF_IMPORT_BACKUP_DIR"/pif.prop.*.bak 2>/dev/null | tail -n +$((PIF_IMPORT_KEEP_BACKUPS + 1)) | while IFS= read -r _pi_old; do
      rm -f "$_pi_old"
    done
    echo "Backup: ${_pi_bak##*/}"
  fi

  if ! _pi_install "$_pi_w/new"; then
    _pi_err "Could not write $PIF_PROP (permission or storage error), previous config kept"
    _pi_cleanup; return 1
  fi

  # Read the result back the same way the PIF backend does; roll back on any mismatch
  _pi_bad=""
  while IFS= read -r _pi_line; do
    _pi_k="${_pi_line%%=*}"
    _pi_v="${_pi_line#*=}"
    [ "$(pif_prop_get "$PIF_PROP" "$_pi_k")" = "$_pi_v" ] || { _pi_bad="$_pi_k"; break; }
  done < "$_pi_w/new"
  if [ -n "$_pi_bad" ]; then
    if [ -n "$_pi_bak" ]; then _pi_install "$_pi_bak"; else rm -f "$PIF_PROP"; fi
    _pi_err "Read-back check failed on $_pi_bad, previous config restored"
    _pi_cleanup; return 1
  fi

  _pi_model="$(pif_prop_get "$PIF_PROP" MODEL)"
  _pi_fpv="$(pif_prop_get "$PIF_PROP" FINGERPRINT)"
  [ -z "$_pi_model" ] && echo "Note: file has no MODEL"
  [ -z "$(pif_prop_get "$PIF_PROP" MANUFACTURER)" ] && echo "Note: file has no MANUFACTURER"
  [ "$_pi_flags" -gt 0 ] && echo "Spoof toggles in the file were ignored, your current toggles are kept"
  if [ "$_pi_unknown" -gt 0 ]; then
    [ "$_pi_unknown" -gt 5 ] && _pi_unknown_names="$_pi_unknown_names, ..."
    echo "Ignored $_pi_unknown unsupported key(s): $_pi_unknown_names"
  fi
  pif_kill_gms
  log "PIF" "Imported fingerprint from $_pi_name (${_pi_model:-unknown model})" >/dev/null 2>&1
  echo "MODEL=$_pi_model"
  echo "FINGERPRINT=$_pi_fpv"
  echo "IMPORT_OK"
  _pi_cleanup
  return 0
}
