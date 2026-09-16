# shellcheck shell=sh

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
        *)
            if _module_enabled "teesim" >/dev/null; then
                KEYSTORE_BACKEND="none"
                log "KEYSTORE" "TEESimulator is active — handled separately by Sync TEESimulator Config, not a Jerry-managed backend"
            elif _module_enabled "tricky_store" >/dev/null; then
                KEYSTORE_BACKEND="trickystore"
            elif _module_enabled "oh_my_keymint" >/dev/null; then
                KEYSTORE_BACKEND="omk"
            else
                KEYSTORE_BACKEND="none"
                log "KEYSTORE" "Error: Tricky Store or OhMyKeymint is not installed"
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
            KEYSTORE_LOCKED="$LOCKED_FILE"
            KEYSTORE_FORMAT="flat"
            ;;
        omk)
            KEYSTORE_NAME=$(_module_enabled "oh_my_keymint")
            [ -n "$KEYSTORE_NAME" ] || KEYSTORE_NAME="OhMyKeymint"
            KEYSTORE_DIR="$OMK_DIR"
            KEYSTORE_KEYBOX="$OMK_KEYBOX"
            KEYSTORE_BACKUP="$OMK_BACKUP"
            KEYSTORE_TARGETS="$OMK_INJECTOR"
            KEYSTORE_SECURITY="$OMK_CONFIG"
            KEYSTORE_LOCKED=""
            KEYSTORE_FORMAT="toml"
            ;;
        *)
            _teesim_name=$(_module_enabled "teesim")
            if [ -n "$_teesim_name" ]; then
                KEYSTORE_NAME="$_teesim_name"
            elif _module_enabled "teesim" >/dev/null; then
                KEYSTORE_NAME="TEESimulator"
            else
                KEYSTORE_NAME="None"
            fi
            unset _teesim_name
            KEYSTORE_DIR=""
            KEYSTORE_KEYBOX=""
            KEYSTORE_BACKUP=""
            KEYSTORE_TARGETS=""
            KEYSTORE_SECURITY=""
            KEYSTORE_LOCKED=""
            KEYSTORE_FORMAT=""
            ;;
    esac

    export KEYSTORE_BACKEND KEYSTORE_NAME KEYSTORE_DIR KEYSTORE_KEYBOX \
           KEYSTORE_TARGETS KEYSTORE_SECURITY KEYSTORE_LOCKED KEYSTORE_FORMAT
    unset _rkb_pref
}

keystore_ready() {
    [ "$KEYSTORE_BACKEND" != "none" ] && [ -n "$KEYSTORE_DIR" ] && [ -d "$KEYSTORE_DIR" ]
}

# Ask the active backend to pick up changes. Tricky Store watches its files
# directly (no reload needed); OhMyKeymint needs an explicit restart touch-file.
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
keystore_write_security_patch() {
    _kwsp_os="$1" _kwsp_boot="${2:-$1}" _kwsp_vendor="${3:-$1}"
    [ -n "$_kwsp_os" ] || { unset _kwsp_os _kwsp_boot _kwsp_vendor; return 1; }

    case "$KEYSTORE_FORMAT" in
        flat)
            printf 'system=%s\nboot=%s\nvendor=%s\n' "$_kwsp_os" "$_kwsp_boot" "$_kwsp_vendor" > "$KEYSTORE_SECURITY"
            _kwsp_status=$?
            ;;
        toml)
            ensure_dir "$(dirname "$KEYSTORE_SECURITY")"
            if [ -f "$KEYSTORE_SECURITY" ] && grep -q '^security_patch' "$KEYSTORE_SECURITY" 2>/dev/null; then
                sed -i "s/^security_patch.*/security_patch = \"$_kwsp_os\"/" "$KEYSTORE_SECURITY"
            else
                printf '\n[main]\nsecurity_patch = "%s"\n' "$_kwsp_os" >> "$KEYSTORE_SECURITY"
            fi
            _kwsp_status=$?
            keystore_reload_keymint
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
keystore_add_target() {
    _kat_pkg="$1" _kat_suffix="${2:-}"
    [ -n "$_kat_pkg" ] || { unset _kat_pkg _kat_suffix; return 1; }

    case "$KEYSTORE_FORMAT" in
        flat)
            ensure_dir "$KEYSTORE_DIR"
            touch "$KEYSTORE_TARGETS"
            grep -Fqx "${_kat_pkg}${_kat_suffix}" "$KEYSTORE_TARGETS" 2>/dev/null || \
                echo "${_kat_pkg}${_kat_suffix}" >> "$KEYSTORE_TARGETS"
            ;;
        toml)
            ensure_dir "$(dirname "$KEYSTORE_TARGETS")"
            touch "$KEYSTORE_TARGETS"
            if ! grep -q "\"$_kat_pkg\"" "$KEYSTORE_TARGETS" 2>/dev/null; then
                if ! grep -q '^\[scoop\]' "$KEYSTORE_TARGETS" 2>/dev/null; then
                    printf '\n[filter]\nenabled = true\n\n[scoop]\npackages = ["%s"]\n' "$_kat_pkg" >> "$KEYSTORE_TARGETS"
                else
                    sed -i "s/^packages = \[/packages = [\"$_kat_pkg\", /" "$KEYSTORE_TARGETS"
                fi
                keystore_reload_injector
            fi
            ;;
        *)
            unset _kat_pkg _kat_suffix
            return 1
            ;;
    esac

    unset _kat_pkg _kat_suffix
    return 0
}

# --- Keybox install: copy a decoded keybox.xml to wherever the backend wants it ---
keystore_install_keybox() {
    _kik_src="$1"
    [ -f "$_kik_src" ] || { unset _kik_src; return 1; }
    [ -n "$KEYSTORE_KEYBOX" ] || { unset _kik_src; return 1; }

    ensure_dir "$(dirname "$KEYSTORE_KEYBOX")"
    cp "$_kik_src" "$KEYSTORE_KEYBOX" 2>/dev/null
    _kik_status=$?

    if [ "$_kik_status" -eq 0 ] && [ "$KEYSTORE_BACKEND" = "omk" ]; then
        chmod 0600 "$KEYSTORE_KEYBOX" 2>/dev/null
        keystore_reload_keymint
    fi

    unset _kik_src
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
    [ "$KEYSTORE_BACKEND" = "trickystore" ]
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
    ' "$KEYSTORE_SECURITY" > "$_ksap_tmp" 2>/dev/null && mv -f "$_ksap_tmp" "$KEYSTORE_SECURITY"
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
    ' "$KEYSTORE_SECURITY" > "$_krap_tmp" 2>/dev/null && mv -f "$_krap_tmp" "$KEYSTORE_SECURITY"
    _krap_status=$?
    rm -f "$_krap_tmp" 2>/dev/null

    unset _krap_pkg _krap_tmp
    return "$_krap_status"
}
