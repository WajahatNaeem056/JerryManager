# shellcheck shell=sh
# ===== Logging =====
JERRYMANAGER_LOG_FILE="/data/adb/JerryManager/boot.log"
log() {
    _log_line="$(date +%Y-%m-%d\ %H:%M:%S) [$1] $2"
    echo "$_log_line"
    mkdir -p "$(dirname "$JERRYMANAGER_LOG_FILE")" 2>/dev/null
    if [ -f "$JERRYMANAGER_LOG_FILE" ]; then
        _log_size=$(wc -c < "$JERRYMANAGER_LOG_FILE" 2>/dev/null || echo 0)
        if [ "$_log_size" -gt 1048576 ] 2>/dev/null; then
            mv -f "$JERRYMANAGER_LOG_FILE" "${JERRYMANAGER_LOG_FILE}.old" 2>/dev/null
        fi
    fi
    echo "$_log_line" >> "$JERRYMANAGER_LOG_FILE" 2>/dev/null
    unset _log_line _log_size
}

die() { log "ERROR" "$1"; exit 1; }

log_customrom() {
    _lcr_line="$(date +%Y-%m-%d\ %H:%M:%S) [$1] $2"
    echo "$_lcr_line"
    _lcr_file="$CUSTOM_ROM_LOG_DIR/$1.log"
    mkdir -p "$CUSTOM_ROM_LOG_DIR" 2>/dev/null
    if [ -f "$_lcr_file" ]; then
        _lcr_size=$(wc -c < "$_lcr_file" 2>/dev/null || echo 0)
        if [ "$_lcr_size" -gt 1048576 ] 2>/dev/null; then
            mv -f "$_lcr_file" "${_lcr_file}.old" 2>/dev/null
        fi
    fi
    echo "$_lcr_line" >> "$_lcr_file" 2>/dev/null
    unset _lcr_line _lcr_size _lcr_file
}

# ===== Network =====
download() {
    _dl_url="$1" _dl_output="$2" _dl_oldpath="$PATH"
    PATH="/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:/data/data/com.termux/files/usr/bin:$PATH"
    _dl_tmp="" _dl_code=1 _dl_try=0

    if [ -z "$_dl_output" ]; then
        _dl_tmp=$(mktemp 2>/dev/null || echo "/data/local/tmp/.jerry_dl_${$}_$(date +%s)")
        _dl_output="$_dl_tmp"
    fi

    for _dl_try in 1 2 3; do
        if busybox wget -T 10 --no-check-certificate -qO "$_dl_output" "$_dl_url" 2>/dev/null && [ -s "$_dl_output" ]; then
            _dl_code=0 && break
        fi
        if command -v curl >/dev/null 2>&1 && curl --version >/dev/null 2>&1; then
            curl --connect-timeout 10 -Ls -o "$_dl_output" "$_dl_url" 2>/dev/null && [ -s "$_dl_output" ] && _dl_code=0 && break
        fi
        sleep 1
    done

    if [ -n "$_dl_tmp" ]; then
        [ "$_dl_code" -eq 0 ] && cat "$_dl_tmp"
        rm -f "$_dl_tmp"
    fi

    PATH="$_dl_oldpath"
    unset _dl_url _dl_output _dl_oldpath _dl_tmp _dl_code _dl_try
    return $_dl_code
}

check_network() {
    _cn_oldpath="$PATH"
    PATH="/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:/data/data/com.termux/files/usr/bin:$PATH"
    _cn_dns=""

    for _cn_dns in "1.1.1.1" "8.8.8.8"; do
        ping -c1 -W2 "$_cn_dns" >/dev/null 2>&1 && PATH="$_cn_oldpath" && unset _cn_oldpath _cn_dns && return 0
    done

    # Some networks block ping (ICMP) while the internet works: try a tiny HTTP request
    if busybox wget -T 5 --no-check-certificate -qO /dev/null "https://cloudflare.com/cdn-cgi/trace" 2>/dev/null; then
        PATH="$_cn_oldpath"; unset _cn_oldpath _cn_dns; return 0
    fi
    if command -v curl >/dev/null 2>&1 && curl --version >/dev/null 2>&1 \
       && curl --connect-timeout 5 -sI "https://clients3.google.com/generate_204" >/dev/null 2>&1; then
        PATH="$_cn_oldpath"; unset _cn_oldpath _cn_dns; return 0
    fi

    PATH="$_cn_oldpath"
    unset _cn_oldpath _cn_dns
    return 1
}

# ===== Checks =====
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

check_prop() {
    _cp_name=$1 _cp_expected=$2
    _cp_value=$(resetprop "$_cp_name" 2>/dev/null || echo "")
    [ -z "$_cp_value" ] || [ "$_cp_value" = "$_cp_expected" ] || resetprop -n "$_cp_name" "$_cp_expected" 2>/dev/null || true
    unset _cp_name _cp_expected _cp_value
}

# ===== Prop helpers =====
sp_try() {
    _st_name="$1"
    if [ $# -eq 2 ]; then
        _st_expected="$2"
        _st_current=$(resetprop "$_st_name" 2>/dev/null || echo "")
        # Only change a prop the device already has. A missing prop is left alone
        # (never invent e.g. Realme props on a OnePlus); an equal one needs no change.
        if [ -z "$_st_current" ] || [ "$_st_current" = "$_st_expected" ]; then
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

# $1 = prop, $2 = value. Sets the prop even when the device does not have it yet.
# Only for props that must exist (ro.boot.flash.locked); everything else uses sp_try.
sp_force() {
    _sf_name="$1" _sf_expected="$2"
    _sf_current=$(resetprop "$_sf_name" 2>/dev/null || echo "")
    [ "$_sf_current" = "$_sf_expected" ] || resetprop -n "$_sf_name" "$_sf_expected" 2>/dev/null || true
    unset _sf_name _sf_expected _sf_current
    return 0
}

JERRYMANAGER_DIR="/data/adb/JerryManager"
PERSIST_RESTORE_FILE="$JERRYMANAGER_DIR/persist_backup.txt"

# Save a persist.* prop's original value (first write wins) before we touch it
_persist_remember() {
    case "$1" in persist.*) ;; *) return 0 ;; esac
    _pr_orig=$(resetprop "$1" 2>/dev/null || echo "")
    if [ -n "$_pr_orig" ]; then
        ensure_dir "$JERRYMANAGER_DIR"
        grep -qsF "restore|$1|" "$PERSIST_RESTORE_FILE" 2>/dev/null || \
            echo "restore|$1|$_pr_orig" >> "$PERSIST_RESTORE_FILE" 2>/dev/null || true
    fi
    unset _pr_orig
}

sp_persist() {
    _sp_name="$1" _sp_value="$2"
    _persist_remember "$_sp_name"
    resetprop -n -p "$_sp_name" "$_sp_value" 2>/dev/null || true
    unset _sp_name _sp_value
}

# Delete a prop from persistent storage, remembering its original value first.
sp_persist_delete() {
    _persist_remember "$1"
    resetprop -p --delete "$1" 2>/dev/null || true
}

# ===== Small helpers =====
ensure_dir() { mkdir -p "$1" 2>/dev/null; }

_escape_json() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Writes webroot/json/state.json (all config/*.val) so the WebUI reads settings without a shell call.
write_state_snapshot() {
    _ss_dir="$MODDIR/webroot/json"
    [ -d "$_ss_dir" ] || mkdir -p "$_ss_dir" 2>/dev/null
    _ss_cfg=""
    _ss_sep=""
    for _ss_f in "$JERRYMANAGER_CONFIG_DIR"/*.val; do
        [ -f "$_ss_f" ] || continue
        _ss_k="${_ss_f##*/}"
        _ss_k="${_ss_k%.val}"
        _ss_v=""
        IFS= read -r _ss_v < "$_ss_f" || true
        _ss_v=${_ss_v//\\/\\\\}
        _ss_v=${_ss_v//\"/\\\"}
        _ss_cfg="${_ss_cfg}${_ss_sep}\"${_ss_k}\":\"${_ss_v}\""
        _ss_sep=","
    done
    if printf '{"config_ts":%s,"config":{%s}}\n' "$(date +%s)" "$_ss_cfg" > "$_ss_dir/.state.json.tmp" 2>/dev/null; then
        mv -f "$_ss_dir/.state.json.tmp" "$_ss_dir/state.json" 2>/dev/null
    fi
    unset _ss_dir _ss_cfg _ss_sep _ss_f _ss_k _ss_v
}

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

# ===== Keybox decode =====
decode_keybox_blob() {
    _dkb_in="$1" _dkb_out="$2"
    base64 -d "$_dkb_in" > "$_dkb_out" 2>/dev/null
    _dkb_rc=$?
    unset _dkb_in _dkb_out
    return $_dkb_rc
}

_parse_serial() {
    _ps_file="$1"
    _ps_hex=$(od -v -tx1 "$_ps_file" 2>/dev/null | awk 'BEGIN{ORS=""} {for(i=2;i<=NF;i++) printf "%s",$i}')
    _ps_serial=$(echo "$_ps_hex" | grep -o "020a[0-9a-f]\{20\}" | head -1 | sed 's/^020a//')
    [ -z "$_ps_serial" ] && _ps_serial=$(echo "$_ps_hex" | grep -o "0210[0-9a-f]\{32\}" | head -1 | sed 's/^0210//')
    [ -z "$_ps_serial" ] && _ps_serial=$(echo "$_ps_hex" | grep -o "0208[0-9a-f]\{16\}" | head -1 | sed 's/^0208//')
    [ -z "$_ps_serial" ] && _ps_serial=$(echo "$_ps_hex" | grep -o "0214[0-9a-f]\{40\}" | head -1 | sed 's/^0214//')
    [ -z "$_ps_serial" ] && _ps_serial=$(echo "$_ps_hex" | grep -o "0212[0-9a-f]\{36\}" | head -1 | sed 's/^0212//')
    printf '%s' "$_ps_serial"
    unset _ps_file _ps_hex _ps_serial
}

decode_keybox_serial() {
    _dks_file="$1"
    [ -f "$_dks_file" ] || return 1
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

# notAfter (YYYYMMDDHHMMSS, UTC) of ONE base64 DER certificate passed as $1. Empty + return 1 when unreadable.
# Reads the two validity times (UTCTime 17 0d or GeneralizedTime 18 0f) out of the DER bytes.
_decode_cert_notafter() {
    _dcn_tmp=$(mktemp 2>/dev/null || echo "/data/local/tmp/.jerry_exp_$$")
    printf '%s' "$1" | base64 -d > "$_dcn_tmp" 2>/dev/null
    _dcn_bytes=$(od -v -An -tx1 "$_dcn_tmp" 2>/dev/null | tr -s '\n ' '  ')
    rm -f "$_dcn_tmp"
    _dcn_t='(17 0d (3[0-9] ){12}5a|18 0f (3[0-9] ){14}5a)'
    _dcn_pair=$(printf '%s ' "$_dcn_bytes" | grep -oE "$_dcn_t $_dcn_t" | head -1)
    _dcn_end=$(printf '%s' "$_dcn_pair" | grep -oE "$_dcn_t" | tail -1)
    _dcn_out=$(printf '%s' "$_dcn_end" | awk '{
        n = ($1 == "17") ? 12 : 14
        s = ""
        for (i = 3; i < 3 + n; i++) s = s substr($i, 2, 1)
        if (n == 12) s = (substr(s, 1, 2) + 0 < 50 ? "20" : "19") s
        printf "%s", s
    }')
    printf '%s' "$_dcn_out"
    _dcn_rc=1; [ ${#_dcn_out} -eq 14 ] && _dcn_rc=0
    unset _dcn_tmp _dcn_bytes _dcn_t _dcn_pair _dcn_end _dcn_out
    return $_dcn_rc
}

# Earliest notAfter over every certificate of the first <CertificateChain> (leaf AND intermediates/root):
# a chain is only as valid as its shortest-lived cert. Prints YYYYMMDDHHMMSS.
decode_keybox_expiry() {
    _dke_file="$1"
    [ -f "$_dke_file" ] || return 1
    _dke_min=""
    _dke_certs=$(sed -n '/<CertificateChain>/,/<\/CertificateChain>/{p;/<\/CertificateChain>/q}' "$_dke_file" 2>/dev/null | \
        awk '/<Certificate format="pem">/{c=1; b=""; next} /<\/Certificate>/{if(c) print b; c=0; next} c && !/-----/{gsub(/[ \r\t]/,""); b=b $0}')
    for _dke_b64 in $_dke_certs; do
        [ -n "$_dke_b64" ] || continue
        _dke_one=$(_decode_cert_notafter "$_dke_b64") || continue
        # awk compares 14-digit values as doubles (exact); shell test would overflow on 32-bit mksh
        if [ -z "$_dke_min" ] || awk -v a="$_dke_one" -v b="$_dke_min" 'BEGIN{exit !(a+0 < b+0)}'; then _dke_min="$_dke_one"; fi
    done
    printf '%s' "$_dke_min"
    _dke_rc=1; [ ${#_dke_min} -eq 14 ] && _dke_rc=0
    unset _dke_file _dke_min _dke_certs _dke_b64 _dke_one
    return $_dke_rc
}

# 0 when any certificate in the chain has reached its notAfter; 1 when valid or unreadable
keybox_is_expired() {
    _kie_exp=$(decode_keybox_expiry "$1") || { unset _kie_exp; return 1; }
    _kie_now=$(date -u +%Y%m%d%H%M%S)
    awk -v e="$_kie_exp" -v n="$_kie_now" 'BEGIN{exit !(e+0 <= n+0)}'
    _kie_rc=$?
    unset _kie_exp _kie_now
    return $_kie_rc
}

# Google's revocation list is kept in cache/ for GOOGLE_REVOCATION_TTL seconds (default 1h) so repeated
# checks do not download it again. Prints the list file; fails when there is no valid list (no network,
# empty or broken reply). Only a reply that contains "entries" is ever kept.
_google_revocation_file() {
    _grf_cache="$JERRYMANAGER_DIR/cache/google_revocation.json"
    _grf_tmp="$_grf_cache.tmp.$$"
    if [ -s "$_grf_cache" ]; then
        _grf_age=$(( $(date +%s) - $(stat -c %Y "$_grf_cache" 2>/dev/null || echo 0) ))
        if [ "$_grf_age" -ge 0 ] && [ "$_grf_age" -lt "${GOOGLE_REVOCATION_TTL:-3600}" ] \
           && grep -q '"entries"' "$_grf_cache" 2>/dev/null; then
            echo "$_grf_cache"
            unset _grf_cache _grf_tmp _grf_age
            return 0
        fi
    fi
    ensure_dir "$JERRYMANAGER_DIR/cache"
    if download "$GOOGLE_REVOCATION_URL" "$_grf_tmp" >/dev/null 2>&1 \
       && grep -q '"entries"' "$_grf_tmp" 2>/dev/null \
       && mv -f "$_grf_tmp" "$_grf_cache" 2>/dev/null; then
        echo "$_grf_cache"
        unset _grf_cache _grf_tmp _grf_age
        return 0
    fi
    rm -f "$_grf_tmp" 2>/dev/null
    unset _grf_cache _grf_tmp _grf_age
    return 1
}

# $1 = certificate serial. Looks it up in Google's list (as given, without leading zeros, then as decimal).
# Prints "STATUS|REASON" when listed. Return: 0 = listed (revoked), 1 = not listed, 2 = list unavailable.
google_revocation_info() {
    [ -n "$1" ] || return 2
    _gri_file=$(_google_revocation_file) || { unset _gri_file; return 2; }
    _gri_clean="${1#"${1%%[!0]*}"}"
    [ -z "$_gri_clean" ] && _gri_clean=0
    _gri_dec=""
    if [ "${#1}" -le 16 ]; then
        _gri_dec=$(printf '%d' "0x$_gri_clean" 2>/dev/null) || _gri_dec=""
    fi
    for _gri_key in "$1" "$_gri_clean" "$_gri_dec"; do
        [ -n "$_gri_key" ] || continue
        if tr -d '\n\r' < "$_gri_file" 2>/dev/null | grep -qiE "\"$_gri_key\"[[:space:]]*:"; then
            _gri_obj=$(tr -d '\n\r' < "$_gri_file" 2>/dev/null \
                | grep -oiE "\"$_gri_key\"[[:space:]]*:[[:space:]]*\{[^}]*\}" | head -n1)
            _gri_status=$(printf '%s' "$_gri_obj" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            _gri_reason=$(printf '%s' "$_gri_obj" | sed -n 's/.*"reason"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            printf '%s|%s\n' "${_gri_status:-REVOKED}" "$_gri_reason"
            unset _gri_file _gri_clean _gri_dec _gri_key _gri_obj _gri_status _gri_reason
            return 0
        fi
    done
    unset _gri_file _gri_clean _gri_dec _gri_key
    return 1
}

# Same result codes as google_revocation_info: 0 = revoked, 1 = not revoked, 2 = unknown (list unavailable).
check_google_revocation() {
    google_revocation_info "$1" >/dev/null
}

# ===== Boot props =====
# $1 = ADB Disabler sub-toggle. True only when the master switch AND that
# sub-toggle are on. Master off = nothing about ADB / developer options is touched.
# Master on = every sub-toggle counts as on unless it was switched off (default 1).
adb_hide_enabled() {
    [ "$(cfg_get toggle_adb_disabler 0)" != "0" ] && [ "$(cfg_get "$1" 1)" != "0" ]
}

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
ro.boot.veritymode|enforcing
ro.boot.veritymode.managed|yes
ro.boot.vbmeta.hash_alg|sha256
ro.warranty_bit|0
ro.boot.warranty_bit|0
ro.vendor.warranty_bit|0
ro.vendor.boot.warranty_bit|0
ro.is_ever_orange|0
ro.secureboot.lockstate|locked
ro.boot.realme.lockstate|1
ro.boot.realmebootstate|green
partition.system.verified|2
partition.vendor.verified|2
partition.product.verified|2
partition.system_ext.verified|2
partition.odm.verified|2
PROPS

    sp_force ro.boot.flash.locked 1

    if adb_hide_enabled toggle_adb_disabler_usb_debug; then
        sp_try sys.usb.config mtp
        sp_try sys.usb.adb.disabled 1
        sp_try persist.sys.usb.config none
        sp_try service.adb.root 0
    fi

    for _abp_rp in ro.bootmode ro.boot.bootmode vendor.boot.bootmode ro.boot.mode vendor.boot.mode; do
        sp_try "$_abp_rp" recovery unknown
    done
    unset _abp_rp _abp_prop _abp_val _abp_match

    resetprop --delete "ro.boot.verifiedbooterror" 2>/dev/null || true
    resetprop --delete "ro.boot.verifyerrorpart" 2>/dev/null || true
    resetprop --delete "crashrecovery.rescue_boot_count" 2>/dev/null || true
}

# ===== Prop hiding =====
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

hide_recovery_folders() {
    _hrf_backup="/data/adb/recovery_backups"
    _hrf_random="" _hrf_subdirs=0 _hrf_path=""
    _hrf_found=0 _hrf_failed=0

    for _hrf_base in /sdcard /storage/emulated/0 /mnt/vendor/persist /persist /cache /data/adb /data/recovery; do
        [ -d "$_hrf_base" ] || continue

        for _hrf_folder in TWRP twrp Twrp OrangeFox orangefox Fox FOX fox PBRP pbrp PitchBlack pitchblack Recovery recovery SHRP shrp Redwolf redwolf AERA aera Aera; do
            _hrf_path="$_hrf_base/$_hrf_folder"
            [ ! -d "$_hrf_path" ] && continue
            _hrf_found=$((_hrf_found + 1))

            if [ -f "$_hrf_path/.twrps" ] || [ -f "$_hrf_path/.twrp_settings" ]; then
                rm -f "$_hrf_path/.twrps" "$_hrf_path/.twrp_settings" 2>/dev/null
            fi

            _hrf_subdirs=$(find "$_hrf_path" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
            if [ "$_hrf_subdirs" -gt 0 ]; then
                mkdir -p "$_hrf_backup" 2>/dev/null
                _hrf_random=$(head /dev/urandom 2>/dev/null | tr -dc A-Za-z0-9 | head -c 12)
                [ -z "$_hrf_random" ] && _hrf_random="recovery_${$}"
                mv "$_hrf_path" "$_hrf_backup/$_hrf_random" 2>/dev/null
            else
                rm -rf "$_hrf_path" 2>/dev/null
            fi

            if [ -d "$_hrf_path" ]; then
                _hrf_failed=$((_hrf_failed + 1))
            fi
        done
    done

    for _hrf_loose in \
        "/sdcard/orangefox_settings.txt" \
        "/sdcard/.twrps" \
        "/sdcard/recovery.log" \
        "/mnt/vendor/persist/.twrps" \
        "/mnt/vendor/persist/.twrp_settings"; do
        [ -e "$_hrf_loose" ] && { rm -f "$_hrf_loose" 2>/dev/null || _hrf_failed=$((_hrf_failed + 1)); }
    done
    unset _hrf_loose

    for _hrf_prop in \
        ro.twrp.boot ro.twrp.version \
        ro.orangefox.version ro.fox.version \
        ro.boot.recovery ro.recovery.rescue_party_trigger \
        ro.boot.boot_devices.recovery; do
        resetprop --delete "$_hrf_prop"    2>/dev/null || true
        resetprop -p --delete "$_hrf_prop" 2>/dev/null || true
    done
    unset _hrf_prop

    unset _hrf_backup _hrf_random _hrf_subdirs _hrf_path _hrf_folder _hrf_base
    _hrf_rc=0
    [ "$_hrf_failed" -gt 0 ] && _hrf_rc=1
    unset _hrf_found _hrf_failed
    return "$_hrf_rc"
}

apply_critical_hiding_props() {
    resetprop --delete sys.oem_unlock_allowed 2>/dev/null || true
    sp_try ro.oem_unlock_supported 0
    sp_try ro.boot.warranty_bit 0
    sp_try ro.warranty_bit 0
    sp_try ro.vendor.warranty_bit 0
    sp_try ro.vendor.boot.warranty_bit 0
}

# ===== Boot hardening =====
apply_boot_hardening() {
    if adb_hide_enabled toggle_adb_disabler_dev_options; then
        settings put global development_settings_enabled 0
        resetprop -n persist.sys.development_settings_enabled 0
        resetprop -n persist.sys.developer_options 0
    fi
    if adb_hide_enabled toggle_adb_disabler_usb_debug; then
        settings put global adb_enabled 0
        settings put global adb_wifi_enabled 0
        settings put global adb_wifi_port -1
        resetprop --delete persist.service.adb.enable 2>/dev/null || true
        resetprop --delete persist.service.debuggable 2>/dev/null || true
    fi
    if adb_hide_enabled toggle_adb_disabler_oem_unlock; then
        settings put global oem_unlock_allowed 0
    fi
    apply_critical_hiding_props
    sp_try ro.is_ever_orange 0
    sp_try ro.secureboot.lockstate locked
    sp_try ro.boot.vbmeta.device_state locked
    sp_try vendor.boot.vbmeta.device_state locked
    sp_force ro.boot.flash.locked 1
    sp_try ro.boot.veritymode enforcing
    sp_try ro.boot.veritymode.managed yes
    sp_try ro.boot.selinux enforcing
    sp_try ro.build.selinux 1
    sp_try ro.build.selinux.enforce 1
    sp_try ro.secure 1
    sp_try ro.hardware.virtual_device 0
    if [ "$(toybox cat /sys/fs/selinux/enforce 2>/dev/null)" = "0" ]; then
        chmod 640 /sys/fs/selinux/enforce 2>/dev/null || true
        chmod 440 /sys/fs/selinux/policy 2>/dev/null || true
    fi
}

# ===== ROM spoof =====
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
persist.sys.pixelprops.vending|false
persist.sys.pihooks.disable|1
persist.sys.kihooks.disable|1
persist.sys.pihooks.enabled_features|0
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

# ===== Conflicts =====
CONFLICT_BACKUP_FILE="$JERRYMANAGER_DIR/conflict_backups.txt"

_conflict_registry() {
    cat <<'EOF'
zygisk_nohello|NoHello|/data/adb/modules/zygisk_nohello/service.sh|boot_hardening|passive
treat_wheel|TreatWheel|/data/adb/modules/treat_wheel/service.sh,/data/adb/modules/treat_wheel/service-or-boot-completed.sh|boot_hardening|passive
sensitive_props|Sensitive Props|/data/adb/modules/sensitive_props/service.sh|boot_hardening,suspicious_props|passive
brene|.BRENE|/data/adb/modules/brene/service.sh,/data/adb/modules/brene/post-fs-data.sh,/data/adb/modules/brene/boot-completed.sh|suspicious_props,boot_hash|passive
specter|Specter|/data/adb/modules/specter/service.sh,/data/adb/modules/specter/post-fs-data.sh|boot_hardening,security_patch,suspicious_props|aggressive
EOF
}

_conflict_detect() {
    _cd_modid="$1"
    [ -d "/data/adb/modules/$_cd_modid" ] || [ -d "/data/adb/modules_update/$_cd_modid" ]
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

# Feature name used in _conflict_registry -> the real toggle key it controls.
# A claimed feature is switched OFF while the other module covers it; the user's own
# value is remembered in <toggle>.pre_conflict and restored when the conflict is gone.
# This never switches a toggle ON by itself.
apply_conflict_toggles() {
    # stray keys written by older builds (these toggles never existed)
    cfg_delete toggle_security_patch
    cfg_delete toggle_lsposed
    cfg_delete toggle_target
    for _ac_pair in \
        boot_hardening:toggle_boot_hardening \
        security_patch:toggle_action_security_patch \
        suspicious_props:toggle_suspicious_props \
        boot_hash:toggle_action_boot_hash; do
        _ac_feature="${_ac_pair%%:*}"
        _ac_key="${_ac_pair#*:}"
        _ac_saved="$JERRYMANAGER_CONFIG_DIR/$_ac_key.pre_conflict"
        _ac_def=1
        command -v toggle_default >/dev/null 2>&1 && _ac_def=$(toggle_default "$_ac_key")
        _ac_cur=$(cfg_get "$_ac_key" "$_ac_def")
        if _conflict_claimed "$_ac_feature"; then
            # remember what the user had (a value they set while claimed counts too)
            if [ ! -f "$_ac_saved" ] || [ "$_ac_cur" != "0" ]; then
                mkdir -p "$JERRYMANAGER_CONFIG_DIR" 2>/dev/null
                printf '%s' "$_ac_cur" > "$_ac_saved" 2>/dev/null
            fi
            [ "$_ac_cur" = "0" ] || cfg_set "$_ac_key" 0
        elif [ -f "$_ac_saved" ]; then
            cfg_set "$_ac_key" "$(cat "$_ac_saved" 2>/dev/null)"
            rm -f "$_ac_saved" 2>/dev/null
        fi
    done
    unset _ac_pair _ac_feature _ac_key _ac_saved _ac_def _ac_cur
}

resolve_conflicts() {
    ensure_dir "$JERRYMANAGER_DIR"
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

# ===== Inotifyd =====
# Pick an inotifyd for install detection: the ROM's own, then the root manager's
# busybox. Sets INOTIFYD_KIND (system, busybox or none) and INOTIFYD_CMD
# (word-split when used, so it may hold two words).
resolve_inotifyd() {
    INOTIFYD_KIND="none"
    INOTIFYD_CMD=""

    if command -v inotifyd >/dev/null 2>&1; then
        INOTIFYD_KIND="system"
        INOTIFYD_CMD="inotifyd"
        return 0
    fi

    for _ri_bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
        [ -x "$_ri_bb" ] || continue
        "$_ri_bb" --list 2>/dev/null | grep -qx inotifyd || continue
        INOTIFYD_KIND="busybox"
        INOTIFYD_CMD="$_ri_bb inotifyd"
        unset _ri_bb
        return 0
    done
    unset _ri_bb

    return 0
}
