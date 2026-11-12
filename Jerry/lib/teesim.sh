# shellcheck shell=sh
# TEESimulator config.json helpers (default profile block, keybox field, patchLevel, apps list)

for _tsl_dir in "$MODDIR/lib" "$MODDIR/../lib" "$MODPATH/lib"; do
    [ -f "$_tsl_dir/inplace.sh" ] && { . "$_tsl_dir/inplace.sh"; break; }
done
unset _tsl_dir

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
        _ks_sed_i "${_tskf_start},${_tskf_end}s|\"keybox\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"keybox\": \"keybox.xml\"|" "$_tskf_cfg"
    else
        _ks_sed_i "${_tskf_start}a\\    \"keybox\": \"keybox.xml\"," "$_tskf_cfg"
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

    _tsp_repl="\"patchLevel\": { \"system\": \"$_tsp_ym\", \"vendor\": \"$_tsp_vendor\", \"boot\": \"$_tsp_boot\" }"
    if sed -n "${_tsp_start},${_tsp_end}p" "$_tsp_cfg" | grep -q '"patchLevel"'; then
        # Replace the existing patchLevel value whether it is written on one line or spread over several
        _tsp_tmp="${_tsp_cfg}.patch.$$"
        awk -v s="$_tsp_start" -v e="$_tsp_end" -v repl="$_tsp_repl" '
        NR >= s && NR <= e {
          if (skipping) {
            if ($0 ~ /}/) { skipping = 0; print ind repl ($0 ~ /},[ \t]*$/ ? "," : "") }
            next
          }
          if ($0 ~ /"patchLevel"[ \t]*:/) {
            match($0, /^[ \t]*/); ind = substr($0, 1, RLENGTH)
            if ($0 ~ /}/) { print ind repl ($0 ~ /},[ \t]*$/ ? "," : ""); next }
            skipping = 1; next
          }
        }
        { print }' "$_tsp_cfg" > "$_tsp_tmp" 2>/dev/null
        _ks_commit "$_tsp_cfg" "$_tsp_tmp"
        rm -f "$_tsp_tmp"
    else
        _ks_sed_i "${_tsp_start}a\\    $_tsp_repl," "$_tsp_cfg"
    fi
    unset _tsp_cfg _tsp_date _tsp_boot _tsp_vendor _tsp_ym _tsp_range _tsp_start _tsp_end _tsp_repl _tsp_tmp
}

# Add a package to the "apps" array of the "default" profile (no-op if already there).
# Falls back to the first "apps" array when no default profile block can be located.
# The array is rebuilt (any shape: [], [\n], one line, several lines), never patched line by line.
_teesim_add_app() {
    _taa_cfg="$1" _taa_pkg="$2"
    [ -f "$_taa_cfg" ] && [ -n "$_taa_pkg" ] || { unset _taa_cfg _taa_pkg; return 1; }

    _taa_s=1 _taa_e=999999
    _taa_range=$(_teesim_default_range "$_taa_cfg") && { set -- $_taa_range; _taa_s=$1; _taa_e=$2; }

    sed -n "${_taa_s},${_taa_e}p" "$_taa_cfg" | grep -q "\"$_taa_pkg\"" 2>/dev/null && { unset _taa_cfg _taa_pkg _taa_s _taa_e _taa_range; return 0; }

    _taa_tmp="${_taa_cfg}.tmp.$$"
    _taa_lst="${_taa_cfg}.add.$$"
    printf '%s\n' "$_taa_pkg" > "$_taa_lst"
    awk -v pkg="$_taa_pkg" -v s="$_taa_s" -v e="$_taa_e" '
    BEGIN { state = 0; n = 0; done = 0 }
    {
        if (state == 0 && !done && NR >= s && NR <= e && $0 ~ /"apps"[ \t]*:[ \t]*\[/) {
            match($0, /^[ \t]*/); ind = substr($0, 1, RLENGTH)
            b = index($0, "[")
            prefix = substr($0, 1, b)
            text = substr($0, b + 1)
            state = 1
        } else if (state == 1) {
            text = text "\n" $0
        } else { print; next }
        c = index(text, "]")
        if (c == 0) next
        suffix = substr(text, c + 1)
        body = substr(text, 1, c - 1)
        while (match(body, /"[^"]*"/)) {
            list[++n] = substr(body, RSTART, RLENGTH)
            body = substr(body, RSTART + RLENGTH)
        }
        list[++n] = "\"" pkg "\""
        print prefix
        for (k = 1; k <= n; k++) print ind "    " list[k] (k < n ? "," : "")
        print ind "]" suffix
        state = 0; done = 1
    }
    END { if (state == 1) exit 2; if (!done) exit 3 }' "$_taa_cfg" > "$_taa_tmp" 2>/dev/null
    _taa_arc=$?
    if [ "$_taa_arc" -eq 0 ] && [ -s "$_taa_tmp" ] && _teesim_verify_edit "$_taa_cfg" "$_taa_tmp" add "$_taa_lst"; then
        _ks_commit "$_taa_cfg" "$_taa_tmp"; _taa_rc=$?
    else
        _taa_rc=1
    fi
    rm -f "$_taa_tmp" "$_taa_lst"
    unset _taa_cfg _taa_pkg _taa_s _taa_e _taa_range _taa_tmp _taa_arc _taa_lst
    return "$_taa_rc"
}

# Remove every package listed in LISTFILE (one per line) from the "apps" arrays of CFG, in ONE pass.
# SCOPE "default" (default): only the default profile; "all": every profile's apps array.
# JSON has no trailing commas, so an array that changed is rebuilt; untouched arrays stay byte-identical.
_teesim_remove_apps() {
    _tra_cfg="$1" _tra_list="$2" _tra_scope="${3:-default}"
    [ -f "$_tra_cfg" ] && [ -f "$_tra_list" ] || { unset _tra_cfg _tra_list _tra_scope; return 1; }

    _tra_s=1 _tra_e=999999
    if [ "$_tra_scope" != "all" ]; then
        _tra_range=$(_teesim_default_range "$_tra_cfg") && { set -- $_tra_range; _tra_s=$1; _tra_e=$2; }
    fi

    _tra_tmp="${_tra_cfg}.tmp.$$"
    awk -v lf="$_tra_list" -v s="$_tra_s" -v e="$_tra_e" -v once="$([ "$_tra_scope" = "all" ] && echo 0 || echo 1)" '
    BEGIN {
        state = 0; done = 0
        while ((getline p < lf) > 0) { gsub(/\r/, "", p); if (p != "") del["\"" p "\""] = 1 }
        close(lf)
    }
    {
        if (state == 0 && !(once == 1 && done) && NR >= s && NR <= e && $0 ~ /"apps"[ \t]*:[ \t]*\[/) {
            match($0, /^[ \t]*/); ind = substr($0, 1, RLENGTH)
            b = index($0, "[")
            prefix = substr($0, 1, b)
            text = substr($0, b + 1)
            state = 1; n = 0; hit = 0
            for (k in list) delete list[k]
        } else if (state == 1) {
            text = text "\n" $0
        } else { print; next }
        c = index(text, "]")
        if (c == 0) next
        suffix = substr(text, c + 1)
        body = substr(text, 1, c - 1)
        while (match(body, /"[^"]*"/)) {
            item = substr(body, RSTART, RLENGTH)
            body = substr(body, RSTART + RLENGTH)
            if (item in del) hit = 1; else list[++n] = item
        }
        if (!hit) { print prefix text }
        else if (n == 0) { print prefix "]" suffix }
        else {
            print prefix
            for (k = 1; k <= n; k++) print ind "    " list[k] (k < n ? "," : "")
            print ind "]" suffix
        }
        state = 0; done = 1
    }
    END { if (state == 1) exit 2 }' "$_tra_cfg" > "$_tra_tmp" 2>/dev/null
    _tra_arc=$?
    if [ "$_tra_arc" -eq 0 ] && [ -s "$_tra_tmp" ] && _teesim_verify_edit "$_tra_cfg" "$_tra_tmp" remove "$_tra_list"; then
        _ks_commit "$_tra_cfg" "$_tra_tmp"; _tra_rc=$?
    else
        _tra_rc=1
    fi
    rm -f "$_tra_tmp"
    unset _tra_cfg _tra_list _tra_scope _tra_s _tra_e _tra_range _tra_tmp _tra_arc
    return "$_tra_rc"
}

# Remove one package (no-op if absent). Optional SCOPE as in _teesim_remove_apps.
_teesim_remove_app() {
    _trs_cfg="$1" _trs_pkg="$2" _trs_scope="${3:-default}"
    [ -f "$_trs_cfg" ] && [ -n "$_trs_pkg" ] || { unset _trs_cfg _trs_pkg _trs_scope; return 1; }
    _trs_list="${_trs_cfg}.rm.$$"
    printf '%s\n' "$_trs_pkg" > "$_trs_list"
    _teesim_remove_apps "$_trs_cfg" "$_trs_list" "$_trs_scope"; _trs_rc=$?
    rm -f "$_trs_list"
    unset _trs_cfg _trs_pkg _trs_scope _trs_list
    return "$_trs_rc"
}

# ---- Robustness helpers: JSON validation, pretty-printing, guarded edits ----

# Succeeds when FILE is balanced, quote-aware JSON starting with an object
_teesim_json_ok() {
    [ -s "$1" ] || return 1
    awk '
    BEGIN { d = 0; instr = 0; esc = 0; first = "" }
    { n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (instr) { if (esc) esc = 0; else if (c == "\\") esc = 1; else if (c == "\"") instr = 0; continue }
        if (c == " " || c == "\t" || c == "\r") continue
        if (first == "") first = c
        if (c == "\"") instr = 1
        else if (c == "{" || c == "[") { d++; st[d] = c }
        else if (c == "}" || c == "]") {
          if (d < 1) bad = 1
          else if ((c == "}" && st[d] != "{") || (c == "]" && st[d] != "[")) bad = 1
          d--
        }
      } }
    END { if (bad || instr || d != 0 || first != "{") exit 1; exit 0 }' "$1"
}

# Stricter grammar check: catches trailing commas, missing commas and misplaced values that the
# bracket-balance check above cannot see. Comments or other non-JSON text make it fail, so callers
# only enforce it on files that already passed it before the edit.
_teesim_json_strict() {
    [ -s "$1" ] || return 1
    awk '
    function val(   ) { if (prev == "value" || prev == "close") bad = 1; prev = "value" }
    BEGIN { instr = 0; esc = 0; prev = "start"; d = 0; tok = 0 }
    { n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (instr) { if (esc) esc = 0; else if (c == "\\") esc = 1; else if (c == "\"") { instr = 0; prev = "value" }; continue }
        if (c == " " || c == "\t" || c == "\r") { tok = 0; continue }
        if (c == "\"") { if (prev == "value" || prev == "close") bad = 1; instr = 1; tok = 0 }
        else if (c == "{" || c == "[") { if (prev == "value" || prev == "close") bad = 1; prev = "open"; d++; tok = 0 }
        else if (c == "}" || c == "]") { if (prev == "comma" || prev == "colon") bad = 1; prev = "close"; d--; tok = 0 }
        else if (c == ",") { if (prev != "value" && prev != "close") bad = 1; prev = "comma"; tok = 0 }
        else if (c == ":") { if (prev != "value") bad = 1; prev = "colon"; tok = 0 }
        else { if (!tok) { if (prev == "value" || prev == "close") bad = 1; prev = "value"; tok = 1 } }
      } }
    END { if (bad || instr || d != 0) exit 1; exit 0 }' "$1"
}

# ---- JSON tokenizer ----
# Reads config.json into one record per line, never modifies the file:
#   P <profile id> | K keybox | M mode | O osVersion | S/V/B patchLevel | I <field> <v> |
#   A <package> | X <key> <json value> | T <top-level key> <json value>
# Used to READ every profile's apps, and to VERIFY that an edit changed only what it should.
_teesim_to_ir() {
  _tti_file="$1"
  [ -f "$_tti_file" ] || { unset _tti_file; return 1; }
  awk '
    BEGIN {
      while ((getline line < ARGV[1]) > 0) raw = raw line "\n"
      close(ARGV[1])
      ARGV[1] = ""
      n = split_json(raw, tok)
      i = 1
      while (i <= n) {
        if (tok[i] == "\"profiles\"" && tok[i+1] == ":") {
          i += 2
          if (tok[i] != "{") { i++; continue }
          i++
          while (i <= n && tok[i] != "}") {
            if (tok[i] ~ /^"/) {
              id = unquote(tok[i]); i++
              if (tok[i] == ":") i++
              if (tok[i] != "{") continue
              print "P " id
              i = parse_profile(++i, tok, n)
              if (tok[i] == ",") i++
              continue
            }
            i++
          }
          break
        }
        if (tok[i] ~ /^"/ && tok[i] != "\"version\"") {
          tk = unquote(tok[i]); i++
          if (tok[i] == ":") i++
          if (tok[i] ~ /^"/) print "T " tk " " json_quote(unquote(tok[i]))
          else if (tok[i] == "{" || tok[i] == "[") i = skip_value(i, tok, n)
          else print "T " tk " " tok[i]
          i++
          continue
        }
        i++
      }
    }

    function unquote(s) {
      gsub(/^"/, "", s); gsub(/"$/, "", s)
      gsub(/\\"/, "\"", s); gsub(/\\\\/, "\\", s)
      return s
    }

    function json_quote(s,   out, i, c) {
      out = "\""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\"") out = out "\\\""
        else if (c == "\\") out = out "\\\\"
        else out = out c
      }
      return out "\""
    }

    function parse_profile(i, tok, n,   key, val) {
      while (i <= n && tok[i] != "}") {
        if (tok[i] !~ /^"/) { i++; continue }
        key = unquote(tok[i]); i++
        if (tok[i] == ":") i++
        if (key == "apps" && tok[i] == "[") {
          i++
          while (i <= n && tok[i] != "]") {
            if (tok[i] ~ /^"/) print "A " unquote(tok[i])
            i++
          }
          if (tok[i] == "]") i++
        } else if (key == "patchLevel" && tok[i] == "{") {
          i++
          while (i <= n && tok[i] != "}") {
            if (tok[i] ~ /^"/) {
              val = unquote(tok[i]); i++
              if (tok[i] == ":") i++
              if (tok[i] ~ /^"/) {
                if (val == "system") print "S " unquote(tok[i])
                else if (val == "vendor") print "V " unquote(tok[i])
                else if (val == "boot") print "B " unquote(tok[i])
                i++
              }
            } else i++
          }
          if (tok[i] == "}") i++
        } else if (tok[i] ~ /^"/) {
          val = unquote(tok[i]); i++
          if (key == "keybox") print "K " val
          else if (key == "mode") print "M " val
          else if (key == "osVersion") print "O " val
          else if (key == "brand" || key == "device" || key == "product" ||
                   key == "manufacturer" || key == "model" || key == "serial" ||
                   key == "imei" || key == "meid" || key == "imei2")
            print "I " key " " val
          else print "X " key " " json_quote(val)
        } else if (tok[i] == "{" || tok[i] == "[") {
          i = skip_value(i, tok, n)
        } else {
          print "X " key " " tok[i]
          i++
        }
        if (tok[i] == ",") i++
      }
      if (tok[i] == "}") i++
      return i
    }

    function skip_value(i, tok, n,   depth, t) {
      t = tok[i]
      if (t == "{") {
        depth = 1; i++
        while (i <= n && depth > 0) {
          if (tok[i] == "{") depth++
          else if (tok[i] == "}") depth--
          i++
        }
        return i
      }
      if (t == "[") {
        depth = 1; i++
        while (i <= n && depth > 0) {
          if (tok[i] == "[") depth++
          else if (tok[i] == "]") depth--
          i++
        }
        return i
      }
      return i + 1
    }

    function split_json(s, out,   i, c, n, q, esc, buf) {
      n = 0; i = 1; buf = ""
      while (i <= length(s)) {
        c = substr(s, i, 1)
        if (c ~ /[ \t\r\n]/) { i++; continue }
        if (c == "\"" ) {
          q = "\""; esc = 0; i++
          while (i <= length(s)) {
            c = substr(s, i, 1)
            q = q c
            if (esc) esc = 0
            else if (c == "\\") esc = 1
            else if (c == "\"") { i++; break }
            i++
          }
          out[++n] = q
          continue
        }
        if (c ~ /[{}\[\]:,]/) { out[++n] = c; i++; continue }
        buf = ""
        while (i <= length(s)) {
          c = substr(s, i, 1)
          if (c ~ /[ \t\r\n{}\[\]:,]/) break
          buf = buf c; i++
        }
        if (buf != "") out[++n] = buf
      }
      return n
    }
  ' "$_tti_file"
  unset _tti_file
}

# Records of CFG as "<profile>\t<record>" lines (P lines dropped)
_teesim_ir_flat() {
    _teesim_to_ir "$1" 2>/dev/null | awk '/^P / { cur = substr($0, 3); next } { print cur "\t" $0 }'
}

# _teesim_verify_edit OLD NEW MODE LISTFILE
#   MODE add    : NEW == OLD plus exactly one "A <pkg>" record, <pkg> being the one line of LISTFILE
#   MODE remove : NEW == OLD minus "A <pkg>" records whose pkg is in LISTFILE, nothing else changed
# Anything else (a lost field, a lost profile, a mangled array) fails, and the caller keeps the old file.
_teesim_verify_edit() {
    _tve_old="${2%.new*}.vold.$$" _tve_new="${2%.new*}.vnew.$$"
    _teesim_ir_flat "$1" > "$_tve_old"; _teesim_ir_flat "$2" > "$_tve_new"
    awk -v mode="$3" -v lf="$4" '
    BEGIN { while ((getline p < lf) > 0) { gsub(/\r/, "", p); if (p != "") ok["A " p] = 1 } close(lf) }
    FILENAME == ARGV[1] { old[$0]++; next }   # not FNR==NR: OLD may be empty
    { nw[$0]++ }
    END {
        added = 0; bad = 0
        for (l in nw) { d = nw[l] - (l in old ? old[l] : 0); if (d > 0) { added += d; r = l; sub(/^[^\t]*\t/, "", r); if (mode != "add" || !(r in ok)) bad = 1 } }
        for (l in old) { d = old[l] - (l in nw ? nw[l] : 0)
            if (d > 0) { if (mode != "remove") bad = 1; else { r = l; sub(/^[^\t]*\t/, "", r); if (!(r in ok)) bad = 1 } } }
        if (mode == "add" && added != 1) bad = 1
        exit bad
    }' "$_tve_old" "$_tve_new"
    _tve_rc=$?
    rm -f "$_tve_old" "$_tve_new"
    unset _tve_old _tve_new
    return "$_tve_rc"
}

# Print FILE as pretty JSON (one token per line, 2-space indent) so the line-based edits work on compact files
_teesim_pretty() {
    awk '
    function app(c) { if (cur == "") curind = ind; cur = cur c }
    function flush() { if (cur != "") { pad = ""; for (k = 0; k < curind; k++) pad = pad "  "; L[++N] = pad cur; cur = "" } }
    BEGIN { ind = 0; instr = 0; esc = 0; lastopen = 0; N = 0; cur = "" }
    { n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (instr) { app(c); if (esc) esc = 0; else if (c == "\\") esc = 1; else if (c == "\"") instr = 0; continue }
        if (c == " " || c == "\t" || c == "\r") continue
        if (c == "\"") { app(c); instr = 1; lastopen = 0 }
        else if (c == "{" || c == "[") { app(c); flush(); ind++; lastopen = 1 }
        else if (c == "}" || c == "]") {
          if (lastopen) { ind--; L[N] = L[N] c; lastopen = 0 }
          else { flush(); ind--; app(c); lastopen = 0 }
        }
        else if (c == ",") { app(c); flush(); lastopen = 0 }
        else if (c == ":") { app(": "); lastopen = 0 }
        else { app(c); lastopen = 0 }
      } }
    END { flush(); for (i = 1; i <= N; i++) print L[i] }' "$1"
}

_teesim_normalize() {
    _tn_cfg="$1"
    [ -f "$_tn_cfg" ] || { unset _tn_cfg; return 1; }
    _tn_tmp="${_tn_cfg}.pretty.$$"
    _teesim_pretty "$_tn_cfg" > "$_tn_tmp" 2>/dev/null
    if _teesim_json_ok "$_tn_tmp"; then
        _ks_commit "$_tn_cfg" "$_tn_tmp"; _tn_rc=$?
    else
        _tn_rc=1
    fi
    rm -f "$_tn_tmp"
    unset _tn_cfg _tn_tmp
    return "$_tn_rc"
}

# _teesim_safe_edit CFG FUNC ARGS... — run FUNC CFG ARGS... with validation and rollback.
# Compact (single-line) config.json is pretty-printed first so the edit helpers can find the default profile.
_teesim_safe_edit() {
    _tse_cfg="$1" _tse_fn="$2"; shift 2
    [ -f "$_tse_cfg" ] || { unset _tse_cfg _tse_fn; return 1; }
    if ! _teesim_json_ok "$_tse_cfg"; then
        log "TEESIM" "config.json is not valid JSON — left unchanged"
        unset _tse_cfg _tse_fn; return 1
    fi
    _teesim_default_range "$_tse_cfg" >/dev/null 2>&1 || _teesim_normalize "$_tse_cfg"
    _tse_strict=0
    _teesim_json_strict "$_tse_cfg" && _tse_strict=1
    cp -p "$_tse_cfg" "$_tse_cfg.jerrybak" 2>/dev/null
    "$_tse_fn" "$_tse_cfg" "$@"; _tse_rc=$?
    if [ "$_tse_rc" -eq 0 ] && { ! _teesim_json_ok "$_tse_cfg" || { [ "$_tse_strict" = "1" ] && ! _teesim_json_strict "$_tse_cfg"; }; }; then
        cat "$_tse_cfg.jerrybak" > "$_tse_cfg" 2>/dev/null
        log "TEESIM" "Edit produced invalid JSON — config.json restored"
        _tse_rc=1
    fi
    unset _tse_cfg _tse_fn _tse_strict
    return "$_tse_rc"
}

# Print the plain package names in the default profile's "apps" list (uid:/pkg@user tokens are skipped)
# SCOPE "all" lists the apps array of every profile (default: default profile only).
_teesim_list_apps() {
    _tla_src="$1" _tla_scope="${2:-default}" _tla_tmp=""
    [ -f "$_tla_src" ] || { unset _tla_src _tla_scope _tla_tmp; return 0; }
    if [ "$_tla_scope" = "all" ]; then
        # every profile, read with the tokenizer (any layout; the file is not touched)
        _teesim_to_ir "$_tla_src" 2>/dev/null | awk '/^A / { print substr($0, 3) }'
        unset _tla_src _tla_scope _tla_tmp
        return 0
    fi
    if ! _teesim_default_range "$_tla_src" >/dev/null 2>&1; then
        _tla_tmp="${_tla_src}.read.$$"
        _teesim_pretty "$_tla_src" > "$_tla_tmp" 2>/dev/null
        _tla_src="$_tla_tmp"
    fi
    _tla_range=$(_teesim_default_range "$_tla_src" 2>/dev/null)
    if [ -n "$_tla_range" ]; then
        _tla_s=${_tla_range%% *}; _tla_e=${_tla_range##* }
        sed -n "${_tla_s},${_tla_e}p" "$_tla_src" | awk -v all="$([ "$_tla_scope" = "all" ] && echo 1 || echo 0)" '
        !inapps && /"apps"[ \t]*:/ { inapps = 1; sub(/^.*"apps"[ \t]*:[ \t]*/, "") }
        inapps {
          line = $0; t = $0; sub(/#.*$/, "", t)
          while (match(line, /"[^"]*"/)) { v = substr(line, RSTART + 1, RLENGTH - 2); line = substr(line, RSTART + RLENGTH)
            if (v ~ /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)*$/) print v }
          if (index(t, "]") > 0) { if (all != 1) exit; inapps = 0 }
        }'
    fi
    [ -n "$_tla_tmp" ] && rm -f "$_tla_tmp"
    unset _tla_src _tla_scope _tla_tmp _tla_range _tla_s _tla_e
    return 0
}
