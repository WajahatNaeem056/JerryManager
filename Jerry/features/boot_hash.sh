#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"

# Usage: boot_hash.sh [--refresh | --set <64 hex> | --set (clears custom) | --show | --vbmeta-size]
#   --show prints HASH=<64 hex or empty> and SOURCE=custom|cache|none, nothing is changed
#   --vbmeta-size prints the vbmeta size read from the partitions next to the live prop, nothing is changed

TS_BIN="/data/adb/tricky_store/boot_hash.bin"
TEE_PROBE_TIMEOUT=15
VBMETA_BYNAME_DIR="${VBMETA_BYNAME_DIR:-/dev/block/by-name}"   # overridable for tests

_norm() { tr -d ' \r\n' | tr '[:upper:]' '[:lower:]'; }
_read() { cat "$1" 2>/dev/null | _norm; }

# 64 hex chars, not all zeros
_valid() {
    [ "${#1}" -eq 64 ] || return 1
    case "$1" in
        *[!0-9a-f]*) return 1 ;;
        *[!0]*) return 0 ;;
    esac
    return 1
}

# Read-only: what Jerry currently holds (custom pin wins over the cached hash)
if [ "$1" = "--show" ]; then
    _shown=$(cfg_get custom_boot_hash "" | _norm)
    _shown_src=custom
    if ! _valid "$_shown"; then
        _shown=$(_read "$BOOT_HASH_FILE")
        _shown_src=cache
    fi
    _valid "$_shown" || { _shown=""; _shown_src=none; }
    printf 'HASH=%s\nSOURCE=%s\n' "$_shown" "$_shown_src"
    [ "$_shown_src" = "none" ] && printf 'NOTE=live sources not probed by --show\n'
    exit 0
fi

log "BOOT_HASH" "Start (arg: ${1:-none})"

# Take the first valid candidate only
_pick() {
    [ -z "$boot_hash" ] && _valid "$1" && { boot_hash="$1"; hash_source="$2"; }
    return 0
}

_tee_probe() {
    [ "$(getprop sys.boot_completed)" = "1" ] || return 0
    _dex="${MODDIR%/features}/dex/attest.dex"
    [ -f "$_dex" ] || return 0

    _tp_out="/data/local/tmp/jerry_attest.$$"
    CLASSPATH="$_dex" app_process / com.jerry.attest.Main >"$_tp_out" 2>/dev/null &
    _tp_pid=$!
    _tp_i=0
    while kill -0 "$_tp_pid" 2>/dev/null && [ "$_tp_i" -lt "$TEE_PROBE_TIMEOUT" ]; do
        sleep 1
        _tp_i=$((_tp_i + 1))
    done

    if kill -0 "$_tp_pid" 2>/dev/null; then
        kill -9 "$_tp_pid" 2>/dev/null
        log "BOOT_HASH" "TEE probe timed out, falling back"
        rm -f "$_tp_out" 2>/dev/null
        return 0
    fi

    _tp_val=$(_norm < "$_tp_out")
    rm -f "$_tp_out" 2>/dev/null

    # Main.java prints exactly one 64-hex line on success, nothing on failure.
    _valid "$_tp_val" && printf '%s' "$_tp_val"
    return 0
}

_random_hash() {
    _r=$(od -v -An -tx1 -N32 /dev/urandom 2>/dev/null | _norm)
    [ "${#_r}" -eq 64 ] && { printf '%s' "$_r"; return; }
    # Fallback when od is unavailable: derive 64 hex from two UUIDs
    _r=$(cat /proc/sys/kernel/random/uuid /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '\n-')
    printf '%s' "${_r:0:64}"
}

# Size of one AVB vbmeta image: 256-byte header + authentication block + auxiliary block.
# The two block sizes are big-endian u64 fields at offsets 12 and 20 of the header.
# Prints bytes; fails when the device is unreadable or does not start with the "AVB0" magic.
_avb_image_size() {
    [ -r "$1" ] || return 1
    dd if="$1" bs=32 count=1 2>/dev/null | od -v -An -tx1 | awk '
        function hx(c) { return index("0123456789abcdef", c) - 1 }
        function byte(i) { return hx(substr(b[i], 1, 1)) * 16 + hx(substr(b[i], 2, 1)) }
        { for (i = 1; i <= NF; i++) b[n++] = $i }
        END {
            if (n < 28 || b[0] b[1] b[2] b[3] != "41564230") exit 1
            for (i = 12; i < 20; i++) auth = auth * 256 + byte(i)
            for (i = 20; i < 28; i++) aux = aux * 256 + byte(i)
            total = 256 + auth + aux
            if (total < 256 || total > 1048576) exit 1
            printf "%d", total
        }'
}

# "<partition> <bytes>" per vbmeta image found (top-level plus chained system/vendor), active slot first
_vbmeta_sizes() {
    _vs_suffix=$(getprop ro.boot.slot_suffix 2>/dev/null)
    for _vs_p in vbmeta vbmeta_system vbmeta_vendor; do
        for _vs_dev in "$VBMETA_BYNAME_DIR/${_vs_p}${_vs_suffix}" "$VBMETA_BYNAME_DIR/${_vs_p}"; do
            _vs_n=$(_avb_image_size "$_vs_dev") || continue
            printf '%s %s\n' "$_vs_p" "$_vs_n"
            break
        done
    done
    unset _vs_suffix _vs_p _vs_dev _vs_n
}

# Sum of all vbmeta images, which is what the bootloader reports as ro.boot.vbmeta.size. Fails if none was readable.
_vbmeta_total_size() {
    _vbmeta_sizes | awk '{ t += $2; n++ } END { if (!n) exit 1; printf "%d", t }'
}

# Make the prop and Tricky Store agree with the resolved hash
_publish() {
    if [ "$(cfg_get toggle_boot_props 1)" != "0" ]; then
        # avb_version and hash_alg are the same on practically every device; size is read from the
        # vbmeta partitions and is simply left alone when they cannot be read.
        for _vb in avb_version:1.2 hash_alg:sha256 "size:$(_vbmeta_total_size)"; do
            _vb_p="ro.boot.vbmeta.${_vb%%:*}"
            _vb_v="${_vb#*:}"
            [ -n "$_vb_v" ] || continue
            [ -z "$(getprop "$_vb_p" 2>/dev/null)" ] \
                && resetprop -n "$_vb_p" "$_vb_v" 2>/dev/null \
                && log "BOOT_HASH" "Filled absent $_vb_p=$_vb_v"
        done
        unset _vb _vb_p _vb_v
    fi

    if [ "$(getprop ro.boot.vbmeta.digest 2>/dev/null | _norm)" != "$1" ]; then
        resetprop -n ro.boot.vbmeta.digest "$1" 2>/dev/null \
            && log "BOOT_HASH" "Aligned ro.boot.vbmeta.digest" \
            || log "BOOT_HASH" "Warning: failed to set ro.boot.vbmeta.digest"
    fi

    [ -d "$(dirname "$TS_BIN")" ] || return 0
    _cur=""
    # -v is required: without it od compresses repeated bytes to '*'
    [ -f "$TS_BIN" ] && _cur=$(od -v -An -tx1 "$TS_BIN" 2>/dev/null | tr -d ' \n')
    [ "$_cur" = "$1" ] && return 0
    printf '%b' "$(printf '%s' "$1" | sed 's/../\\x&/g')" > "$TS_BIN" 2>/dev/null \
        && log "BOOT_HASH" "Synced Tricky Store boot_hash.bin" \
        || log "BOOT_HASH" "Warning: failed to sync Tricky Store boot_hash.bin"
}

force=0
case "$1" in
    --refresh) force=1 ;;
    --vbmeta-size)
        _vbmeta_sizes | sed 's/^/PART_/; s/ /=/'
        printf 'COMPUTED=%s\nPROP=%s\n' "$(_vbmeta_total_size)" "$(getprop ro.boot.vbmeta.size 2>/dev/null)"
        exit 0
        ;;
    --set)
        _val=$(printf '%s' "$2" | _norm)
        [ -z "$_val" ] || _valid "$_val" || die "Invalid boot hash (needs 64 hex characters, not all zeros)"
        cfg_set custom_boot_hash "$_val"
        log "BOOT_HASH" "Custom boot hash: ${_val:-cleared}"
        [ -n "$_val" ] && force=1
        ;;
    "") ;;
    *) log "BOOT_HASH" "Warning: ignoring unexpected argument: $1" ;;
esac

boot_hash=""
hash_source=""

_pick "$(cfg_get custom_boot_hash "" | _norm)" custom
[ "$force" -eq 0 ] && _pick "$(_read "$BOOT_HASH_FILE")" cache
[ -z "$boot_hash" ] && _pick "$(_tee_probe)" tee
[ -z "$boot_hash" ] && _pick "$(getprop ro.boot.vbmeta.digest 2>/dev/null | _norm)" ro.boot.vbmeta.digest
[ -z "$boot_hash" ] && _pick "$(_read "$BOOT_HASH_FILE")" cache
[ -z "$boot_hash" ] && _pick "$(_random_hash)" generated

[ -n "$boot_hash" ] || die "Could not resolve a valid boot hash from any source"

case "$hash_source" in
    custom|cache) ;;
    *)
        ensure_dir "$(dirname "$BOOT_HASH_FILE")"
        echo "$boot_hash" > "$BOOT_HASH_FILE" || die "Failed to write $BOOT_HASH_FILE"
        ;;
esac
chmod 644 "$BOOT_HASH_FILE" 2>/dev/null

_publish "$boot_hash"

log "BOOT_HASH" "Stored Jerry boot hash (source: $hash_source)"
log "BOOT_HASH" "Finish"
exit 0
