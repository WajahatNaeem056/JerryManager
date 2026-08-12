# shellcheck shell=sh

JERRYKEY_LOG_FILE="/data/adb/JerryManager/boot.log"
log() {
    _log_line="$(date +%Y-%m-%d\ %H:%M:%S) [$1] $2"
    echo "$_log_line"
    mkdir -p "$(dirname "$JERRYKEY_LOG_FILE")" 2>/dev/null
    # Rotate if log grows past ~1MB, keep one backup
    if [ -f "$JERRYKEY_LOG_FILE" ]; then
        _log_size=$(wc -c < "$JERRYKEY_LOG_FILE" 2>/dev/null || echo 0)
        [ "$_log_size" -gt 1048576 ] 2>/dev/null && mv -f "$JERRYKEY_LOG_FILE" "${JERRYKEY_LOG_FILE}.old" 2>/dev/null
    fi
    echo "$_log_line" >> "$JERRYKEY_LOG_FILE" 2>/dev/null
    unset _log_line _log_size
}

die() { log "ERROR" "$1"; exit 1; }

# ── Download (3-retry, wget+curl fallback, all root solutions) ────────────────
download() {
    _dl_url="$1" _dl_output="$2" _dl_oldpath="$PATH"
    PATH="/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:/data/data/com.termux/files/usr/bin:$PATH"
    _dl_tmp="" _dl_code=1 _dl_try=0

    if [ -z "$_dl_output" ]; then
        _dl_tmp=$(mktemp 2>/dev/null || echo "/data/local/tmp/.jerry_dl_${$}_$(date +%s)")
        _dl_output="$_dl_tmp"
    fi

    for _dl_try in 1 2 3; do
        if busybox wget -T 10 --no-check-certificate -qO "$_dl_output" "$_dl_url" 2>/dev/null; then
            _dl_code=0 && break
        fi
        if command -v curl >/dev/null 2>&1 && curl --version >/dev/null 2>&1; then
            curl --connect-timeout 10 -Ls -o "$_dl_output" "$_dl_url" 2>/dev/null && _dl_code=0 && break
        fi
        sleep 1
    done

    if [ -n "$_dl_tmp" ] && [ "$_dl_code" -eq 0 ]; then
        cat "$_dl_tmp"
        rm -f "$_dl_tmp"
    fi

    PATH="$_dl_oldpath"
    unset _dl_url _dl_output _dl_oldpath _dl_tmp _dl_code _dl_try
    return $_dl_code
}

# ── Network check (ping-first, faster offline detection) ─────────────────────
# Capped to a strict ~4s worst case (was up to ~36s) so UI-facing checks like
# keybox_info.sh don't leave the WebUI blank for a long time on slow/flaky
# networks. Ping-only, no HTTP fallback — user explicitly accepted the
# trade-off that networks which block ICMP ping (but still have working
# internet) will incorrectly report "no network" here, in exchange for a
# strict ~10s total cap on the keybox status check.
check_network() {
    _cn_oldpath="$PATH"
    PATH="/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:/data/data/com.termux/files/usr/bin:$PATH"
    _cn_dns=""

    for _cn_dns in "1.1.1.1" "8.8.8.8"; do
        ping -c1 -W2 "$_cn_dns" >/dev/null 2>&1 && PATH="$_cn_oldpath" && unset _cn_oldpath _cn_dns && return 0
    done

    PATH="$_cn_oldpath"
    unset _cn_oldpath _cn_dns
    return 1
}

check_module() {
    _cm_name="$1"
    if [ ! -d "/data/adb/modules/$_cm_name" ] && [ ! -d "/data/adb/modules_update/$_cm_name" ]; then
        log "ERROR" "Required module '$1' is not installed"
        return 1
    fi
    return 0
}

check_command() {
    _cc_name="$1"
    if ! command -v "$_cc_name" >/dev/null 2>&1; then
        log "ERROR" "Required command '$1' not found on this device"
        return 1
    fi
    return 0
}

# ── Prop helpers ──────────────────────────────────────────────────────────────

# check_prop: set prop only if current value differs from expected
check_prop() {
    _cp_name=$1 _cp_expected=$2
    _cp_value=$(resetprop "$_cp_name" 2>/dev/null || echo "")
    [ -z "$_cp_value" ] || [ "$_cp_value" = "$_cp_expected" ] || resetprop -n "$_cp_name" "$_cp_expected" 2>/dev/null || true
    unset _cp_name _cp_expected _cp_value
}

# sp_try: 2-arg = check_prop alias; 3-arg = set only if current value *contains* needle
sp_try() {
    _st_name="$1"
    if [ $# -eq 2 ]; then
        _st_expected="$2"
        _st_current=$(resetprop "$_st_name" 2>/dev/null || echo "")
        if [ -n "$_st_current" ] && [ "$_st_current" = "$_st_expected" ]; then
            unset _st_name _st_expected _st_current
            return 0
        fi
    elif [ $# -ge 3 ]; then
        _st_needle="$2" _st_value="$3"
        _st_current=$(resetprop "$_st_name" 2>/dev/null || echo "")
        case "$_st_current" in *"$_st_needle"*) ;; *) return 1 ;; esac
        _st_expected="$_st_value"
    else
        return 1
    fi
    resetprop -n "$_st_name" "$_st_expected" 2>/dev/null || true
    unset _st_name _st_expected _st_current _st_needle _st_value
    return 0
}

# sp_persist: set prop AND persist with -p, track in restore file
JERRYKEY_DIR="/data/adb/JerryManager"
PERSIST_RESTORE_FILE="$JERRYKEY_DIR/persist_backup.txt"

sp_persist() {
    _sp_name="$1" _sp_value="$2"
    resetprop -n -p "$_sp_name" "$_sp_value" 2>/dev/null || true
    _sp_restore=$(resetprop "$_sp_name" 2>/dev/null || echo "")
    if [ -n "$_sp_restore" ]; then
        ensure_dir "$JERRYKEY_DIR"
        if ! grep -qsF "|$_sp_name|" "$PERSIST_RESTORE_FILE" 2>/dev/null; then
            echo "restore|$_sp_name|$_sp_restore" >> "$PERSIST_RESTORE_FILE" 2>/dev/null || true
        fi
    fi
    unset _sp_name _sp_value _sp_restore
}

contains_check_prop() {
    _ccp_name=$1 _ccp_contains=$2 _ccp_newval=$3
    case "$(resetprop "$_ccp_name" 2>/dev/null)" in
        *"$_ccp_contains"*) resetprop -n "$_ccp_name" "$_ccp_newval"; unset _ccp_name _ccp_contains _ccp_newval; return 0 ;;
    esac
    unset _ccp_name _ccp_contains _ccp_newval
    return 1
}

ensure_dir() { mkdir -p "$1" 2>/dev/null; }

# ── JSON helper ───────────────────────────────────────────────────────────────
_escape_json() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# ── Version comparison ────────────────────────────────────────────────────────
version_ge() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        split(a,A,"."); split(b,B,".");
        for(i=1;i<=3;i++) {
            if(A[i]+0 > B[i]+0) { exit 0 }
            if(A[i]+0 < B[i]+0) { exit 1 }
        }
        exit 0
    }'
}

# ── TEESimulator detection ────────────────────────────────────────────────────
_is_teesimulator() {
    [ -f "/data/adb/modules/TEESimulator/module.prop" ] || \
    [ -f "/data/adb/modules_update/TEESimulator/module.prop" ]
}

# ── Keybox helpers ────────────────────────────────────────────────────────────

# decode_keybox_blob: base64 decode input file to output file
decode_keybox_blob() {
    _dkb_in="$1" _dkb_out="$2"
    base64 -d "$_dkb_in" > "$_dkb_out" 2>/dev/null
    _dkb_rc=$?
    unset _dkb_in _dkb_out
    return $_dkb_rc
}

# _parse_serial: extract hex serial from DER-encoded certificate bytes
_parse_serial() {
    _ps_file="$1"
    _ps_hex=$(od -v -tx1 "$_ps_file" 2>/dev/null | awk 'BEGIN{ORS=""} {for(i=2;i<=NF;i++) printf "%s",$i}')
    # Try multiple serial lengths: 020a=10byte, 2010=16byte, 2008=8byte, 2014=20byte, 2012=18byte
    _ps_serial=$(echo "$_ps_hex" | grep -o "020a[0-9a-f]\{20\}" | head -1 | sed 's/^020a//')
    [ -z "$_ps_serial" ] && _ps_serial=$(echo "$_ps_hex" | grep -o "0210[0-9a-f]\{32\}" | head -1 | sed 's/^0210//')
    [ -z "$_ps_serial" ] && _ps_serial=$(echo "$_ps_hex" | grep -o "0208[0-9a-f]\{16\}" | head -1 | sed 's/^0208//')
    [ -z "$_ps_serial" ] && _ps_serial=$(echo "$_ps_hex" | grep -o "0214[0-9a-f]\{40\}" | head -1 | sed 's/^0214//')
    [ -z "$_ps_serial" ] && _ps_serial=$(echo "$_ps_hex" | grep -o "0212[0-9a-f]\{36\}" | head -1 | sed 's/^0212//')
    printf '%s' "$_ps_serial"
    unset _ps_file _ps_hex _ps_serial
}

# decode_keybox_serial: extract serial number from keybox.xml certificate
decode_keybox_serial() {
    _dks_file="$1"
    [ -f "$_dks_file" ] || return 1
    # Extract base64 — explicitly remove BEGIN/END lines and XML tags
    _dks_b64=$(sed -n '/<Certificate format="pem">/,/<\/Certificate>/p' "$_dks_file" 2>/dev/null | \
        grep -v 'Certificate' | \
        grep -v -- '-----BEGIN' | \
        grep -v -- '-----END' | \
        tr -d '\n\r ')
    [ -z "$_dks_b64" ] && return 1
    _dks_tmp=$(mktemp 2>/dev/null || echo "/data/local/tmp/.jerry_cert_$$")
    printf '%s' "$_dks_b64" | base64 -d > "$_dks_tmp" 2>/dev/null
    [ -s "$_dks_tmp" ] || { rm -f "$_dks_tmp"; return 1; }
    _dks_serial=$(_parse_serial "$_dks_tmp")
    rm -f "$_dks_tmp"
    printf '%s' "$_dks_serial"
    unset _dks_file _dks_b64 _dks_tmp _dks_serial
}

# check_google_revocation: returns 0 if revoked, 1 if clean
check_google_revocation() {
    _cgr_serial="$1"
    [ -n "$_cgr_serial" ] || return 1
    _cgr_list=$(download "$GOOGLE_REVOCATION_URL" 2>/dev/null)
    [ -z "$_cgr_list" ] && { log "REVOKE" "Warning: Could not fetch Google revocation list"; return 1; }
    # Check hex serial
    if echo "$_cgr_list" | grep -qi "$_cgr_serial"; then
        unset _cgr_serial _cgr_list; return 0
    fi
    # Check stripped leading zeros
    _cgr_clean="${_cgr_serial#"${_cgr_serial%%[!0]*}"}"
    [ -z "$_cgr_clean" ] && _cgr_clean=0
    if echo "$_cgr_list" | grep -qi "$_cgr_clean"; then
        unset _cgr_serial _cgr_list _cgr_clean; return 0
    fi
    # Check decimal (only if serial short enough)
    if [ "${#_cgr_serial}" -le 16 ]; then
        _cgr_dec=$((16#$_cgr_clean))
        if echo "$_cgr_list" | grep -q "$_cgr_dec"; then
            unset _cgr_serial _cgr_list _cgr_clean _cgr_dec; return 0
        fi
        unset _cgr_dec
    fi
    unset _cgr_serial _cgr_list _cgr_clean
    return 1
}

# ── Boot props — data-driven, single source of truth ─────────────────────────
apply_boot_props() {
    while IFS='|' read -r _abp_prop _abp_val; do
        [ -z "$_abp_prop" ] && continue
        case "$_abp_prop" in
            ro.*.build.type)
                while IFS= read -r _abp_match; do
                    [ -z "$_abp_match" ] && continue
                    sp_try "$_abp_match" "user"
                done <<MATCHES
$(resetprop 2>/dev/null | grep -oE 'ro.*\.build\.type' | grep -v 'ro.build.type' || true)
MATCHES
                ;;
            ro.*.build.tags)
                while IFS= read -r _abp_match; do
                    [ -z "$_abp_match" ] && continue
                    sp_try "$_abp_match" "release-keys"
                done <<MATCHES
$(resetprop 2>/dev/null | grep -oE 'ro.*\.build\.tags' | grep -v 'ro.build.tags' || true)
MATCHES
                ;;
            *)
                sp_try "$_abp_prop" "$_abp_val"
                ;;
        esac
    done << PROPS
ro.boot.selinux|enforcing
ro.build.selinux|1
ro.secure|1
ro.adb.secure|1
ro.debuggable|0
ro.force.debuggable|0
ro.kernel.qemu|0
ro.boot.qemu|0
ro.crypto.state|encrypted
ro.hardware.virtual_device|0
ro.build.type|user
ro.build.tags|release-keys
ro.*.build.type|user
ro.*.build.tags|release-keys
ro.boot.verifiedbootstate|green
vendor.boot.verifiedbootstate|green
ro.boot.vbmeta.device_state|locked
vendor.boot.vbmeta.device_state|locked
ro.boot.flash.locked|1
ro.boot.veritymode|enforcing
ro.boot.veritymode.managed|yes
ro.boot.vbmeta.avb_version|2.0
ro.boot.vbmeta.hash_alg|sha256
ro.warranty_bit|0
ro.boot.warranty_bit|0
ro.vendor.warranty_bit|0
ro.vendor.boot.warranty_bit|0
ro.is_ever_orange|0
ro.secureboot.lockstate|locked
ro.boot.realme.lockstate|1
ro.boot.realmebootstate|green
sys.usb.config|mtp
sys.usb.adb.disabled|1
persist.sys.usb.config|none
service.adb.root|0
partition.system.verified|2
partition.vendor.verified|2
partition.product.verified|2
partition.system_ext.verified|2
partition.odm.verified|2
PROPS

    for _abp_rp in ro.bootmode ro.boot.bootmode vendor.boot.bootmode ro.boot.mode vendor.boot.mode; do
        sp_try "$_abp_rp" recovery unknown
    done
    unset _abp_rp _abp_prop _abp_val _abp_match

    # ── Boot error prop cleanup — clears traces of past verified-boot
    # failures / rescue-boot triggers that would otherwise persist and
    # remain visible to attestation/root-detection checks.
    resetprop --delete "ro.boot.verifiedbooterror" 2>/dev/null || true
    resetprop --delete "ro.boot.verifyerrorpart" 2>/dev/null || true
    resetprop --delete "crashrecovery.rescue_boot_count" 2>/dev/null || true
}

# ── hexpatch_deleteprop ───────────────────────────────────────────────────────
hexpatch_deleteprop() {
    _hd_prop="$1"
    [ -n "$_hd_prop" ] || return 0
    _hd_magiskboot=$(command -v magiskboot 2>/dev/null || find /data/adb /data/data/me.bmax.apatch/patch/ -name magiskboot -print -quit 2>/dev/null)
    if [ -n "$_hd_magiskboot" ]; then
        _hd_file=$(resetprop -Z "$_hd_prop" 2>/dev/null | cut -d' ' -f2 | cut -d':' -f3)
        [ -z "$_hd_file" ] && { resetprop -p --delete "$_hd_prop" 2>/dev/null || true; return 0; }
        _hd_path=$(find /dev/__properties__/ -name "*$_hd_file*" -print -quit 2>/dev/null)
        [ -z "$_hd_path" ] && { resetprop -p --delete "$_hd_prop" 2>/dev/null || true; return 0; }
        _hd_search_hex=$(printf '%s' "$_hd_prop" | od -A n -t x1 | tr -d ' \n' | tr '[:lower:]' '[:upper:]')
        _hd_search_len=$(printf '%s' "$_hd_prop" | wc -c)
        _hd_replacement=$(head /dev/urandom 2>/dev/null | tr -dc '0-9a-f' | head -c "$_hd_search_len" 2>/dev/null || printf '%s' "$_hd_prop" | od -A n -t x1 | tr -d ' \n' | head -c "$((_hd_search_len * 2))")
        _hd_replacement_hex=$(printf '%s' "$_hd_replacement" | od -A n -t x1 | tr -d ' \n' | tr '[:lower:]' '[:upper:]')
        "$_hd_magiskboot" hexpatch "$_hd_path" "$_hd_search_hex" "$_hd_replacement_hex" >/dev/null 2>&1 || resetprop -p --delete "$_hd_prop" 2>/dev/null || true
    else
        resetprop -p --delete "$_hd_prop" 2>/dev/null || true
    fi
    unset _hd_prop _hd_magiskboot _hd_file _hd_path _hd_search_hex _hd_search_len _hd_replacement _hd_replacement_hex
}

# ── Control Tab Functions ─────────────────────────────────────────────────────

hide_recovery_folders() {
    _hrf_backup="/data/adb/recovery_backups"
    _hrf_random="" _hrf_subdirs=0 _hrf_path=""

    for _hrf_folder in TWRP OrangeFox FOX PBRP PitchBlack Recovery; do
        _hrf_path="/sdcard/$_hrf_folder"
        [ ! -d "$_hrf_path" ] && continue

        if [ -f "$_hrf_path/.twrps" ]; then
            rm -f "$_hrf_path/.twrps" 2>/dev/null || {
                _hrf_random=$(head /dev/urandom 2>/dev/null | tr -dc A-Za-z0-9 | head -c 12)
                [ -z "$_hrf_random" ] && _hrf_random="recovery_${$}"
                mv "$_hrf_path" "/sdcard/$_hrf_random" 2>/dev/null
                continue
            }
        fi

        _hrf_subdirs=$(find "$_hrf_path" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        if [ "$_hrf_subdirs" -gt 0 ]; then
            mkdir -p "$_hrf_backup" 2>/dev/null
            mv "$_hrf_path" "$_hrf_backup/" 2>/dev/null
        else
            rm -rf "$_hrf_path" 2>/dev/null
        fi
    done
    unset _hrf_backup _hrf_random _hrf_subdirs _hrf_path _hrf_folder
}

# ── apply_critical_hiding_props ───────────────────────────────────────────────
# These props (oem_unlock_allowed/supported + warranty bits) must ALWAYS be
# hidden regardless of any user toggle — Duck Detector and other root/attestation
# checkers key on them directly. Previously these were only set inside
# apply_boot_hardening(), which is gated behind the (user-toggleable) Boot
# Hardening feature — so devices with that toggle off never got them spoofed
# and failed root-hiding checks. Kept as its own unconditional function so it's
# never accidentally re-coupled to a toggle again, and no longer duplicated in
# apply_boot_props()'s early PROPS list (removed there to avoid the early,
# silently-failing sp_try attempt racing with this authoritative one).
apply_critical_hiding_props() {
    # sys.oem_unlock_allowed: deleted rather than forced to 0. On genuine
    # locked-bootloader devices this prop is typically absent entirely, not
    # explicitly set to 0 — a checker reading it via reflection (e.g. Duck
    # Detector) flags the mere presence of an explicit value as suspicious,
    # even when that value is the "safe" 0. Deleting it matches real device
    # behavior instead of mimicking it with a forced value.
    resetprop --delete sys.oem_unlock_allowed 2>/dev/null || true
    resetprop -n ro.oem_unlock_supported 0 2>/dev/null || true
    resetprop -n ro.boot.warranty_bit 0 2>/dev/null || true
    resetprop -n ro.warranty_bit 0 2>/dev/null || true
    resetprop -n ro.vendor.warranty_bit 0 2>/dev/null || true
    resetprop -n ro.vendor.boot.warranty_bit 0 2>/dev/null || true
}

apply_boot_hardening() {
    settings put global development_settings_enabled 0
    settings put global adb_enabled 0
    settings put global oem_unlock_allowed 0
    settings put global adb_wifi_enabled 0
    settings put global adb_wifi_port -1
    resetprop --delete persist.service.adb.enable 2>/dev/null || true
    resetprop --delete persist.service.debuggable 2>/dev/null || true
    resetprop -n persist.sys.developer_options 0
    apply_critical_hiding_props
    resetprop -n ro.is_ever_orange 0 2>/dev/null || true
    resetprop -n ro.secureboot.lockstate locked 2>/dev/null || true
    resetprop -n ro.boot.vbmeta.device_state locked 2>/dev/null || true
    resetprop -n vendor.boot.vbmeta.device_state locked 2>/dev/null || true
    resetprop -n ro.boot.flash.locked 1 2>/dev/null || true
    resetprop -n ro.boot.veritymode enforcing 2>/dev/null || true
    resetprop -n ro.boot.veritymode.managed yes 2>/dev/null || true
    resetprop -n ro.boot.selinux enforcing 2>/dev/null || true
    resetprop -n ro.build.selinux 1 2>/dev/null || true
    resetprop -n ro.build.selinux.enforce 1 2>/dev/null || true
    resetprop -n ro.secure 1 2>/dev/null || true
    resetprop -n ro.hardware.virtual_device 0 2>/dev/null || true
    if [ "$(toybox cat /sys/fs/selinux/enforce 2>/dev/null)" = "0" ]; then
        chmod 640 /sys/fs/selinux/enforce 2>/dev/null || true
        chmod 440 /sys/fs/selinux/policy 2>/dev/null || true
    fi
}

# ── block_rom_spoof_engines — persist-tracked ─────────────────────────────────
block_rom_spoof_engines() {
    _brs_gate=false
    resetprop 2>/dev/null | grep -qE 'persist\.sys\.(pihooks|entryhooks|pixelprops)' && _brs_gate=true
    [ -f "/data/system/gms_certified_props.json" ] && _brs_gate=true
    [ "$_brs_gate" = "false" ] && unset _brs_gate && return 0

    for _brs_hook in persist.sys.pihooks.first_api_level persist.sys.pihooks.security_patch; do
        resetprop 2>/dev/null | grep -q "$_brs_hook" || sp_persist "$_brs_hook" ""
    done
    unset _brs_hook

    while IFS='|' read -r _brs_prop _brs_val; do
        sp_persist "$_brs_prop" "$_brs_val"
    done << MAP
persist.sys.pihooks.disable.gms_props|true
persist.sys.pihooks.disable.gms_key_attestation_block|true
persist.sys.entryhooks_enabled|false
persist.sys.pixelprops.gms|false
persist.sys.pixelprops.gapps|false
persist.sys.pixelprops.google|false
persist.sys.pixelprops.pi|false
MAP

    if [ -f "/data/system/gms_certified_props.json" ] && [ "$(resetprop persist.sys.spoof.gms 2>/dev/null)" != "false" ]; then
        resetprop persist.sys.spoof.gms false 2>/dev/null || true
    fi

    unset _brs_gate _brs_prop _brs_val
}

disable_bootloader_spoofer() {
    if command -v cmd >/dev/null 2>&1; then
        if pm list packages 2>/dev/null | grep -q "es.chiteroman.bootloaderspoofer"; then
            cmd package uninstall --user 0 "es.chiteroman.bootloaderspoofer" >/dev/null 2>&1 || true
        fi
    else
        for _pkg in es.chiteroman.bootloaderspoofer; do
            if grep -q "$_pkg" /data/system/packages.list 2>/dev/null; then
                timeout 5 pm uninstall --user 0 "$_pkg" >/dev/null 2>&1 || true
            fi
        done
        unset _pkg
        _wpp_xml="/data/data/com.wmods.wppenhacer/shared_prefs/com.wmods.wppenhacer_preferences.xml"
        if [ -f "$_wpp_xml" ] && grep -q 'name="bootloader_spoofer" value="true"' "$_wpp_xml" 2>/dev/null; then
            sed -i 's/\(name="bootloader_spoofer" value=\)"true"/\1"false"/' "$_wpp_xml" 2>/dev/null || true
        fi
        unset _wpp_xml
    fi
}

# ── Conflict Detection System ─────────────────────────────────────────────────
CONFLICT_BACKUP_FILE="$JERRYKEY_DIR/conflict_backups.txt"

_conflict_registry() {
    cat <<'EOF'
zygisk_nohello|NoHello|/data/adb/modules/zygisk_nohello/service.sh|boot_hardening|passive
tsupport-advance|TSupport-Advance|/data/adb/modules/tsupport-advance/post-fs-data.sh,/data/adb/modules/tsupport-advance/service.sh|boot_hardening,security_patch,suspicious_props,lsposed,rom_spoof,bootloader_spoofer,target|aggressive
treat_wheel|TreatWheel|/data/adb/modules/treat_wheel/service.sh,/data/adb/modules/treat_wheel/service-or-boot-completed.sh|boot_hardening|passive
sensitive_props|Sensitive Props|/data/adb/modules/sensitive_props/service.sh|boot_hardening,suspicious_props|passive
Yurikey|Yurikey Manager|/data/adb/modules/Yurikey/service.sh|boot_hardening,security_patch,suspicious_props,rom_spoof|aggressive
integritybox|Integrity Box|/data/adb/modules/playintegrityfix/service.sh,/data/adb/modules/playintegrityfix/post-fs-data.sh|boot_hardening,security_patch,suspicious_props,rom_spoof,bootloader_spoofer,target|aggressive
brene|.BRENE|/data/adb/modules/brene/service.sh,/data/adb/modules/brene/post-fs-data.sh,/data/adb/modules/brene/boot-completed.sh|suspicious_props,boot_hash|passive
tsupport-utl|Tricky Addon - Update Target List|/data/adb/modules/TA_utl/prop.sh|boot_hash|aggressive
tsupport-enhanced|Tricky Addon Enhanced|/data/adb/modules/TA_enhanced/prop.sh,/data/adb/modules/TA_enhanced/bin/arm64-v8a/ta-enhanced,/data/adb/modules/TA_enhanced/bin/armeabi-v7a/ta-enhanced,/data/adb/modules/TA_enhanced/bin/x86_64/ta-enhanced,/data/adb/modules/TA_enhanced/bin/x86/ta-enhanced|boot_hash,keybox,security_patch|aggressive
specter|Specter|/data/adb/modules/specter/service.sh,/data/adb/modules/specter/post-fs-data.sh|boot_hardening,security_patch,suspicious_props|aggressive
zygisk-assistant|Zygisk Assistant|/data/adb/modules/zygisk-assistant/service.sh,/data/adb/modules/zygisk-assistant/post-fs-data.sh|boot_hardening|passive
EOF
}

_conflict_detect() {
    _cd_modid="$1"
    case "$_cd_modid" in
        integritybox)
            [ -d "/data/adb/modules/playintegrityfix" ] && [ -d "/data/adb/Box-Brain" ]
            ;;
        *)
            [ -d "/data/adb/modules/$_cd_modid" ] || [ -d "/data/adb/modules_update/$_cd_modid" ]
            ;;
    esac
}

_conflict_choice() {
    cfg_get "conflict_$1" "priority_jerry"
}

_conflict_rename_bak() {
    _cr_path="$1"
    [ -f "$_cr_path" ] || return 0
    [ -f "$_cr_path.bak" ] && return 0
    mv "$_cr_path" "$_cr_path.bak" 2>/dev/null || true
    echo "$_cr_path" >> "$CONFLICT_BACKUP_FILE" 2>/dev/null || true
}

_conflict_restore_bak() {
    _cr_path="$1"
    [ -f "$_cr_path.bak" ] || return 0
    mv "$_cr_path.bak" "$_cr_path" 2>/dev/null || true
}

_conflict_apply_scripts() {
    _cas_scripts="$1" _cas_choice="$2" _cas_old_ifs="$IFS"
    IFS=','
    for _cas_script in $_cas_scripts; do
        [ -z "$_cas_script" ] && continue
        if [ "$_cas_choice" = "priority_module" ]; then
            _conflict_restore_bak "$_cas_script"
        else
            _conflict_rename_bak "$_cas_script"
        fi
    done
    IFS="$_cas_old_ifs"
    unset _cas_scripts _cas_choice _cas_old_ifs _cas_script
}

_conflict_claimed() {
    _cc_feature="$1" _cc_claimed=1
    while IFS='|' read -r _cc_id _cc_name _cc_scripts _cc_features _cc_type; do
        [ -z "$_cc_id" ] && continue
        _conflict_detect "$_cc_id" || continue
        case ",$_cc_features," in *",$_cc_feature,"*) ;; *) continue ;; esac
        case "$_cc_type" in
            passive) _cc_claimed=0; break ;;
            aggressive)
                [ "$(_conflict_choice "$_cc_id")" = "priority_module" ] || continue
                _cc_claimed=0; break ;;
        esac
    done <<EOF
$(_conflict_registry)
EOF
    unset _cc_id _cc_name _cc_scripts _cc_features _cc_type
    return $_cc_claimed
}

apply_conflict_toggles() {
    for _ac_feature in boot_hardening security_patch suspicious_props lsposed rom_spoof bootloader_spoofer target; do
        if _conflict_claimed "$_ac_feature"; then
            cfg_set "toggle_$_ac_feature" 0
        else
            cfg_set "toggle_$_ac_feature" 1
        fi
    done
    unset _ac_feature
}

resolve_conflicts() {
    ensure_dir "$JERRYKEY_DIR"
    touch "$CONFLICT_BACKUP_FILE" 2>/dev/null || true
    disable_bootloader_spoofer

    while IFS='|' read -r _rc_id _rc_name _rc_scripts _rc_features _rc_type; do
        [ -z "$_rc_id" ] && continue
        _conflict_detect "$_rc_id" || continue
        case "$_rc_type" in
            aggressive)
                _conflict_apply_scripts "$_rc_scripts" "priority_jerry"
                cfg_set "conflict_$_rc_id" "priority_jerry"
                log "CONFLICT" "$_rc_name: full overlap — disabled, JerryManager covers all"
                ;;
            passive)
                log "CONFLICT" "$_rc_name: partial overlap — deferred: $_rc_features"
                ;;
        esac
    done <<EOF
$(_conflict_registry)
EOF
    unset _rc_id _rc_name _rc_scripts _rc_features _rc_type
    apply_conflict_toggles
}

conflict_status_json() {
    _cs_first=1
    printf '['
    while IFS='|' read -r _cs_id _cs_name _cs_scripts _cs_features _cs_type; do
        [ -z "$_cs_id" ] && continue
        _conflict_detect "$_cs_id" || continue
        _cs_choice="$(_conflict_choice "$_cs_id")"
        _cs_priority=true
        [ "$_cs_choice" = "priority_module" ] && _cs_priority=false
        _cs_name_json="$(_escape_json "$_cs_name")"
        if [ "$_cs_first" -eq 0 ]; then printf ','; else _cs_first=0; fi
        printf '{"key":"%s","friendlyName":"%s","detected":true,"priorityJerry":%s,"type":"%s"}' \
            "$_cs_id" "$_cs_name_json" "$_cs_priority" "$_cs_type"
    done <<EOF
$(_conflict_registry)
EOF
    printf ']'
    unset _cs_first _cs_id _cs_name _cs_scripts _cs_features _cs_type _cs_choice _cs_priority _cs_name_json
}
