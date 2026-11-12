# shellcheck shell=sh

# Helper libraries (MODDIR is the module root or features/)
for _ks_lib in inplace teesim omk ini; do
    for _ks_dir in "$MODDIR/lib" "$MODDIR/../lib" "$MODPATH/lib"; do
        [ -f "$_ks_dir/$_ks_lib.sh" ] && { . "$_ks_dir/$_ks_lib.sh"; break; }
    done
done
unset _ks_dir _ks_lib

_module_enabled() {
    _me_id="$1"
    for _me_dir in "/data/adb/modules/$_me_id" "/data/adb/modules_update/$_me_id"; do
        [ -d "$_me_dir" ] || continue
        [ -f "$_me_dir/disable" ] && continue
        _me_name=$(grep "^name=" "$_me_dir/module.prop" 2>/dev/null | cut -d= -f2-)
        printf '%s\n' "$_me_name"
        unset _me_id _me_dir _me_name
        return 0
    done
    unset _me_id _me_dir
    return 1
}

resolve_keystore_backend() {
    _rkb_pref=$(cfg_get keystore_backend auto 2>/dev/null)

    case "$_rkb_pref" in
        trickystore) KEYSTORE_BACKEND="trickystore" ;;
        omk)         KEYSTORE_BACKEND="omk" ;;
        teesim)      KEYSTORE_BACKEND="teesim" ;;
        *)
            if _module_enabled "teesim" >/dev/null; then
                KEYSTORE_BACKEND="teesim"
            elif _module_enabled "tricky_store" >/dev/null; then
                KEYSTORE_BACKEND="trickystore"
            elif _module_enabled "oh_my_keymint" >/dev/null; then
                KEYSTORE_BACKEND="omk"
            else
                KEYSTORE_BACKEND="none"
                log "KEYSTORE" "Error: Tricky Store, OhMyKeymint or TEESimulator is not installed"
            fi
            ;;
    esac

    case "$KEYSTORE_BACKEND" in
        trickystore)
            KEYSTORE_NAME=$(_module_enabled "tricky_store")
            [ -n "$KEYSTORE_NAME" ] || KEYSTORE_NAME="Tricky Store"
            KEYSTORE_DIR="$TRICKY_DIR"
            KEYSTORE_KEYBOX="$TARGET_FILE"
            KEYSTORE_BACKUP="$BACKUP_FILE"
            KEYSTORE_TARGETS="$TARGET_TXT"
            KEYSTORE_SECURITY="$SECURITY_PATCH_FILE"
            KEYSTORE_FORMAT="flat"
            # Newer Tricky Store keeps targets and patch levels in config.ini
            if [ -f "$TRICKY_CONFIG" ] && ini_has_sections "$TRICKY_CONFIG"; then
                KEYSTORE_TARGETS="$TRICKY_CONFIG"
                KEYSTORE_SECURITY="$TRICKY_CONFIG"
                KEYSTORE_FORMAT="ini"
            fi
            ;;
        omk)
            KEYSTORE_NAME=$(_module_enabled "oh_my_keymint")
            [ -n "$KEYSTORE_NAME" ] || KEYSTORE_NAME="OhMyKeymint"
            KEYSTORE_DIR="$OMK_DIR"
            KEYSTORE_KEYBOX="$OMK_KEYBOX"
            KEYSTORE_BACKUP="$OMK_BACKUP"
            KEYSTORE_TARGETS="$OMK_INJECTOR"
            KEYSTORE_SECURITY="$OMK_CONFIG"
            KEYSTORE_FORMAT="toml"
            ;;
        teesim)
            KEYSTORE_NAME=$(_module_enabled "teesim")
            [ -n "$KEYSTORE_NAME" ] || KEYSTORE_NAME="TEESimulator"
            KEYSTORE_DIR="$TEESIM_DIR"
            KEYSTORE_KEYBOX="$TEESIM_KEYBOX"
            KEYSTORE_BACKUP="$TEESIM_BACKUP"
            KEYSTORE_TARGETS="$TEESIM_CONFIG"
            KEYSTORE_SECURITY="$TEESIM_CONFIG"
            KEYSTORE_FORMAT="json"
            ;;
        *)
            KEYSTORE_NAME="None"
            KEYSTORE_DIR=""
            KEYSTORE_KEYBOX=""
            KEYSTORE_BACKUP=""
            KEYSTORE_TARGETS=""
            KEYSTORE_SECURITY=""
            KEYSTORE_FORMAT=""
            ;;
    esac

    export KEYSTORE_BACKEND KEYSTORE_NAME KEYSTORE_DIR KEYSTORE_KEYBOX \
           KEYSTORE_TARGETS KEYSTORE_SECURITY KEYSTORE_FORMAT
    unset _rkb_pref
}

# Log a warning when more than one keystore backend module is enabled. Jerry only
# writes to the active one, but two running side by side can conflict in keystore2.
keystore_warn_multiple() {
    _kwm_list="" _kwm_n=0
    for _kwm_id in teesim tricky_store oh_my_keymint; do
        _module_enabled "$_kwm_id" >/dev/null || continue
        _kwm_list="${_kwm_list:+$_kwm_list, }$_kwm_id"
        _kwm_n=$((_kwm_n + 1))
    done
    [ "$_kwm_n" -gt 1 ] && log "KEYSTORE" "Warning: $_kwm_n keystore backends are enabled ($_kwm_list) — Jerry uses $KEYSTORE_NAME; disable the others to avoid conflicts"
    unset _kwm_list _kwm_n _kwm_id
    return 0
}

keystore_ready() {
    [ "$KEYSTORE_BACKEND" != "none" ] && [ -n "$KEYSTORE_DIR" ] && [ -d "$KEYSTORE_DIR" ]
}

# OhMyKeymint needs an explicit restart touch-file; Tricky Store just watches files
keystore_reload_keymint() {
    [ "$KEYSTORE_BACKEND" = "omk" ] || return 0
    ensure_dir "$OMK_RESTART_DIR"
    touch "$OMK_RESTART_DIR/restart.keymint" 2>/dev/null
}

keystore_reload_injector() {
    [ "$KEYSTORE_BACKEND" = "omk" ] || return 0
    ensure_dir "$OMK_RESTART_DIR"
    touch "$OMK_RESTART_DIR/restart.injector" 2>/dev/null
}

# --- Security patch date, written in whatever format the backend expects ---
_keystore_write_security_patch_nolock() {
    _kwsp_os="$1" _kwsp_boot="${2:-$1}" _kwsp_vendor="${3:-$1}"
    [ -n "$_kwsp_os" ] || { unset _kwsp_os _kwsp_boot _kwsp_vendor; return 1; }

    case "$KEYSTORE_FORMAT" in
        flat)
            ensure_dir "$(dirname "$KEYSTORE_SECURITY")"
            # Per-app [package] sections (keystore_set_per_app_patch) live in the same file; keep them
            _kwsp_sections=""
            [ -f "$KEYSTORE_SECURITY" ] && _kwsp_sections=$(awk '/^[[:space:]]*\[/ { emit = 1 } emit { print }' "$KEYSTORE_SECURITY" 2>/dev/null)
            {
                printf 'system=%s\nboot=%s\nvendor=%s\n' "$_kwsp_os" "$_kwsp_boot" "$_kwsp_vendor"
                # if, not &&: an empty section list must not turn the whole write into a failure
                if [ -n "$_kwsp_sections" ]; then printf '\n%s\n' "$_kwsp_sections"; fi
            } > "$KEYSTORE_SECURITY"
            _kwsp_status=$?
            unset _kwsp_sections
            ;;
        toml)
            ensure_dir "$(dirname "$KEYSTORE_SECURITY")"
            if [ -f "$KEYSTORE_SECURITY" ] && grep -qE '^[[:space:]]*security_patch[[:space:]]*=' "$KEYSTORE_SECURITY" 2>/dev/null; then
                _ks_sed_i "s/^\([[:space:]]*\)security_patch[[:space:]]*=.*/\1security_patch = \"$_kwsp_os\"/" "$KEYSTORE_SECURITY"
            elif [ -f "$KEYSTORE_SECURITY" ]; then
                omk_toml_set "$KEYSTORE_SECURITY" trust security_patch "\"$_kwsp_os\""
            else
                printf '[trust]\nsecurity_patch = "%s"\n' "$_kwsp_os" > "$KEYSTORE_SECURITY"
            fi
            _kwsp_status=$?
            keystore_reload_keymint
            ;;
        ini)
            _ini_set_patch "$KEYSTORE_SECURITY" "$_kwsp_os" "$_kwsp_boot" "$_kwsp_vendor"
            _kwsp_status=$?
            ;;
        json)
            _teesim_safe_edit "$KEYSTORE_SECURITY" _teesim_set_patch "$_kwsp_os" "$_kwsp_boot" "$_kwsp_vendor"
            _kwsp_status=$?
            ;;
        *)
            unset _kwsp_os _kwsp_boot _kwsp_vendor
            return 1
            ;;
    esac

    unset _kwsp_os _kwsp_boot _kwsp_vendor
    return "$_kwsp_status"
}

# --- Target/injector list: add a package to the always-spoof list ---
_keystore_add_target_nolock() {
    _kat_pkg="$1" _kat_suffix="${2:-}"
    [ -n "$_kat_pkg" ] || { unset _kat_pkg _kat_suffix; return 1; }

    case "$KEYSTORE_FORMAT" in
        flat)
            ensure_dir "$KEYSTORE_DIR"
            touch "$KEYSTORE_TARGETS"
            if ! grep -Fqx -e "${_kat_pkg}" -e "${_kat_pkg}!" -e "${_kat_pkg}?" "$KEYSTORE_TARGETS" 2>/dev/null; then
                if grep -qE '^[[:space:]]*\[' "$KEYSTORE_TARGETS" 2>/dev/null; then
                    # the list lives above the first [package] section; appending would put it inside that section
                    _kat_tmp="${KEYSTORE_TARGETS}.add.$$"
                    awk -v e="${_kat_pkg}${_kat_suffix}" '!d && /^[ \t]*\[/ { print e; d = 1 } { print }' "$KEYSTORE_TARGETS" > "$_kat_tmp" 2>/dev/null
                    _ks_commit "$KEYSTORE_TARGETS" "$_kat_tmp" || { rm -f "$_kat_tmp"; unset _kat_pkg _kat_suffix _kat_tmp; return 1; }
                    rm -f "$_kat_tmp"; unset _kat_tmp
                else
                    if [ -s "$KEYSTORE_TARGETS" ] && [ -n "$(tail -c1 "$KEYSTORE_TARGETS" 2>/dev/null)" ]; then
                        echo >> "$KEYSTORE_TARGETS"
                    fi
                    echo "${_kat_pkg}${_kat_suffix}" >> "$KEYSTORE_TARGETS"
                fi
            fi
            ;;
        toml)
            # OMK creates injector.toml itself on first start; never create or guess its layout here
            if [ ! -f "$KEYSTORE_TARGETS" ]; then
                log "KEYSTORE" "OMK injector.toml not found — skipped $_kat_pkg"
                unset _kat_pkg _kat_suffix
                return 1
            fi
            if ! grep -q "\"$_kat_pkg\"" "$KEYSTORE_TARGETS" 2>/dev/null; then
                if grep -qE '^[[:space:]]*\[scoop[].]' "$KEYSTORE_TARGETS" 2>/dev/null; then
                    # legacy [scoop] table is not supported by current OMK; adding a second scoop key would break the file
                    log "KEYSTORE" "injector.toml uses an unsupported [scoop] table — skipped $_kat_pkg"
                    unset _kat_pkg _kat_suffix
                    return 1
                fi
                omk_scoop_init "$KEYSTORE_TARGETS" && omk_scoop_add "$KEYSTORE_TARGETS" "$_kat_pkg" || {
                    log "KEYSTORE" "Could not add $_kat_pkg to injector.toml"
                    unset _kat_pkg _kat_suffix
                    return 1
                }
                keystore_reload_injector
            fi
            ;;
        ini)
            _ini_add_target "$KEYSTORE_TARGETS" "$_kat_pkg" "$_kat_suffix" || { unset _kat_pkg _kat_suffix; return 1; }
            ;;
        json)
            _teesim_safe_edit "$KEYSTORE_TARGETS" _teesim_add_app "$_kat_pkg" || { unset _kat_pkg _kat_suffix; return 1; }
            ;;
        *)
            unset _kat_pkg _kat_suffix
            return 1
            ;;
    esac

    unset _kat_pkg _kat_suffix
    return 0
}

# --- Target/injector list: remove a package (counterpart of keystore_add_target) ---
# Optional 2nd arg SCOPE ("all"): TEESimulator only, remove from every profile, not just "default".
_keystore_remove_target_nolock() {
    _krt_pkg="$1" _krt_scope="${2:-default}"
    [ -n "$_krt_pkg" ] || { unset _krt_pkg; return 1; }
    [ -f "$KEYSTORE_TARGETS" ] || { unset _krt_pkg; return 0; }

    case "$KEYSTORE_FORMAT" in
        flat)
            grep -Fqx -e "$_krt_pkg" -e "${_krt_pkg}!" -e "${_krt_pkg}?" "$KEYSTORE_TARGETS" 2>/dev/null || { unset _krt_pkg; return 0; }
            _krt_tmp="${KEYSTORE_TARGETS}.tmp.$$"
            grep -Fvx -e "$_krt_pkg" -e "${_krt_pkg}!" -e "${_krt_pkg}?" "$KEYSTORE_TARGETS" > "$_krt_tmp" 2>/dev/null
            # grep exits 1 when every line was removed; an empty result is still valid
            cat "$_krt_tmp" > "$KEYSTORE_TARGETS" 2>/dev/null
            rm -f "$_krt_tmp"
            unset _krt_tmp
            ;;
        toml)
            if grep -q "\"$_krt_pkg\"" "$KEYSTORE_TARGETS" 2>/dev/null; then
                omk_scoop_remove "$KEYSTORE_TARGETS" "$_krt_pkg" && keystore_reload_injector
            fi
            ;;
        ini)
            _ini_remove_target "$KEYSTORE_TARGETS" "$_krt_pkg"
            ;;
        json)
            _teesim_safe_edit "$KEYSTORE_TARGETS" _teesim_remove_app "$_krt_pkg" "$_krt_scope"
            ;;
        *)
            unset _krt_pkg _krt_scope
            return 1
            ;;
    esac

    unset _krt_pkg _krt_scope
    return 0
}

# --- Keybox install: copy a decoded keybox.xml to wherever the backend wants it ---
# Keybox sanity check, same for every backend. Hard failures: empty file, no <Keybox>, no private key,
# no certificate chain, BOM / zero-width characters (watermarks), neither an EC nor an RSA key.
# A missing EC or RSA key alone is only a warning (RKP keyboxes are EC only).
keystore_validate_keybox() {
    _kvk_f="$1"
    [ -s "$_kvk_f" ] || { log "KEYBOX" "Invalid keybox: file is empty"; return 1; }
    grep -qi '<Keybox' "$_kvk_f" 2>/dev/null || { log "KEYBOX" "Invalid keybox: no <Keybox> element"; return 1; }
    grep -q 'BEGIN .*PRIVATE KEY' "$_kvk_f" 2>/dev/null || { log "KEYBOX" "Invalid keybox: private key missing"; return 1; }
    grep -q 'BEGIN CERTIFICATE' "$_kvk_f" 2>/dev/null || { log "KEYBOX" "Invalid keybox: certificate chain missing"; return 1; }
    _kvk_bom=$(printf '\357\273\277'); _kvk_zws=$(printf '\342\200\213'); _kvk_zwj=$(printf '\342\200\215')
    if grep -qF -e "$_kvk_bom" -e "$_kvk_zws" -e "$_kvk_zwj" "$_kvk_f" 2>/dev/null; then
        log "KEYBOX" "Invalid keybox: invisible characters found (BOM / zero-width)"
        unset _kvk_f _kvk_bom _kvk_zws _kvk_zwj
        return 1
    fi
    unset _kvk_bom _kvk_zws _kvk_zwj
    # RKP keyboxes ship EC only, so one missing key is just a warning on every backend
    _kvk_n=0
    for _kvk_alg in ecdsa rsa; do
        if grep -qi "algorithm=[\"']$_kvk_alg[\"']" "$_kvk_f" 2>/dev/null; then
            _kvk_n=$((_kvk_n + 1))
        else
            log "KEYBOX" "Warning: keybox has no $_kvk_alg key"
        fi
    done
    if [ "$_kvk_n" -eq 0 ]; then
        log "KEYBOX" "Invalid keybox: no ecdsa or rsa key"
        unset _kvk_f _kvk_alg _kvk_n
        return 1
    fi
    unset _kvk_n
    unset _kvk_f _kvk_alg
    return 0
}

# Install a decoded keybox.xml for the active backend (all backends share this path)
keystore_install_keybox() {
    _kik_src="$1"
    [ -f "$_kik_src" ] || { unset _kik_src; return 1; }
    [ -n "$KEYSTORE_KEYBOX" ] || { unset _kik_src; return 1; }
    keystore_validate_keybox "$_kik_src" || { unset _kik_src; return 1; }

    ensure_dir "$(dirname "$KEYSTORE_KEYBOX")"
    # Overwriting an existing file keeps its inode, owner, mode and SELinux label (same as a manual copy)
    _kik_new=0
    [ -f "$KEYSTORE_KEYBOX" ] || _kik_new=1
    cp "$_kik_src" "$KEYSTORE_KEYBOX" 2>/dev/null
    _kik_status=$?

    if [ "$_kik_status" -eq 0 ]; then
        case "$KEYSTORE_BACKEND" in
            omk)
                if [ "$_kik_new" -eq 1 ]; then
                    chmod 0600 "$KEYSTORE_KEYBOX" 2>/dev/null
                    chown keystore:keystore "$KEYSTORE_KEYBOX" 2>/dev/null
                    restorecon "$KEYSTORE_KEYBOX" 2>/dev/null
                fi
                keystore_reload_keymint
                ;;
            teesim)
                _teesim_safe_edit "$KEYSTORE_SECURITY" _teesim_set_keybox_field
                ;;
        esac
    fi

    unset _kik_src _kik_new
    return "$_kik_status"
}

# --- Read back which keybox file is actually active, for status/UI display ---
keystore_keybox_status() {
    if [ -n "$KEYSTORE_KEYBOX" ] && [ -f "$KEYSTORE_KEYBOX" ]; then
        echo "present"
    else
        echo "missing"
    fi
}

# Per-app patch overrides (Tricky Store only — OMK has no per-package field)
keystore_per_app_patch_supported() {
    [ "$KEYSTORE_BACKEND" = "trickystore" ] && [ "$KEYSTORE_FORMAT" = "flat" ]
}

keystore_read_per_app_patches() {
    keystore_per_app_patch_supported || return 1
    [ -f "$KEYSTORE_SECURITY" ] || return 0
    awk '
        /^\[.*\]$/ {
            if (pkg != "") print pkg "|" vals
            pkg = substr($0, 2, length($0)-2)
            vals = ""
            next
        }
        pkg != "" && /^[a-zA-Z_]+[ \t]*=/ {
            line = $0
            gsub(/^[ \t]+|[ \t]+$/, "", line)
            vals = (vals == "") ? line : vals ";" line
        }
        END { if (pkg != "") print pkg "|" vals }
    ' "$KEYSTORE_SECURITY" 2>/dev/null
}

keystore_set_per_app_patch() {
    _ksap_pkg="$1" _ksap_date="$2"
    keystore_per_app_patch_supported || { unset _ksap_pkg _ksap_date; return 1; }
    [ -n "$_ksap_pkg" ] && [ -n "$_ksap_date" ] || { unset _ksap_pkg _ksap_date; return 1; }

    ensure_dir "$(dirname "$KEYSTORE_SECURITY")"
    [ -f "$KEYSTORE_SECURITY" ] || : > "$KEYSTORE_SECURITY"
    _ksap_tmp="${KEYSTORE_SECURITY}.tmp.$$"

    awk -v pkg="$_ksap_pkg" -v date="$_ksap_date" '
        BEGIN { in_target=0; done=0; found=0 }
        /^\[.*\]$/ {
            cur = substr($0, 2, length($0)-2)
            if (in_target && !done) { print "boot=" date; done = 1 }
            if (cur == pkg) { in_target = 1; found = 1 } else { in_target = 0 }
            print
            next
        }
        in_target && /^boot[ \t]*=/ { print "boot=" date; done = 1; next }
        { print }
        END {
            if (in_target && !done) { print "boot=" date; done = 1 }
            if (!found) { print ""; print "[" pkg "]"; print "boot=" date }
        }
    ' "$KEYSTORE_SECURITY" > "$_ksap_tmp" 2>/dev/null && _ks_commit "$KEYSTORE_SECURITY" "$_ksap_tmp"
    _ksap_status=$?
    rm -f "$_ksap_tmp" 2>/dev/null

    unset _ksap_pkg _ksap_date _ksap_tmp
    return "$_ksap_status"
}

keystore_remove_per_app_patch() {
    _krap_pkg="$1"
    keystore_per_app_patch_supported || { unset _krap_pkg; return 1; }
    [ -n "$_krap_pkg" ] && [ -f "$KEYSTORE_SECURITY" ] || { unset _krap_pkg; return 1; }

    _krap_tmp="${KEYSTORE_SECURITY}.tmp.$$"
    awk -v pkg="$_krap_pkg" '
        /^\[.*\]$/ {
            cur = substr($0, 2, length($0)-2)
            skip = (cur == pkg)
            if (!skip) print
            next
        }
        !skip { print }
    ' "$KEYSTORE_SECURITY" > "$_krap_tmp" 2>/dev/null && _ks_commit "$KEYSTORE_SECURITY" "$_krap_tmp"
    _krap_status=$?
    rm -f "$_krap_tmp" 2>/dev/null

    unset _krap_pkg _krap_tmp
    return "$_krap_status"
}

# --- OMK trust fields ([trust] in config.toml): os_version, security_patch, vb_key, vb_hash ---
# Only the toml (OhMyKeymint) backend has these; other backends return 1.
keystore_get_trust_field() {
    _kgt_key="$1"
    if [ "$KEYSTORE_FORMAT" != "toml" ] || [ ! -f "$KEYSTORE_SECURITY" ]; then
        unset _kgt_key
        return 1
    fi
    awk -v key="$_kgt_key" '
    { t = $0; gsub(/^[ \t]+|[ \t\r]+$/, "", t) }
    t ~ /^\[.*\]$/ { insec = (t == "[trust]"); next }
    insec && t ~ ("^" key "[ \t]*=") { sub(/^[^=]*=[ \t]*/, "", t); gsub(/^"|"$/, "", t); print t; exit }
    ' "$KEYSTORE_SECURITY"
    unset _kgt_key
    return 0
}

# keystore_set_trust_field KEY VALUE — values are validated so nothing can break the TOML
# Accepted forms follow OMK's own config page: os_version auto|0-99, security_patch auto|latest|date,
# vb_key / vb_hash auto|random|64 hex (from OMK docs/CONFIGURATION.md).
keystore_set_trust_field() {
    _kst_key="$1" _kst_val="$2"
    [ "$KEYSTORE_FORMAT" = "toml" ] || { unset _kst_key _kst_val; return 1; }

    case "$_kst_key" in
        os_version)
            case "$_kst_val" in
                auto) _kst_out='"auto"' ;;
                ''|*[!0-9]*) unset _kst_key _kst_val; return 1 ;;
                *)
                    [ "${#_kst_val}" -le 2 ] || { unset _kst_key _kst_val; return 1; }
                    _kst_out="$_kst_val"
                    ;;
            esac
            ;;
        security_patch)
            case "$_kst_val" in
                auto|latest) ;;
                [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
                *) unset _kst_key _kst_val; return 1 ;;
            esac
            _kst_out="\"$_kst_val\""
            ;;
        vb_key|vb_hash)
            case "$_kst_val" in
                auto|random) ;;
                *)
                    [ "${#_kst_val}" -eq 64 ] || { unset _kst_key _kst_val; return 1; }
                    case "$_kst_val" in *[!0-9a-fA-F]*) unset _kst_key _kst_val; return 1 ;; esac
                    ;;
            esac
            _kst_out="\"$_kst_val\""
            ;;
        *)
            unset _kst_key _kst_val
            return 1
            ;;
    esac

    # OMK creates config.toml on its first start; wait briefly for it
    _kst_i=0
    while [ ! -f "$KEYSTORE_SECURITY" ] && [ "$_kst_i" -lt 10 ]; do
        sleep 1
        _kst_i=$((_kst_i + 1))
    done
    if [ ! -f "$KEYSTORE_SECURITY" ]; then
        log "KEYSTORE" "OMK config.toml not available yet, skipping trust field $_kst_key"
        unset _kst_key _kst_val _kst_out _kst_i
        return 1
    fi

    omk_toml_set "$KEYSTORE_SECURITY" trust "$_kst_key" "$_kst_out"
    _kst_rc=$?
    [ "$_kst_rc" -eq 0 ] && keystore_reload_keymint
    unset _kst_key _kst_val _kst_out _kst_i
    return "$_kst_rc"
}

# --- Locking: one writer at a time for target / patch files (mkdir is atomic) ---
KS_LOCK_DIR="/data/adb/JerryManager/.lock/keystore.d"

keystore_lock() {
    [ "${_KS_LOCK_HELD:-0}" = "1" ] && return 0
    mkdir -p "$(dirname "$KS_LOCK_DIR")" 2>/dev/null
    _kl_n=0
    while ! mkdir "$KS_LOCK_DIR" 2>/dev/null; do
        _kl_pid=$(cat "$KS_LOCK_DIR/pid" 2>/dev/null)
        if [ -n "$_kl_pid" ] && [ ! -d "/proc/$_kl_pid" ]; then
            rm -rf "$KS_LOCK_DIR" 2>/dev/null   # owner died
            continue
        fi
        _kl_n=$((_kl_n + 1))
        if [ "$_kl_n" -ge 30 ]; then
            log "KEYSTORE" "Lock held too long — taking it over"
            rm -rf "$KS_LOCK_DIR" 2>/dev/null
            _kl_n=0
            continue
        fi
        sleep 1
    done
    echo "$$" > "$KS_LOCK_DIR/pid" 2>/dev/null
    _KS_LOCK_HELD=1
    unset _kl_n _kl_pid
    return 0
}

keystore_unlock() {
    [ "${_KS_LOCK_HELD:-0}" = "1" ] || return 0
    rm -rf "$KS_LOCK_DIR" 2>/dev/null
    _KS_LOCK_HELD=0
    return 0
}

keystore_write_security_patch() {
    keystore_lock || return 1
    _keystore_write_security_patch_nolock "$@"; _kw_rc=$?
    keystore_unlock
    return "$_kw_rc"
}

keystore_add_target() {
    keystore_lock || return 1
    _keystore_add_target_nolock "$@"; _ka_rc=$?
    keystore_unlock
    return "$_ka_rc"
}

keystore_remove_target() {
    keystore_lock || return 1
    _keystore_remove_target_nolock "$@"; _kr_rc=$?
    keystore_unlock
    return "$_kr_rc"
}

# keystore_remove_targets_file LISTFILE — remove every package in LISTFILE (one per line) from the
# target list, from ALL TEESimulator profiles. TEESimulator is edited in one validated pass
# (one edit per package took ~0.2-0.7 s each); other backends remove package by package.
keystore_remove_targets_file() {
    _krf_list="$1"
    [ -f "$_krf_list" ] || { unset _krf_list; return 1; }
    keystore_lock || { unset _krf_list; return 1; }
    _krf_rc=0
    case "$KEYSTORE_FORMAT" in
        json)
            [ -f "$KEYSTORE_TARGETS" ] && { _teesim_safe_edit "$KEYSTORE_TARGETS" _teesim_remove_apps "$_krf_list" all || _krf_rc=1; }
            ;;
        *)
            while IFS= read -r _krf_pkg || [ -n "$_krf_pkg" ]; do
                [ -n "$_krf_pkg" ] || continue
                _keystore_remove_target_nolock "$_krf_pkg" || _krf_rc=1
            done < "$_krf_list"
            ;;
    esac
    keystore_unlock
    unset _krf_list _krf_pkg
    return "$_krf_rc"
}

# --- Read the active target list: one entry per line, !/? suffix kept where the backend has it ---
# Like keystore_read_targets, but TEESimulator lists the apps of every profile
keystore_read_targets_all() {
    [ -n "$KEYSTORE_TARGETS" ] && [ -f "$KEYSTORE_TARGETS" ] || return 0
    if [ "$KEYSTORE_FORMAT" = "json" ]; then
        _teesim_list_apps "$KEYSTORE_TARGETS" all
    else
        keystore_read_targets
    fi
    return 0
}

keystore_read_targets() {
    [ -n "$KEYSTORE_TARGETS" ] && [ -f "$KEYSTORE_TARGETS" ] || return 0
    case "$KEYSTORE_FORMAT" in
        flat)
            # top-level list only; [package] sections below it are keybox/patch scopes
            awk '
            /^[ \t]*\[/ { exit }
            { sub(/\r$/, ""); gsub(/^[ \t]+|[ \t]+$/, ""); if ($0 != "" && $0 !~ /^#/) print }' "$KEYSTORE_TARGETS" ;;
        ini)  _ini_read_targets "$KEYSTORE_TARGETS" ;;
        toml) omk_scoop_list "$KEYSTORE_TARGETS" ;;
        json) _teesim_list_apps "$KEYSTORE_TARGETS" ;;
    esac
    return 0
}

# --- Replace the whole target list with LISTFILE (one package per line, optional !/? suffix) ---
_keystore_set_targets_nolock() {
    _kst_src="$1"
    [ -f "$_kst_src" ] || { echo "list file missing: $_kst_src" >&2; return 1; }
    [ -n "$KEYSTORE_TARGETS" ] || { echo "no target file resolved for backend '$KEYSTORE_BACKEND'" >&2; return 1; }
    _kst_list="${_kst_src}.clean.$$"
    # clean: strip CR/space, keep valid package names only, last entry per package wins
    tr -d '\r' < "$_kst_src" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | awk '
        /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)*[!?]?$/ {
            b = $0; sub(/[!?]$/, "", b)
            if (!(b in w)) o[++n] = b
            w[b] = $0
        }
        END { for (i = 1; i <= n; i++) print w[o[i]] }' > "$_kst_list"

    case "$KEYSTORE_FORMAT" in
        flat)
            ensure_dir "$KEYSTORE_DIR"
            [ -f "$KEYSTORE_TARGETS" ] || : > "$KEYSTORE_TARGETS"
            cp -p "$KEYSTORE_TARGETS" "$KEYSTORE_TARGETS.bak" 2>/dev/null
            _kst_sections=$(awk '/^[ \t]*\[/ { e = 1 } e { print }' "$KEYSTORE_TARGETS" 2>/dev/null)
            {
                cat "$_kst_list"
                # if, not &&: an empty section list must not turn a good write into a failure
                if [ -n "$_kst_sections" ]; then printf '\n%s\n' "$_kst_sections"; fi
            } > "$KEYSTORE_TARGETS"
            _kst_rc=$?
            [ "$_kst_rc" -eq 0 ] || echo "cannot write $KEYSTORE_TARGETS" >&2
            ;;
        ini)
            _ini_set_targets "$KEYSTORE_TARGETS" "$_kst_list"
            _kst_rc=$?
            ;;
        toml)
            _kst_rc=0
            if [ ! -f "$KEYSTORE_TARGETS" ]; then
                log "KEYSTORE" "OMK injector.toml not found — target list not changed"
                _kst_rc=1
            elif grep -qE '^[[:space:]]*\[scoop[].]' "$KEYSTORE_TARGETS" 2>/dev/null; then
                log "KEYSTORE" "injector.toml uses an unsupported [scoop] table — target list not changed"
                _kst_rc=1
            else
                omk_scoop_init "$KEYSTORE_TARGETS" || _kst_rc=1
                _kst_want="${_kst_list}.want"; _kst_cur="${_kst_list}.cur"
                sed 's/[!?]$//' "$_kst_list" > "$_kst_want"
                omk_scoop_list "$KEYSTORE_TARGETS" > "$_kst_cur"
                _kst_changed=0
                while IFS= read -r _kst_p; do
                    [ -z "$_kst_p" ] && continue
                    grep -Fxq "$_kst_p" "$_kst_want" 2>/dev/null && continue
                    omk_scoop_remove "$KEYSTORE_TARGETS" "$_kst_p" && _kst_changed=1 || _kst_rc=1
                done < "$_kst_cur"
                while IFS= read -r _kst_p; do
                    [ -z "$_kst_p" ] && continue
                    grep -Fxq "$_kst_p" "$_kst_cur" 2>/dev/null && continue
                    omk_scoop_add "$KEYSTORE_TARGETS" "$_kst_p" && _kst_changed=1 || _kst_rc=1
                done < "$_kst_want"
                [ "$_kst_changed" = "1" ] && keystore_reload_injector
                rm -f "$_kst_want" "$_kst_cur"
            fi
            ;;
        json)
            _kst_rc=0
            _kst_want="${_kst_list}.want"; _kst_cur="${_kst_list}.cur"
            sed 's/[!?]$//' "$_kst_list" > "$_kst_want"
            _teesim_list_apps "$KEYSTORE_TARGETS" > "$_kst_cur"
            while IFS= read -r _kst_p; do
                [ -z "$_kst_p" ] && continue
                grep -Fxq "$_kst_p" "$_kst_want" 2>/dev/null && continue
                _teesim_safe_edit "$KEYSTORE_TARGETS" _teesim_remove_app "$_kst_p" || _kst_rc=1
            done < "$_kst_cur"
            while IFS= read -r _kst_p; do
                [ -z "$_kst_p" ] && continue
                grep -Fxq "$_kst_p" "$_kst_cur" 2>/dev/null && continue
                _teesim_safe_edit "$KEYSTORE_TARGETS" _teesim_add_app "$_kst_p" || _kst_rc=1
            done < "$_kst_want"
            rm -f "$_kst_want" "$_kst_cur"
            ;;
        *) _kst_rc=1 ;;
    esac
    rm -f "$_kst_list"
    return "$_kst_rc"
}

keystore_set_targets() {
    keystore_lock || return 1
    _keystore_set_targets_nolock "$@"; _kss_rc=$?
    keystore_unlock
    return "$_kss_rc"
}

# --- Two keystore backends enabled at once conflict in keystore2: keep the active one, disable the rest ---
# The disable flag takes effect after the next reboot.
keystore_enforce_singleton() {
    case "$KEYSTORE_BACKEND" in
        trickystore) _kes_keep="tricky_store" ;;
        omk)         _kes_keep="oh_my_keymint" ;;
        teesim)      _kes_keep="teesim" ;;
        *) return 0 ;;
    esac
    for _kes_id in teesim tricky_store oh_my_keymint; do
        [ "$_kes_id" = "$_kes_keep" ] && continue
        _module_enabled "$_kes_id" >/dev/null || continue
        for _kes_dir in "/data/adb/modules/$_kes_id" "/data/adb/modules_update/$_kes_id"; do
            [ -d "$_kes_dir" ] && touch "$_kes_dir/disable" 2>/dev/null
        done
        log "KEYSTORE" "Disabled conflicting module $_kes_id (using $KEYSTORE_NAME) — takes effect after reboot"
    done
    unset _kes_keep _kes_id _kes_dir
    return 0
}
