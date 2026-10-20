#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"

log "BOOT_HASH" "Start"

_is_valid_hash() {
    _vh_hash=$1
    [ "${#_vh_hash}" -eq 64 ] || { unset _vh_hash; return 1; }
    case "$_vh_hash" in *[!0-9a-fA-F]*) unset _vh_hash; return 1 ;; esac
    case "$_vh_hash" in *[!0]*) ;; *) unset _vh_hash; return 1 ;; esac
    unset _vh_hash
    return 0
}

_bh_force=0
[ "${1:-}" = "--refresh" ] && _bh_force=1

boot_hash=""
hash_source=""

# Trust the cache only if it came from the TEE probe; weak fallbacks must not stick.
BOOT_HASH_SRC_FILE="${BOOT_HASH_FILE}.src"
_bh_booted=0
[ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ] && _bh_booted=1

if [ "$_bh_force" -eq 0 ] && [ -f "$BOOT_HASH_FILE" ]; then
    _bh_cached=$(tr -d ' \r\n' < "$BOOT_HASH_FILE" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    _bh_csrc=$(cat "$BOOT_HASH_SRC_FILE" 2>/dev/null)
    if _is_valid_hash "$_bh_cached"; then
        case "$_bh_csrc" in
            tee)
                boot_hash="$_bh_cached"
                hash_source="cache"
                ;;
        esac
    fi
    unset _bh_cached _bh_csrc
fi

# TEE probe: needs keystore, so only after boot_completed.
if [ -z "$boot_hash" ] && [ "$_bh_booted" -eq 1 ]; then
    _bh_dex="${MODDIR%/features}/dex/attest.dex"
    if [ -f "$_bh_dex" ]; then
        _bh_out=$(CLASSPATH="$_bh_dex" app_process / com.jerry.attest.Main 2>/dev/null | tr -d ' \r\n' | tr '[:upper:]' '[:lower:]')
        if _is_valid_hash "$_bh_out"; then
            boot_hash="$_bh_out"
            hash_source="tee"
        fi
        unset _bh_out
    fi
    unset _bh_dex
fi

# Bootloader digest
if [ -z "$boot_hash" ]; then
    _bh_prop=$(getprop ro.boot.vbmeta.digest 2>/dev/null | tr -d ' \r\n' | tr '[:upper:]' '[:lower:]')
    if _is_valid_hash "$_bh_prop"; then
        boot_hash="$_bh_prop"
        hash_source="ro.boot.vbmeta.digest"
    fi
    unset _bh_prop
fi

# vbmeta partition hash (approximation, not the AVB chain digest)
_bh_partition_digest() {
    _bpd_tool=""
    if command -v sha256sum >/dev/null 2>&1; then
        _bpd_tool=sha256sum
    elif command -v openssl >/dev/null 2>&1; then
        _bpd_tool=openssl
    else
        return 1
    fi

    _bpd_slot=$(getprop ro.boot.slot_suffix 2>/dev/null)
    _bpd_path=""
    for _bpd_cand in \
        "/dev/block/bootdevice/by-name/vbmeta${_bpd_slot}" \
        "/dev/block/by-name/vbmeta${_bpd_slot}" \
        /dev/block/platform/*/by-name/vbmeta"${_bpd_slot}" \
        /dev/block/platform/*/*/by-name/vbmeta"${_bpd_slot}"
    do
        if [ -e "$_bpd_cand" ]; then
            _bpd_path="$_bpd_cand"
            break
        fi
    done
    if [ -z "$_bpd_path" ]; then
        unset _bpd_tool _bpd_slot _bpd_path _bpd_cand
        return 1
    fi

    # First 64KB only: header and signature, skipping zero padding
    if [ "$_bpd_tool" = "sha256sum" ]; then
        _bpd_hash=$(dd if="$_bpd_path" bs=4096 count=16 2>/dev/null | sha256sum 2>/dev/null | cut -d' ' -f1)
    else
        _bpd_hash=$(dd if="$_bpd_path" bs=4096 count=16 2>/dev/null | openssl dgst -sha256 2>/dev/null | sed 's/^.*= *//')
    fi
    _bpd_hash=$(printf '%s' "$_bpd_hash" | tr -d ' \r\n' | tr '[:upper:]' '[:lower:]')
    unset _bpd_tool _bpd_slot _bpd_path _bpd_cand

    if _is_valid_hash "$_bpd_hash"; then
        boot_hash="$_bpd_hash"
        hash_source="vbmeta-partition"
        unset _bpd_hash
        return 0
    fi
    unset _bpd_hash
    return 1
}

if [ -z "$boot_hash" ]; then
    _bh_partition_digest || true
fi

# Last resort: never fall back to zeros
if [ -z "$boot_hash" ]; then
    _bh_rand=$(od -v -An -tx1 -N32 /dev/urandom 2>/dev/null | tr -d ' \r\n' | tr '[:upper:]' '[:lower:]')
    if _is_valid_hash "$_bh_rand"; then
        boot_hash="$_bh_rand"
        hash_source="generated"
    fi
    unset _bh_rand
fi

[ -n "$boot_hash" ] || die "Could not resolve a valid boot hash from any source"

ensure_dir "$(dirname "$BOOT_HASH_FILE")"
if [ "$hash_source" != "cache" ]; then
    echo "$boot_hash" > "$BOOT_HASH_FILE" || die "Failed to write $BOOT_HASH_FILE"
    case "$hash_source" in
        tee) echo tee > "$BOOT_HASH_SRC_FILE" ;;
        *) echo "weak" > "$BOOT_HASH_SRC_FILE" ;;   # re-resolved after boot
    esac
fi
chmod 644 "$BOOT_HASH_FILE" || log "BOOT_HASH" "Warning: Failed to set permissions on $BOOT_HASH_FILE"

# Only TEE-sourced hashes may touch props or Tricky Store; weak ones stay in Jerry's cache.
case "$hash_source" in
    tee|cache)
        # resetprop does not persist; re-applied every boot
        _bh_cur=$(getprop ro.boot.vbmeta.digest 2>/dev/null | tr -d ' \r\n' | tr '[:upper:]' '[:lower:]')
        if [ "$_bh_cur" != "$boot_hash" ]; then
            resetprop -n ro.boot.vbmeta.digest "$boot_hash" 2>/dev/null \
                && log "BOOT_HASH" "Aligned ro.boot.vbmeta.digest with attested hash" \
                || log "BOOT_HASH" "Warning: failed to align ro.boot.vbmeta.digest"
        fi
        unset _bh_cur

        _bh_ts_file="/data/adb/tricky_store/boot_hash.bin"
        if [ -d "/data/adb/tricky_store" ]; then
            _bh_ts_current=""
            [ -f "$_bh_ts_file" ] && _bh_ts_current=$(od -An -tx1 "$_bh_ts_file" 2>/dev/null | tr -d ' \n')
            if [ "$_bh_ts_current" != "$boot_hash" ]; then
                _bh_ts_bytes=$(printf '%s' "$boot_hash" | sed 's/../\\x&/g')
                printf '%b' "$_bh_ts_bytes" > "$_bh_ts_file" 2>/dev/null \
                    && log "BOOT_HASH" "Synced Tricky Store boot_hash.bin with attested hash" \
                    || log "BOOT_HASH" "Warning: failed to sync Tricky Store boot_hash.bin"
            fi
            unset _bh_ts_current _bh_ts_bytes
        fi
        unset _bh_ts_file
        ;;
esac

log "BOOT_HASH" "Stored Jerry boot hash (source: $hash_source)"
log "BOOT_HASH" "Finish"
unset boot_hash hash_source _bh_force
exit 0
