# shellcheck shell=sh
# Tricky Store config.ini helpers: [target] package list and [default_policy] patch levels.
# Newer Tricky Store versions migrate target.txt / security_patch.txt into this file.

ini_has_sections() {
    [ -f "$1" ] && grep -qE '^[[:space:]]*\[[^]]+\]' "$1" 2>/dev/null
}

# Print the [target] entries (package, optional ! or ? suffix)
_ini_read_targets() {
    [ -f "$1" ] || return 0
    awk '
    function pkg(s) { return s ~ /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)*[!?]?$/ }
    { c = $0; sub(/\r$/, "", c); sub(/[;#].*$/, "", c); gsub(/^[ \t]+|[ \t]+$/, "", c)
      if (c ~ /^\[[^]]+\]$/) { section = c; next }
      if (section == "[target]" && pkg(c)) print c }' "$1"
}

# _ini_add_target FILE PKG [SUFFIX] — no-op when the package is already listed
_ini_add_target() {
    _iat_f="$1" _iat_p="$2" _iat_s="${3:-}"
    [ -f "$_iat_f" ] || { unset _iat_f _iat_p _iat_s; return 1; }
    case "$_iat_p" in ''|*[!A-Za-z0-9_.]*) unset _iat_f _iat_p _iat_s; return 1 ;; esac
    case "$_iat_s" in ''|'!'|'?') ;; *) _iat_s="" ;; esac
    if _ini_read_targets "$_iat_f" | sed 's/[!?]$//' | grep -Fxq "$_iat_p"; then
        unset _iat_f _iat_p _iat_s; return 0
    fi
    _iat_tmp="${_iat_f}.add.$$"
    awk -v entry="${_iat_p}${_iat_s}" '
    { c = $0; sub(/\r$/, "", c); sub(/[;#].*$/, "", c); gsub(/^[ \t]+|[ \t]+$/, "", c)
      print $0
      if (c == "[target]" && !done) { print entry; done = 1 } }
    END { if (!done) { print ""; print "[target]"; print entry } }' "$_iat_f" > "$_iat_tmp" 2>/dev/null
    _ks_commit "$_iat_f" "$_iat_tmp"; _iat_rc=$?
    rm -f "$_iat_tmp"
    unset _iat_f _iat_p _iat_s _iat_tmp
    return "$_iat_rc"
}

# _ini_remove_target FILE PKG — removes PKG, PKG! and PKG? from [target]
_ini_remove_target() {
    _irt_f="$1" _irt_p="$2"
    [ -f "$_irt_f" ] && [ -n "$_irt_p" ] || { unset _irt_f _irt_p; return 1; }
    _irt_tmp="${_irt_f}.rm.$$"
    awk -v pkg="$_irt_p" '
    { c = $0; sub(/\r$/, "", c); sub(/[;#].*$/, "", c); gsub(/^[ \t]+|[ \t]+$/, "", c)
      if (c ~ /^\[[^]]+\]$/) { section = c; print $0; next }
      if (section == "[target]" && (c == pkg || c == pkg "!" || c == pkg "?")) next
      print $0 }' "$_irt_f" > "$_irt_tmp" 2>/dev/null
    _ks_commit "$_irt_f" "$_irt_tmp"; _irt_rc=$?
    rm -f "$_irt_tmp"
    unset _irt_f _irt_p _irt_tmp
    return "$_irt_rc"
}

# _ini_set_targets FILE LISTFILE — replace the [target] package list with LISTFILE (one entry per line)
_ini_set_targets() {
    _ist_f="$1" _ist_l="$2"
    [ -f "$_ist_f" ] && [ -f "$_ist_l" ] || { unset _ist_f _ist_l; return 1; }
    _ist_tmp="${_ist_f}.set.$$"
    awk -v src="$_ist_l" '
    function pkg(s) { return s ~ /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)*[!?]?$/ }
    function emit(  i) { for (i = 1; i <= n; i++) print want[order[i]] }
    BEGIN {
      while ((getline l < src) > 0) {
        sub(/\r$/, "", l); gsub(/^[ \t]+|[ \t]+$/, "", l)
        if (l == "" || !pkg(l)) continue
        b = l; sub(/[!?]$/, "", b)
        if (!(b in want)) order[++n] = b
        want[b] = l
      }
      close(src)
    }
    { c = $0; sub(/\r$/, "", c); sub(/[;#].*$/, "", c); gsub(/^[ \t]+|[ \t]+$/, "", c)
      if (c ~ /^\[[^]]+\]$/) { section = c; print $0; if (c == "[target]" && !found) { emit(); found = 1 } next }
      if (section == "[target]" && pkg(c)) next
      print $0 }
    END { if (!found) { print ""; print "[target]"; emit() } }' "$_ist_f" > "$_ist_tmp" 2>/dev/null
    _ks_commit "$_ist_f" "$_ist_tmp"; _ist_rc=$?
    rm -f "$_ist_tmp"
    unset _ist_f _ist_l _ist_tmp
    return "$_ist_rc"
}

# _ini_set_patch FILE OS_DATE [BOOT_DATE] [VENDOR_DATE] — dates are YYYY-MM-DD.
# Writes os_patch (YYYYMM), boot_patch and vendor_patch (YYYYMMDD) into [default_policy].
_ini_set_patch() {
    _isp_f="$1" _isp_os="$2" _isp_boot="${3:-$2}" _isp_ven="${4:-$2}"
    [ -f "$_isp_f" ] || { unset _isp_f _isp_os _isp_boot _isp_ven; return 1; }
    for _isp_d in "$_isp_os" "$_isp_boot" "$_isp_ven"; do
        case "$_isp_d" in
            [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
            *) unset _isp_f _isp_os _isp_boot _isp_ven _isp_d; return 1 ;;
        esac
    done
    _isp_os6=$(printf '%s' "$_isp_os" | tr -d '-' | cut -c1-6)
    _isp_boot8=$(printf '%s' "$_isp_boot" | tr -d '-')
    _isp_ven8=$(printf '%s' "$_isp_ven" | tr -d '-')
    _isp_tmp="${_isp_f}.patch.$$"
    awk -v os="$_isp_os6" -v boot="$_isp_boot8" -v ven="$_isp_ven8" '
    function emit() {
      if (!seen["os_patch"]) print "os_patch=" os
      if (!seen["boot_patch"]) print "boot_patch=" boot
      if (!seen["vendor_patch"]) print "vendor_patch=" ven
      seen["os_patch"] = seen["boot_patch"] = seen["vendor_patch"] = 1
    }
    { c = $0; sub(/\r$/, "", c); sub(/[;#].*$/, "", c); gsub(/^[ \t]+|[ \t]+$/, "", c)
      if (c ~ /^\[[^]]+\]$/) {
        if (section == "[default_policy]") emit()
        section = c
        if (c == "[default_policy]") found = 1
        print $0; next
      }
      if (section == "[default_policy]" && c ~ /^(os_patch|boot_patch|vendor_patch)[ \t]*=/) {
        k = c; sub(/[ \t]*=.*$/, "", k)
        print k "=" (k == "os_patch" ? os : (k == "boot_patch" ? boot : ven))
        seen[k] = 1; next
      }
      print $0 }
    END {
      if (section == "[default_policy]") emit()
      if (!found) { print ""; print "[default_policy]"; emit() }
    }' "$_isp_f" > "$_isp_tmp" 2>/dev/null
    _ks_commit "$_isp_f" "$_isp_tmp"; _isp_rc=$?
    rm -f "$_isp_tmp"
    unset _isp_f _isp_os _isp_boot _isp_ven _isp_d _isp_os6 _isp_boot8 _isp_ven8 _isp_tmp
    return "$_isp_rc"
}
