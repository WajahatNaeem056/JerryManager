#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/paths.sh"

# Put back persist.* props that Jerry changed or deleted (format: restore|name|value)
if [ -f "$PERSIST_RESTORE_FILE" ]; then
    while IFS='|' read -r _pr_cmd _pr_name _pr_val; do
        [ "$_pr_cmd" = "restore" ] || continue
        [ -n "$_pr_name" ] || continue
        resetprop -n -p "$_pr_name" "$_pr_val" 2>/dev/null || true
        log "UNINSTALL" "Restored prop: $_pr_name"
    done < "$PERSIST_RESTORE_FILE"
    rm -f "$PERSIST_RESTORE_FILE" 2>/dev/null
    unset _pr_cmd _pr_name _pr_val
fi

# Restore any root folders hidden by multiroot_hide.sh
[ -f "$MODDIR/features/multiroot_hide.sh" ] && sh "$MODDIR/features/multiroot_hide.sh" --restore 2>/dev/null

if [ -f "$TARGET_FILE" ] && grep -q "jerryroot" "$TARGET_FILE" 2>/dev/null; then
    _uninstall_ts_backup="$(find_keybox_backup trickystore)"
    if [ -n "$_uninstall_ts_backup" ]; then
        rm -f "$TARGET_FILE"
        cp "$_uninstall_ts_backup" "$TARGET_FILE"
        log "UNINSTALL" "Restored original keybox from backup (Tricky Store)"
    fi
    unset _uninstall_ts_backup
fi

if [ -f "$OMK_KEYBOX" ] && grep -q "jerryroot" "$OMK_KEYBOX" 2>/dev/null; then
    _uninstall_omk_backup="$(find_keybox_backup omk)"
    if [ -n "$_uninstall_omk_backup" ]; then
        rm -f "$OMK_KEYBOX"
        cp "$_uninstall_omk_backup" "$OMK_KEYBOX"
        log "UNINSTALL" "Restored original keybox from backup (OhMyKeymint)"
    fi
    unset _uninstall_omk_backup
fi

if [ -d "$BBIN" ]; then
    rm -rf "$BBIN" 2>/dev/null
    log "UNINSTALL" "Removed $BBIN"
fi

if [ -f "$MIGRATION_MARKER" ]; then
    rm -f "$MIGRATION_MARKER" 2>/dev/null
    log "UNINSTALL" "Removed migration marker"
fi

if [ -f "$BOOT_HASH_FILE" ]; then
    rm -f "$BOOT_HASH_FILE" 2>/dev/null
    log "UNINSTALL" "Removed boot hash file"
fi

if [ -f "$IDFILE" ]; then
    rm -f "$IDFILE" 2>/dev/null
    log "UNINSTALL" "Removed RKA ID file"
fi

exit 0
