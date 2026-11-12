# shellcheck shell=sh
# OhMyKeymint TOML helpers. Needs awk (Magisk/KSU/APatch busybox).

# true when injector.toml uses the current top-level `scoop = [ ... ]` array
omk_has_toplevel_scoop() {
    [ -f "$1" ] && grep -qE '^[[:space:]]*scoop[[:space:]]*=[[:space:]]*\[' "$1" 2>/dev/null
}

# omk_toml_set FILE SECTION KEY VALUE [keep]
# With "keep", an existing value is left untouched (key is only added when missing).
# Replaces KEY inside [SECTION]; adds it to the section (or adds the section) if missing.
# VALUE is written verbatim (use true/false, numbers, or "quoted strings").
omk_toml_set() {
    _ots_file="$1" _ots_sec="$2" _ots_key="$3" _ots_val="$4" _ots_keep="${5:-}"
    [ -f "$_ots_file" ] || return 1
    _ots_tmp="${_ots_file}.tmp.$$"
    awk -v sec="$_ots_sec" -v key="$_ots_key" -v val="$_ots_val" -v keep="$_ots_keep" '
    function trim(s) { gsub(/^[ \t]+|[ \t\r]+$/, "", s); return s }
    BEGIN { insec = 0; found = 0; seen = 0 }
    {
        line = $0; t = trim(line)
        if (t ~ /^\[.*\]$/) {
            if (insec && !found) { print key " = " val; found = 1 }
            name = t; gsub(/^\[|\]$/, "", name); name = trim(name)
            insec = (name == sec); if (insec) seen = 1
            print line; next
        }
        if (insec && !found && t ~ ("^" key "[ \t]*=")) { found = 1; if (keep == "keep") { print line } else { print key " = " val }; next }
        print line
    }
    END {
        if (insec && !found) print key " = " val
        if (!seen) { print ""; print "[" sec "]"; print key " = " val }
    }' "$_ots_file" > "$_ots_tmp" 2>/dev/null
    if [ -s "$_ots_tmp" ]; then
        cat "$_ots_tmp" > "$_ots_file" 2>/dev/null; _ots_rc=$?
    else
        _ots_rc=1
    fi
    rm -f "$_ots_tmp"
    unset _ots_file _ots_sec _ots_key _ots_val _ots_keep _ots_tmp
    return "$_ots_rc"
}

# omk_scoop_add FILE PACKAGE — add PACKAGE to the top-level scoop array (no-op if present)
omk_scoop_add() {
    _osa_file="$1" _osa_pkg="$2"
    [ -f "$_osa_file" ] && [ -n "$_osa_pkg" ] || return 1
    grep -q "\"$_osa_pkg\"" "$_osa_file" 2>/dev/null && return 0
    _osa_tmp="${_osa_file}.tmp.$$"
    awk -v pkg="$_osa_pkg" '
    BEGIN { d = 0 }
    !d && /^[ \t]*scoop[ \t]*=[ \t]*\[/ {
        idx = index($0, "["); pre = substr($0, 1, idx); post = substr($0, idx + 1)
        t = post; gsub(/[ \t\r]/, "", t)
        if (t == "]")      print pre "\"" pkg "\"]"
        else if (t == "")  print pre "\"" pkg "\","
        else               print pre "\"" pkg "\", " post
        d = 1; next
    }
    { print }' "$_osa_file" > "$_osa_tmp" 2>/dev/null
    if [ -s "$_osa_tmp" ]; then
        cat "$_osa_tmp" > "$_osa_file" 2>/dev/null; _osa_rc=$?
    else
        _osa_rc=1
    fi
    rm -f "$_osa_tmp"
    unset _osa_file _osa_pkg _osa_tmp
    return "$_osa_rc"
}

# omk_scoop_remove FILE PACKAGE — remove PACKAGE from the scoop array (no-op if absent)
# Handles both layouts: top-level `scoop = [ ... ]` and `[scoop]` + `packages = [ ... ]`.
omk_scoop_remove() {
    _osr_file="$1" _osr_pkg="$2"
    [ -f "$_osr_file" ] && [ -n "$_osr_pkg" ] || return 1
    grep -q "\"$_osr_pkg\"" "$_osr_file" 2>/dev/null || return 0
    _osr_tmp="${_osr_file}.tmp.$$"
    awk -v pkg="$_osr_pkg" '
    BEGIN { tok = "\"" pkg "\""; inarr = 0 }
    {
        line = $0; hit = 0
        if (!inarr && line ~ /^[ \t]*(scoop|packages)[ \t]*=[ \t]*\[/) inarr = 1
        if (inarr) {
            while ((i = index(line, tok)) > 0) {
                rest = substr(line, i + length(tok))
                sub(/^[ \t]*,[ \t]*/, "", rest)
                line = substr(line, 1, i - 1) rest
                hit = 1
            }
            if (hit) gsub(/,[ \t]*\]/, "]", line)
            if (index($0, "]") > 0) inarr = 0
        }
        if (hit && line ~ /^[ \t]*$/) next
        print line
    }' "$_osr_file" > "$_osr_tmp" 2>/dev/null
    if [ -s "$_osr_tmp" ]; then
        cat "$_osr_tmp" > "$_osr_file" 2>/dev/null; _osr_rc=$?
    else
        _osr_rc=1
    fi
    rm -f "$_osr_tmp"
    unset _osr_file _osr_pkg _osr_tmp
    return "$_osr_rc"
}

# omk_scoop_init FILE — make sure a top-level `scoop = []` exists (placed before the first [table],
# since a top-level key written after a table header would belong to that table). No-op if present.
omk_scoop_init() {
    _osi_file="$1"
    [ -f "$_osi_file" ] || return 1
    omk_has_toplevel_scoop "$_osi_file" && return 0
    _osi_tmp="${_osi_file}.tmp.$$"
    awk 'BEGIN { d = 0 }
    !d && /^[ \t]*\[/ { print "scoop = []"; print ""; d = 1 }
    { print }
    END { if (!d) print "scoop = []" }' "$_osi_file" > "$_osi_tmp" 2>/dev/null
    if [ -s "$_osi_tmp" ]; then
        cat "$_osi_tmp" > "$_osi_file" 2>/dev/null; _osi_rc=$?
    else
        _osi_rc=1
    fi
    rm -f "$_osi_tmp"
    unset _osi_file _osi_tmp
    return "$_osi_rc"
}

# omk_scoop_list FILE — print the packages of the top-level scoop array (single- or multi-line)
omk_scoop_list() {
    [ -f "$1" ] || return 0
    awk '
    !inarr && /^[ \t]*scoop[ \t]*=[ \t]*\[/ { inarr = 1; sub(/^[^[]*\[/, "") }
    inarr {
      line = $0; t = $0; sub(/#.*$/, "", t)
      while (match(line, /"[^"]*"/)) { print substr(line, RSTART + 1, RLENGTH - 2); line = substr(line, RSTART + RLENGTH) }
      if (index(t, "]") > 0) exit
    }' "$1"
}
