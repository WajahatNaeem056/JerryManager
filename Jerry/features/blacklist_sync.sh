#!/system/bin/sh
# Immediately remove blacklisted packages from the active backend after the
# WebUI saves blacklist.txt. This deliberately does not run an Auto Target scan.
MODDIR=${0%/*}
# WebUI (ksu.exec) can start with a bare PATH: make sure awk/sed/tr/cp resolve
PATH="/system/bin:/system/xbin:/data/adb/ksu/bin:/data/adb/ap/bin:/data/adb/magisk:$PATH"; export PATH
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/keystore.sh"
. "$MODDIR/../lib/package_list.sh"

resolve_keystore_backend >/dev/null 2>&1

if ! auto_target_blacklist_active; then
    log "BLACKLIST" "Immediate sync skipped — blacklist is disabled or empty"
    echo "__JERRY_BLACKLIST_SYNC__:skipped"
    exit 0
fi

if [ "$KEYSTORE_BACKEND" = "none" ] || [ -z "$KEYSTORE_TARGETS" ]; then
    log "BLACKLIST" "Immediate sync skipped — no active backend"
    echo "__JERRY_BLACKLIST_SYNC__:no-backend"
    exit 0
fi

# A failed read (missing tool) must never look like "package not in the list"
for _bs_c in awk sed tr cp grep; do
    command -v "$_bs_c" >/dev/null 2>&1 || {
        log "BLACKLIST" "Immediate sync aborted — '$_bs_c' not found in PATH=$PATH"
        echo "__JERRY_BLACKLIST_SYNC__:failed:missing-$_bs_c"
        exit 1
    }
done
unset _bs_c

_bs_tmp="$JERRYMANAGER_DIR/.blacklist_sync.$$"
_bs_want="$_bs_tmp.want"     # valid, de-duplicated, non-protected entries of blacklist.txt
_bs_cur="$_bs_tmp.cur"       # packages currently in the backend list (all TEESimulator profiles)
_bs_todo="$_bs_tmp.todo"     # blacklisted packages that really are in the backend list
_bs_after="$_bs_tmp.after"
trap 'rm -f "$_bs_want" "$_bs_cur" "$_bs_todo" "$_bs_after" "$_bs_tmp.known" 2>/dev/null' EXIT
ensure_dir "$JERRYMANAGER_DIR" 2>/dev/null
: > "$_bs_want"; : > "$_bs_todo"

_seen="|"
while IFS= read -r _pkg || [ -n "$_pkg" ]; do
    _pkg=$(printf '%s' "$_pkg" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    case "$_pkg" in ''|\#*) continue ;; esac
    printf '%s\n' "$_pkg" | grep -Eq '^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$' || {
        log "BLACKLIST" "Ignored invalid package entry"
        continue
    }
    case "$_seen" in *"|$_pkg|"*) continue ;; esac
    _seen="${_seen}${_pkg}|"

    # Core platform packages are intentionally protected by Jerry (FIXED_TARGETS is newline separated)
    _fixed=0
    for _f in $FIXED_TARGETS; do
        [ "$_pkg" = "$_f" ] && { _fixed=1; break; }
    done
    [ "$_fixed" = "1" ] && continue

    echo "$_pkg" >> "$_bs_want"
done < "$AUTO_TARGET_BLACKLIST_FILE"

# One read of the backend list, then only touch packages that are really in it
keystore_read_targets_all 2>/dev/null | sed 's/[!?]$//' > "$_bs_cur"
while IFS= read -r _pkg; do
    [ -n "$_pkg" ] || continue
    grep -Fxq -- "$_pkg" "$_bs_cur" 2>/dev/null && echo "$_pkg" >> "$_bs_todo"
done < "$_bs_want"

_total=$(grep -c . "$_bs_want" 2>/dev/null); [ -n "$_total" ] || _total=0
_present=$(grep -c . "$_bs_todo" 2>/dev/null); [ -n "$_present" ] || _present=0
_absent=$((_total - _present))
_removed=0
_failed=0

if [ "$_present" -gt 0 ]; then
    keystore_remove_targets_file "$_bs_todo" >/dev/null 2>&1
    # Verify against a fresh read: success means "no longer in the list", not "the command returned 0"
    keystore_read_targets_all 2>/dev/null | sed 's/[!?]$//' > "$_bs_after"
    while IFS= read -r _pkg; do
        [ -n "$_pkg" ] || continue
        if grep -Fxq -- "$_pkg" "$_bs_after" 2>/dev/null; then
            _failed=$((_failed + 1))
            log "BLACKLIST" "Could not verify removal of $_pkg via $KEYSTORE_NAME"
        else
            _removed=$((_removed + 1))
        fi
    done < "$_bs_todo"
fi

# Blacklisted apps must not stay in Auto Target's known-packages list, otherwise they are
# never picked up again after being un-blacklisted. Skipped while a scan is running: the
# scan rewrites that file itself.
_bs_known="$JERRYMANAGER_DIR/auto_known_packages.txt"
if [ -s "$_bs_known" ] && [ -s "$_bs_want" ] && [ ! -d "$JERRYMANAGER_DIR/.auto_target.lock" ]; then
    grep -vxFf "$_bs_want" "$_bs_known" > "$_bs_tmp.known" 2>/dev/null
    # grep exits 1 when every line was dropped; an empty result is still valid
    cat "$_bs_tmp.known" > "$_bs_known" 2>/dev/null
fi

log "BLACKLIST" "Immediate sync finished via $KEYSTORE_NAME: removed=$_removed failed=$_failed absent=$_absent"
echo "__JERRY_BLACKLIST_SYNC__:removed=$_removed:failed=$_failed:absent=$_absent"
[ "$_failed" -eq 0 ]
