# shellcheck shell=sh
resolve_keystore_backend() {
    _rkb_pref=$(cfg_get keystore_backend auto 2>/dev/null)

    case "$_rkb_pref" in
        trickystore) KEYSTORE_BACKEND="trickystore" ;;
        omk)         KEYSTORE_BACKEND="omk" ;;
        *)
            if [ -d "/data/adb/modules/tricky_store" ] || [ -d "/data/adb/modules_update/tricky_store" ]; then
                KEYSTORE_BACKEND="trickystore"
            elif [ -d "/data/adb/modules/oh_my_keymint" ] || [ -d "/data/adb/modules_update/oh_my_keymint" ]; then
                KEYSTORE_BACKEND="omk"
            else
                KEYSTORE_BACKEND="none"
                log "KEYSTORE" "Error: Tricky Store or OhMyKeymint is not installed"
            fi
            ;;
    esac

    case "$KEYSTORE_BACKEND" in
        trickystore)
            KEYSTORE_NAME="Tricky Store"
            KEYSTORE_DIR="$TRICKY_DIR"
            KEYSTORE_KEYBOX="$TARGET_FILE"
            KEYSTORE_TARGETS="$TARGET_TXT"
            KEYSTORE_SECURITY="$SECURITY_PATCH_FILE"
            KEYSTORE_LOCKED="$LOCKED_FILE"
            KEYSTORE_FORMAT="flat"
            ;;
        omk)
            KEYSTORE_NAME="OhMyKeymint"
            KEYSTORE_DIR="$OMK_DIR"
            KEYSTORE_KEYBOX="$OMK_KEYBOX"
            KEYSTORE_TARGETS="$OMK_INJECTOR"
            KEYSTORE_SECURITY="$OMK_CONFIG"
            KEYSTORE_LOCKED=""
            KEYSTORE_FORMAT="toml"
            ;;
        *)
            KEYSTORE_NAME="None"
            KEYSTORE_DIR=""
            KEYSTORE_KEYBOX=""
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
    _kwsp_date="$1"
    [ -n "$_kwsp_date" ] || { unset _kwsp_date; return 1; }

    case "$KEYSTORE_FORMAT" in
        flat)
            printf 'boot=%s\nvendor=%s\n' "$_kwsp_date" "$_kwsp_date" > "$KEYSTORE_SECURITY"
            ;;
        toml)
            ensure_dir "$(dirname "$KEYSTORE_SECURITY")"
            if [ -f "$KEYSTORE_SECURITY" ] && grep -q '^security_patch' "$KEYSTORE_SECURITY" 2>/dev/null; then
                sed -i "s/^security_patch.*/security_patch = \"$_kwsp_date\"/" "$KEYSTORE_SECURITY"
            else
                printf '\n[main]\nsecurity_patch = "%s"\n' "$_kwsp_date" >> "$KEYSTORE_SECURITY"
            fi
            keystore_reload_keymint
            ;;
        *)
            unset _kwsp_date
            return 1
            ;;
    esac

    _kwsp_status=$?
    unset _kwsp_date
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
