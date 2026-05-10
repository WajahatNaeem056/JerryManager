#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/urls.sh"

log "HMA" "Start"

check_network || { log "HMA" "Error: No internet connection"; exit 1; }

if pm list packages | grep -q org.frknkrc44.hma_oss; then
  ensure_dir "$HMA_DIR"
  download "$HMA_CONFIG_URL" > "$HMA_FILE" || {
    log "HMA" "Error: HMA-oss config download failed"
    rm -f "$HMA_FILE"
    exit 1
  }
  if [ ! -s "$HMA_FILE" ]; then
    log "HMA" "Error: Downloaded HMA config is empty or invalid"
    rm -f "$HMA_FILE"
    exit 1
  fi
  chmod 600 "$HMA_FILE"
  _hma_uid=$(stat -c "%u" "$HMA_DIR" 2>/dev/null) || _hma_uid=0
  chown "$_hma_uid:$_hma_uid" "$HMA_FILE"
elif pm list packages | grep -q com.tsng.hidemyapplist; then
  log "HMA" "Warning: Legacy HMA detected, use latest HMA-oss for config support"
else
  log "HMA" "Warning: HMA-oss not installed, skipping"
fi

log "HMA" "Finish"
exit 0
