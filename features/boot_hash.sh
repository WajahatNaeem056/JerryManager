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

# 1) reuse last good hash so boot doesn't redo work every time
if [ "$_bh_force" -eq 0 ] && [ -f "$BOOT_HASH_FILE" ]; then
    _bh_cached=$(tr -d ' \r\n' < "$BOOT_HASH_FILE" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if _is_valid_hash "$_bh_cached"; then
        boot_hash="$_bh_cached"
        hash_source="cache"
    fi
    unset _bh_cached
fi

# 2) bootloader-provided digest, when the device actually populates it
if [ -z "$boot_hash" ]; then
    _bh_prop=$(getprop ro.boot.vbmeta.digest 2>/dev/null | tr -d ' \r\n' | tr '[:upper:]' '[:lower:]')
    if _is_valid_hash "$_bh_prop"; then
        boot_hash="$_bh_prop"
        hash_source="ro.boot.vbmeta.digest"
    fi
    unset _bh_prop
fi

# 3) last resort: generate our own instead of ever falling back to zeros
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
fi
chmod 644 "$BOOT_HASH_FILE" || log "BOOT_HASH" "Warning: Failed to set permissions on $BOOT_HASH_FILE"

sp_try ro.boot.vbmeta.digest "$boot_hash"

# Keep TrickyStore's attested boot_hash.bin in sync — it goes stale on
# its own whenever this digest changes, breaking attestation.
_bh_ts_file="/data/adb/tricky_store/boot_hash.bin"
if [ -d "/data/adb/tricky_store" ]; then
    _bh_ts_current=""
    [ -f "$_bh_ts_file" ] && _bh_ts_current=$(od -An -tx1 "$_bh_ts_file" 2>/dev/null | tr -d ' \n')
    if [ "$_bh_ts_current" != "$boot_hash" ]; then
        _bh_ts_bytes=$(printf '%s' "$boot_hash" | sed 's/../\\x&/g')
        printf '%b' "$_bh_ts_bytes" > "$_bh_ts_file" 2>/dev/null \
            && log "BOOT_HASH" "Synced TrickyStore boot_hash.bin to $boot_hash" \
            || log "BOOT_HASH" "Warning: Failed to sync TrickyStore boot_hash.bin"
    fi
    unset _bh_ts_current _bh_ts_bytes
fi
unset _bh_ts_file

log "BOOT_HASH" "ro.boot.vbmeta.digest -> $boot_hash (source: $hash_source)"
log "BOOT_HASH" "Finish"
unset boot_hash hash_source _bh_force
exit 0
