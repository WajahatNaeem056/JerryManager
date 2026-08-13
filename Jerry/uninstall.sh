#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/paths.sh"

if [ -f "$TARGET_FILE" ] && grep -q "jerryroot" "$TARGET_FILE" 2>/dev/null; then
    if [ -f "$BACKUP_FILE" ]; then
        rm -f "$TARGET_FILE"
        mv "$BACKUP_FILE" "$TARGET_FILE"
        log "UNINSTALL" "Restored original keybox from backup"
    fi
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

# Clean up RKA config in PassIt app data
return 0
