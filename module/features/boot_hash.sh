#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"

log "BOOT_HASH" "Start"

boot_hash=$(getprop ro.boot.vbmeta.digest 2>/dev/null)
if [ -z "$boot_hash" ]; then
  boot_hash="0000000000000000000000000000000000000000000000000000000000000000"
  log "BOOT_HASH" "Warning: No vbmeta digest found, using default"
fi

ensure_dir "$(dirname "$BOOT_HASH_FILE")"
echo "$boot_hash" > "$BOOT_HASH_FILE" || die "Failed to write $BOOT_HASH_FILE"
chmod 644 "$BOOT_HASH_FILE" || log "BOOT_HASH" "Warning: Failed to set permissions on $BOOT_HASH_FILE"

resetprop -n ro.boot.vbmeta.digest "$boot_hash" >/dev/null 2>&1

log "BOOT_HASH" "Wrote hash to $BOOT_HASH_FILE"
log "BOOT_HASH" "Finish"
exit 0
