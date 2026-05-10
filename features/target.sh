#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/package_list.sh"

log "TARGET" "Start"

if [ ! -d "/data/adb/tricky_store" ]; then
  log "TARGET" "Error: Tricky Store data directory not found"
  exit 1
fi

_count=0
MODULE_ROOT="${MODDIR%/features}"
TEMP_PKGS="$MODULE_ROOT/jerrykey_pkgs.txt"
trap 'rm -f "$TEMP_PKGS"' EXIT

teeBroken="false"
if [ -f "$TEE_STATUS" ]; then
  teeBroken=$(grep -E '^teeBroken=' "$TEE_STATUS" | cut -d '=' -f2 2>/dev/null || echo "false")
fi
log "TARGET" "TEE status: teeBroken=$teeBroken"

rm -f "$TARGET_TXT"

for entry in $FIXED_TARGETS; do
  echo "$entry" >> "$TARGET_TXT"
  _count=$((_count + 1))
done

for flag in "-3" "-s"; do
  pkgs=$(pm list packages "$flag" 2>/dev/null) || {
    log "TARGET" "Warning: Failed to list packages (flag $flag)"
    continue
  }
  [ -z "$pkgs" ] && continue

  echo "$pkgs" | cut -d ":" -f 2 > "$TEMP_PKGS"
  while read -r pkg; do
    [ -z "$pkg" ] && continue
    if [ "$teeBroken" = "true" ]; then
      echo "${pkg}?" >> "$TARGET_TXT"
    else
      echo "$pkg" >> "$TARGET_TXT"
    fi
    _count=$((_count + 1))
  done < "$TEMP_PKGS"
  rm -f "$TEMP_PKGS"
done

# Deduplicate target.txt (FIXED_TARGETS + system/user pkgs can overlap)
sort -u "$TARGET_TXT" -o "$TARGET_TXT" 2>/dev/null || true
_final_count=$(wc -l < "$TARGET_TXT" 2>/dev/null || echo "$_count")
log "TARGET" "Wrote $_final_count unique entries to target.txt (before dedup: $_count)"
log "TARGET" "Finish"
exit 0
