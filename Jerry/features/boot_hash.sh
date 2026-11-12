#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"

# Usage: boot_hash.sh [--refresh | --set <64 hex> | --set (clears custom) | --show]
#   --show prints HASH=<64 hex or empty> and SOURCE=custom|cache|none, nothing is changed

TS_BIN="/data/adb/tricky_store/boot_hash.bin"

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
    exit 0
fi

log "BOOT_HASH" "Start (arg: ${1:-none})"

# Take the first valid candidate only
_pick() {
    [ -z "$boot_hash" ] && _valid "$1" && { boot_hash="$1"; source="$2"; }
    return 0
}

_tee_probe() {
    [ "$(getprop sys.boot_completed)" = "1" ] || return 0
    _dex="${MODDIR%/features}/dex/attest.dex"
    [ -f "$_dex" ] || return 0
    # Own watchdog (no busybox dependency): a stuck keystore must never hang the script or the WebUI
    _tp_out="/data/local/tmp/jerry_attest.$$"
    CLASSPATH="$_dex" app_process / com.jerry.attest.Main >"$_tp_out" 2>/dev/null &
    _tp_pid=$!
    _tp_i=0
    while kill -0 "$_tp_pid" 2>/dev/null && [ "$_tp_i" -lt 15 ]; do
        sleep 1
        _tp_i=$((_tp_i + 1))
    done
    if kill -0 "$_tp_pid" 2>/dev/null; then
        kill -9 "$_tp_pid" 2>/dev/null
        log "BOOT_HASH" "TEE probe timed out, falling back" >&2
    fi
    _norm < "$_tp_out"
    rm -f "$_tp_out" 2>/dev/null
}

_random_hash() { od -v -An -tx1 -N32 /dev/urandom 2>/dev/null | _norm; }

# Make the prop and Tricky Store agree with the resolved hash
_publish() {
    if [ "$(getprop ro.boot.vbmeta.digest 2>/dev/null | _norm)" != "$1" ]; then
        resetprop -n ro.boot.vbmeta.digest "$1" 2>/dev/null \
            && log "BOOT_HASH" "Aligned ro.boot.vbmeta.digest" \
            || log "BOOT_HASH" "Warning: failed to set ro.boot.vbmeta.digest"
    fi

    [ -d "$(dirname "$TS_BIN")" ] || return 0
    _cur=""
    [ -f "$TS_BIN" ] && _cur=$(od -An -tx1 "$TS_BIN" 2>/dev/null | tr -d ' \n')
    [ "$_cur" = "$1" ] && return 0
    printf '%b' "$(printf '%s' "$1" | sed 's/../\\x&/g')" > "$TS_BIN" 2>/dev/null \
        && log "BOOT_HASH" "Synced Tricky Store boot_hash.bin" \
        || log "BOOT_HASH" "Warning: failed to sync Tricky Store boot_hash.bin"
}

force=0
case "$1" in
    --refresh) force=1 ;;
    --set)
        _val=$(printf '%s' "$2" | _norm)
        [ -z "$_val" ] || _valid "$_val" || die "Invalid boot hash (needs 64 hex characters, not all zeros)"
        cfg_set custom_boot_hash "$_val"
        log "BOOT_HASH" "Custom boot hash: ${_val:-cleared}"
        force=1
        ;;
esac

boot_hash=""
source=""

# 1. Custom hash pinned by the user
_pick "$(cfg_get custom_boot_hash "" | _norm)" custom

# 2. Cache (skipped on --refresh so a better source can replace it)
[ "$force" -eq 0 ] && _pick "$(_read "$BOOT_HASH_FILE")" cache

# 3. TEE probe (needs keystore, so only after boot_completed)
[ -z "$boot_hash" ] && _pick "$(_tee_probe)" tee

# 4. Bootloader digest
[ -z "$boot_hash" ] && _pick "$(getprop ro.boot.vbmeta.digest 2>/dev/null | _norm)" ro.boot.vbmeta.digest

# 5. Existing cache, so --refresh without a better source keeps the same hash
[ -z "$boot_hash" ] && _pick "$(_read "$BOOT_HASH_FILE")" cache

# 6. Last resort, never zeros (cached, replaced later by a real source on --refresh)
[ -z "$boot_hash" ] && _pick "$(_random_hash)" generated

[ -n "$boot_hash" ] || die "Could not resolve a valid boot hash from any source"

# Persist (custom and cache hits are already stored)
case "$source" in
    custom|cache) ;;
    *)
        ensure_dir "$(dirname "$BOOT_HASH_FILE")"
        echo "$boot_hash" > "$BOOT_HASH_FILE" || die "Failed to write $BOOT_HASH_FILE"
        ;;
esac
chmod 644 "$BOOT_HASH_FILE" 2>/dev/null

_publish "$boot_hash"

log "BOOT_HASH" "Stored Jerry boot hash (source: $source)"
log "BOOT_HASH" "Finish"
exit 0
