#!/system/bin/sh
# Hide Other Root Solutions: --hide / --restore / --dry-run / --status
# Only moves a root positively detected as NOT active; no signal, no move.
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"

MODE="${1:---hide}"
ADB_DIR="/data/adb"
MR_BACKUP_DIR="$JERRYMANAGER_DIR/RootBackup"
MR_ALL_ROOTS="magisk apatch kernelsu"
MR_ALL_ITEMS="magisk ap apd fp ksu ksud"

_mr_items_for() {
    case "$1" in
        magisk)   echo "magisk" ;;
        apatch)   echo "ap apd fp" ;;
        kernelsu) echo "ksu ksud" ;;
    esac
}

_mr_exists() { [ -e "$1" ] || [ -L "$1" ]; }

# Roots positively detected as running right now (space separated)
_mr_detect_active() {
    _mr_ov=$(cfg_get multiroot_active_root auto)
    case "$_mr_ov" in
        magisk|kernelsu|apatch) echo "$_mr_ov"; return 0 ;;
    esac

    _mr_act=""

    # APatch also exports KSU=true, so check it first
    if [ "$APATCH" = "true" ] || command -v apd >/dev/null 2>&1; then
        _mr_act="$_mr_act apatch"
    elif [ "$KSU" = "true" ] || command -v ksud >/dev/null 2>&1; then
        _mr_act="$_mr_act kernelsu"
    fi
    if [ -n "$MAGISK_VER_CODE" ] || command -v magisk >/dev/null 2>&1 || pidof magiskd >/dev/null 2>&1; then
        _mr_act="$_mr_act magisk"
    fi

    for _mr_pid in $$ $PPID; do
        _mr_exe=$(readlink "/proc/$_mr_pid/exe" 2>/dev/null)
        case "$_mr_exe" in
            "$ADB_DIR"/magisk|"$ADB_DIR"/magisk/*)           _mr_act="$_mr_act magisk" ;;
            "$ADB_DIR"/ksu|"$ADB_DIR"/ksu/*|"$ADB_DIR"/ksud) _mr_act="$_mr_act kernelsu" ;;
            "$ADB_DIR"/ap|"$ADB_DIR"/ap/*|"$ADB_DIR"/apd|"$ADB_DIR"/fp|"$ADB_DIR"/fp/*) _mr_act="$_mr_act apatch" ;;
        esac
    done

    echo $_mr_act
    unset _mr_ov _mr_act _mr_pid _mr_exe
}

# True if $1 is where the running shell (or its parent) executes from
_mr_in_use() {
    for _miu_pid in $$ $PPID; do
        _miu_exe=$(readlink "/proc/$_miu_pid/exe" 2>/dev/null)
        case "$_miu_exe" in
            "$1"|"$1"/*) unset _miu_pid _miu_exe; return 0 ;;
        esac
    done
    unset _miu_pid _miu_exe
    return 1
}

mr_restore() {
    [ -d "$MR_BACKUP_DIR" ] || return 0
    _mrr_n=0
    for _mrr_item in $MR_ALL_ITEMS; do
        _mrr_bak="$MR_BACKUP_DIR/$_mrr_item"
        _mrr_src="$ADB_DIR/$_mrr_item"
        _mr_exists "$_mrr_bak" || continue
        if _mr_exists "$_mrr_src"; then
            log "MULTIROOT" "$_mrr_src is back already, dropping older backup"
            rm -rf "$_mrr_bak"
        elif mv -f "$_mrr_bak" "$_mrr_src" 2>/dev/null; then
            log "MULTIROOT" "Restored $_mrr_src"
            _mrr_n=$((_mrr_n + 1))
        else
            log "MULTIROOT" "Warning: could not restore $_mrr_src (backup kept in $MR_BACKUP_DIR)"
        fi
    done
    rmdir "$MR_BACKUP_DIR" 2>/dev/null
    [ "$_mrr_n" -gt 0 ] && log "MULTIROOT" "Restored $_mrr_n item(s)"
    unset _mrr_n _mrr_item _mrr_bak _mrr_src
    return 0
}

mr_hide() {
    _mrh_dry="$1"
    _mrh_active=$(_mr_detect_active)
    if [ -z "$_mrh_active" ]; then
        log "MULTIROOT" "Could not positively identify the active root - nothing moved"
        return 0
    fi
    log "MULTIROOT" "Active root: $_mrh_active"

    _mrh_n=0
    for _mrh_root in $MR_ALL_ROOTS; do
        case " $_mrh_active " in *" $_mrh_root "*) continue ;; esac
        for _mrh_item in $(_mr_items_for "$_mrh_root"); do
            _mrh_src="$ADB_DIR/$_mrh_item"
            _mrh_bak="$MR_BACKUP_DIR/$_mrh_item"
            _mr_exists "$_mrh_src" || continue
            if _mr_in_use "$_mrh_src"; then
                log "MULTIROOT" "Skipped $_mrh_src (a running process uses it)"
                continue
            fi
            if [ "$_mrh_dry" = "1" ]; then
                log "MULTIROOT" "DRY-RUN would move $_mrh_src -> $_mrh_bak"
                continue
            fi
            ensure_dir "$MR_BACKUP_DIR"
            _mr_exists "$_mrh_bak" && rm -rf "$_mrh_bak"
            if mv -f "$_mrh_src" "$_mrh_bak" 2>/dev/null; then
                log "MULTIROOT" "Hid $_mrh_src"
                _mrh_n=$((_mrh_n + 1))
            else
                log "MULTIROOT" "Warning: could not move $_mrh_src"
            fi
        done
    done
    [ "$_mrh_dry" = "1" ] || log "MULTIROOT" "Hidden $_mrh_n item(s)"
    unset _mrh_dry _mrh_active _mrh_n _mrh_root _mrh_item _mrh_src _mrh_bak
    return 0
}

case "$MODE" in
    --restore)
        mr_restore
        ;;
    --status)
        echo "Active root(s): $(_mr_detect_active)"
        ;;
    --dry-run)
        mr_hide 1
        ;;
    --hide|*)
        if [ "$(cfg_get safemode 0)" = "1" ]; then
            log "MULTIROOT" "Safe Mode is on - restoring any hidden root folders instead"
            mr_restore
        else
            mr_hide 0
        fi
        ;;
esac
exit 0
