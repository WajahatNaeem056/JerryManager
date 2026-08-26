#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/keystore.sh"

[ "$(cfg_get toggle_auto_target 1)" = "0" ] && exit 0

log "AUTO_TARGET" "Start"

resolve_keystore_backend

if [ "$KEYSTORE_BACKEND" = "none" ]; then
  log "AUTO_TARGET" "No active keystore backend found (Tricky Store / OhMyKeymint) — skipping"
  exit 0
fi

ensure_dir "$JERRYKEY_DIR"

KNOWN_PKGS="$JERRYKEY_DIR/auto_known_packages.txt"
TEMP_LIST="$JERRYKEY_DIR/auto_scan_tmp.txt"
NEW_LIST="$JERRYKEY_DIR/auto_new_tmp.txt"

PKG_FLAGS="-3"
[ "$(cfg_get toggle_target_system 0)" = "1" ] && PKG_FLAGS="-3 -s"

pkgs=""
for flag in $PKG_FLAGS; do
  _p=$(pm list packages "$flag" 2>/dev/null) || continue
  [ -z "$_p" ] && continue
  pkgs="$pkgs
$_p"
done
if [ -z "$pkgs" ]; then
  log "AUTO_TARGET" "Warning: pm list packages failed"
  exit 0
fi
echo "$pkgs" | cut -d ":" -f 2 | sed '/^$/d' | sort -u > "$TEMP_LIST"

if [ ! -s "$TEMP_LIST" ]; then
  rm -f "$TEMP_LIST"
  log "AUTO_TARGET" "No user packages found"
  log "AUTO_TARGET" "Finish"
  exit 0
fi

_known=""
[ -f "$KNOWN_PKGS" ] && _known=$(cat "$KNOWN_PKGS")

: > "$NEW_LIST"
while IFS= read -r _pkg; do
  [ -z "$_pkg" ] && continue
  if echo "$_known" | grep -Fxq "$_pkg" 2>/dev/null; then
    continue
  fi
  if [ "$KEYSTORE_BACKEND" = "trickystore" ] && grep -Fxq "$_pkg" "$TARGET_TXT" 2>/dev/null; then
    continue
  fi
  echo "$_pkg" >> "$NEW_LIST"
done < "$TEMP_LIST"

if [ -s "$NEW_LIST" ]; then
  _added=$(wc -l < "$NEW_LIST" 2>/dev/null || echo "0")
  if [ "$KEYSTORE_BACKEND" = "omk" ]; then
    while IFS= read -r _new_pkg; do
      [ -z "$_new_pkg" ] && continue
      keystore_add_target "$_new_pkg"
    done < "$NEW_LIST"
    log "AUTO_TARGET" "Added $_added new app(s) to OhMyKeymint injector.toml"
  else
    cat "$NEW_LIST" >> "$TARGET_TXT"
    sort -u "$TARGET_TXT" -o "$TARGET_TXT" 2>/dev/null
    log "AUTO_TARGET" "Added $_added new app(s) to target.txt"
  fi
else
  log "AUTO_TARGET" "No new apps found"
fi

cp "$TEMP_LIST" "$KNOWN_PKGS" 2>/dev/null || true
rm -f "$TEMP_LIST" "$NEW_LIST"

log "AUTO_TARGET" "Finish"
exit 0
