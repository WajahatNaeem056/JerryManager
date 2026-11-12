# shellcheck shell=sh
# In-place file helpers. Keystore daemons (Tricky Store, OMK, TEESimulator) watch their
# config files, so edits must keep the same inode, owner and SELinux label:
# never `sed -i` / `mv` over those files.

# _ks_commit DST SRC — put SRC's content into DST (kept as .bak first). Restores on failure.
_ks_commit() {
    _kc_dst="$1" _kc_src="$2"
    [ -f "$_kc_dst" ] && [ -s "$_kc_src" ] || { unset _kc_dst _kc_src; return 1; }
    cp -p "$_kc_dst" "$_kc_dst.bak" 2>/dev/null
    if cat "$_kc_src" > "$_kc_dst" 2>/dev/null; then
        _kc_rc=0
    else
        cat "$_kc_dst.bak" > "$_kc_dst" 2>/dev/null
        _kc_rc=1
    fi
    unset _kc_dst _kc_src
    return "$_kc_rc"
}

# _ks_sed_i SED-ARGS... FILE — like `sed -i` but writes back into the same inode (FILE is the last arg)
_ks_sed_i() {
    for _ksi_file; do :; done
    [ -f "$_ksi_file" ] || { unset _ksi_file; return 1; }
    _ksi_tmp="${_ksi_file}.sedtmp.$$"
    if sed "$@" > "$_ksi_tmp" 2>/dev/null && [ -s "$_ksi_tmp" ]; then
        _ks_commit "$_ksi_file" "$_ksi_tmp"; _ksi_rc=$?
    else
        _ksi_rc=1
    fi
    rm -f "$_ksi_tmp"
    unset _ksi_file _ksi_tmp
    return "$_ksi_rc"
}
