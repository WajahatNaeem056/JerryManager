#!/system/bin/sh
# Backend-aware target list I/O for the WebUI (Tricky Store target.txt / config.ini, OMK scoop, TEESimulator apps).
#   targets_io.sh --backend   prints __BACKEND__:<name>
#   targets_io.sh --read      prints the active target list
#   targets_io.sh --patches   prints per-app patch dates (Tricky Store target.txt only)
#   targets_io.sh --write F   replaces the target list with the package list in file F
MODDIR=${0%/*}
# WebUI (ksu.exec) can start with a bare PATH: make sure awk/sed/tr/cp resolve
PATH="/system/bin:/system/xbin:/data/adb/ksu/bin:/data/adb/ap/bin:/data/adb/magisk:$PATH"; export PATH
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/keystore.sh"
. "$MODDIR/../lib/package_list.sh"
resolve_keystore_backend >/dev/null 2>&1

case "${1:-}" in
    --backend)
        _b="$KEYSTORE_BACKEND"
        [ "$_b" = "trickystore" ] && [ "$KEYSTORE_FORMAT" = "ini" ] && _b="trickystore-ini"
        echo "__BACKEND__:$_b"
        ;;
    --read)    keystore_read_targets ;;
    --patches) keystore_read_per_app_patches 2>/dev/null; exit 0 ;;
    --write)
        [ -f "${2:-}" ] || die "targets_io: list file missing"
        for _tio_c in awk sed tr cp; do command -v "$_tio_c" >/dev/null 2>&1 || die "targets_io: '$_tio_c' not found in PATH=$PATH"; done
        [ "$KEYSTORE_BACKEND" != "none" ] || die "No active keystore backend found"
        _tio_src="$2"; _tio_bl=""
        if auto_target_blacklist_active; then
            _tio_bl="${2}.bl.$$"
            tr -d '\r' < "$AUTO_TARGET_BLACKLIST_FILE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
                | grep -vE '^(#|$)' > "${_tio_bl}.list" 2>/dev/null
            printf '%s\n' $FIXED_TARGETS > "${_tio_bl}.fx"
            awk '
                FILENAME == ARGV[1] { bl[$0] = 1; next }
                FILENAME == ARGV[2] { fx[$0] = 1; next }
                { l = $0; sub(/\r$/, "", l); b = l; sub(/[!?]$/, "", b)
                  if ((b in bl) && !(b in fx)) { skipped++; next }
                  print l }
                END { if (skipped) print skipped > "/dev/stderr" }' "${_tio_bl}.list" "${_tio_bl}.fx" "$2" > "$_tio_bl" 2>"${_tio_bl}.n"
            [ -s "${_tio_bl}.n" ] && log "TARGET_IO" "Skipped $(cat "${_tio_bl}.n") blacklisted app(s)"
            _tio_src="$_tio_bl"
        fi
        log "TARGET_IO" "Write start ($(grep -c . "$_tio_src" 2>/dev/null) entries) via $KEYSTORE_NAME"
        _tio_err=$(keystore_set_targets "$_tio_src" 2>&1 >/dev/null) || { [ -n "$_tio_bl" ] && rm -f "$_tio_bl" "${_tio_bl}.list" "${_tio_bl}.fx" "${_tio_bl}.n"; die "Failed to write target list via $KEYSTORE_NAME${_tio_err:+: $_tio_err}"; }
        [ -n "$_tio_bl" ] && rm -f "$_tio_bl" "${_tio_bl}.list" "${_tio_bl}.fx" "${_tio_bl}.n"
        log "TARGET_IO" "Write done"
        ;;
    *) echo "usage: targets_io.sh --backend|--read|--patches|--write FILE" >&2; exit 2 ;;
esac
