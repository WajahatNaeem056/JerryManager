#!/system/bin/sh
MODDIR=${0%/*}
_AT_SELF="$0"
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/keystore.sh"
. "$MODDIR/../lib/package_list.sh"
. "$MODDIR/../lib/notify.sh"
. "$MODDIR/../lib/toggle_seed.sh"

# Usage: auto_target.sh [boot|install|poll]   (no argument = boot)
# The scan itself is identical in every mode; the mode only decides which toggle
# may start it, so the two settings can never enable each other:
#   boot     the one scan per boot, started by service.sh after sys.boot_completed
#            (plus bounded retries if that scan could not complete).
#            Gate: toggle_auto_target ONLY.
#   install  install-triggered scan: inotify events via auto_target_notify.sh and
#            their delayed stages.   Gate: toggle_auto_target_immediate ONLY.
#   poll     60s recovery poll backing up missed inotify events. It finds apps that
#            appeared since the last scan, i.e. it IS install detection.
#            Gate: toggle_auto_target_immediate ONLY.
# Exit status: 0, except boot mode returns 75 when the scan did not complete
# (lock busy, no backend yet, pm failed) so service.sh can retry it.
AT_MODE="${1:-boot}"
case "$AT_MODE" in
  boot)         _AT_GATE="toggle_auto_target" ;;
  install|poll) _AT_GATE="toggle_auto_target_immediate" ;;
  *) log "AUTO_TARGET" "Unknown scan mode '$AT_MODE' — skipping"; exit 0 ;;
esac
_feature_enabled "$_AT_GATE" || exit 0

# Boot mode reports "could not complete" to its caller; other modes stay silent
_at_incomplete() { [ "$AT_MODE" = "boot" ] && exit 75; exit 0; }

# Idle scans (nothing new) stay silent; set auto_target_verbose=1 to log every scan
_AT_VERBOSE=$(cfg_get auto_target_verbose 0)
_at_vlog() { [ "$_AT_VERBOSE" = "1" ] && log "$@"; return 0; }

_at_vlog "AUTO_TARGET" "Start ($AT_MODE)"

resolve_keystore_backend

if [ "$KEYSTORE_BACKEND" = "none" ]; then
  _at_vlog "AUTO_TARGET" "No active keystore backend found — skipping"
  _at_incomplete
fi

ensure_dir "$JERRYMANAGER_DIR"

KNOWN_PKGS="$JERRYMANAGER_DIR/auto_known_packages.txt"
TEMP_LIST="$JERRYMANAGER_DIR/auto_scan_tmp.txt"
NEW_LIST="$JERRYMANAGER_DIR/auto_new_tmp.txt"
ADDED_LIST="$JERRYMANAGER_DIR/auto_added_tmp.txt"
AT_LOCK="$JERRYMANAGER_DIR/.auto_target.lock"
AT_PENDING="$JERRYMANAGER_DIR/.auto_target.pending"

# One scan at a time: overlapping runs (packages.xml bursts, poll + boot scan)
# would race on the temp files and could add or notify the same app twice.
_at_lock_acquire() {
  if mkdir "$AT_LOCK" 2>/dev/null; then
    echo "$$" > "$AT_LOCK/pid" 2>/dev/null
    return 0
  fi
  _ala_pid=$(cat "$AT_LOCK/pid" 2>/dev/null)
  _ala_age=$(( $(date +%s 2>/dev/null || echo 0) - $(stat -c %Y "$AT_LOCK" 2>/dev/null || echo 0) ))
  # Held: live owner (not older than 10 min), or owner still writing its pid
  if [ -n "$_ala_pid" ] && kill -0 "$_ala_pid" 2>/dev/null && [ "$_ala_age" -lt 600 ]; then
    return 1
  fi
  if [ -z "$_ala_pid" ] && [ "$_ala_age" -lt 30 ]; then
    return 1
  fi
  rm -rf "$AT_LOCK" 2>/dev/null
  mkdir "$AT_LOCK" 2>/dev/null || return 1
  echo "$$" > "$AT_LOCK/pid" 2>/dev/null
  return 0
}

# Order matters: flag first, then try the lock. Whoever owns the lock re-scans
# on exit if a flag appeared, so an event that arrives mid-scan is never lost.
touch "$AT_PENDING" 2>/dev/null
if ! _at_lock_acquire; then
  _at_vlog "AUTO_TARGET" "Another scan is running — re-scan queued"
  _at_incomplete
fi
rm -f "$AT_PENDING" 2>/dev/null

_at_cleanup() {
  rm -f "$TEMP_LIST" "$NEW_LIST" "$ADDED_LIST" 2>/dev/null
  rm -rf "$AT_LOCK" 2>/dev/null
  if [ -f "$AT_PENDING" ] && [ "${AUTO_TARGET_DEPTH:-0}" -lt 3 ]; then
    AUTO_TARGET_DEPTH=$(( ${AUTO_TARGET_DEPTH:-0} + 1 )) sh "$_AT_SELF" "$AT_MODE" 2>/dev/null
  fi
}
trap _at_cleanup EXIT

# True if $1 is already in the active backend's target list (Tricky Store
# lines may carry a ! or ? suffix)
_at_target_present() {
  [ -n "$KEYSTORE_TARGETS" ] && [ -f "$KEYSTORE_TARGETS" ] || return 1
  case "$KEYSTORE_FORMAT" in
    flat) grep -Fxq -e "$1" -e "$1!" -e "$1?" "$KEYSTORE_TARGETS" 2>/dev/null ;;
    *)    grep -q "\"$1\"" "$KEYSTORE_TARGETS" 2>/dev/null ;;
  esac
}

# Android system notification for the apps that were really added
_at_notify_added() {
  _an_n=$(wc -l < "$ADDED_LIST" 2>/dev/null | tr -d ' ')
  if [ "$_an_n" = "1" ]; then
    _an_msg="Successfully added 1 new app to the target list."
  else
    _an_msg="Successfully added $_an_n new apps to the target list."
  fi
  _an_names=$(head -n 3 "$ADDED_LIST" | tr '\n' ',' | sed 's/,$//; s/,/, /g')
  [ "$_an_n" -gt 3 ] && _an_names="$_an_names +$((_an_n - 3)) more"
  jn_post "JerryManager — Auto Target" "$_an_msg
$_an_names" "JerryManagerAutoTarget_$(date +%s 2>/dev/null)" || true
  unset _an_n _an_msg _an_names
}

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
  _at_incomplete
fi
echo "$pkgs" | cut -d ":" -f 2 | sed '/^$/d' | sort -u > "$TEMP_LIST"

if [ ! -s "$TEMP_LIST" ]; then
  rm -f "$TEMP_LIST"
  log "AUTO_TARGET" "No user packages found"
  _at_vlog "AUTO_TARGET" "Finish"
  exit 0
fi

# No known-packages file yet = first scan; it seeds the list, so no notification
_baseline=0
[ -f "$KNOWN_PKGS" ] || _baseline=1

_known=""
[ -f "$KNOWN_PKGS" ] && _known=$(cat "$KNOWN_PKGS")

_excluded=0
: > "$NEW_LIST"
while IFS= read -r _pkg; do
  [ -z "$_pkg" ] && continue
  if echo "$_known" | grep -Fxq "$_pkg" 2>/dev/null; then
    continue
  fi
  if is_auto_target_excluded "$_pkg"; then
    _excluded=$((_excluded + 1))
    continue
  fi
  if _at_target_present "$_pkg"; then
    continue
  fi
  echo "$_pkg" >> "$NEW_LIST"
done < "$TEMP_LIST"
[ "$_excluded" -gt 0 ] && log "AUTO_TARGET" "Excluded $_excluded root/Xposed manager app(s)"

if [ -s "$NEW_LIST" ]; then
  if [ "$KEYSTORE_BACKEND" = "omk" ] || [ "$KEYSTORE_BACKEND" = "teesim" ]; then
    while IFS= read -r _new_pkg; do
      [ -z "$_new_pkg" ] && continue
      keystore_add_target "$_new_pkg" >/dev/null 2>&1 || true
    done < "$NEW_LIST"
  else
    # Keep the last existing entry on its own line before appending
    if [ -s "$TARGET_TXT" ] && [ -n "$(tail -c1 "$TARGET_TXT" 2>/dev/null)" ]; then
      echo >> "$TARGET_TXT" 2>/dev/null
    fi
    cat "$NEW_LIST" >> "$TARGET_TXT" 2>/dev/null
    sort -u "$TARGET_TXT" -o "$TARGET_TXT" 2>/dev/null
  fi

  # Read back: only packages that are really in the list now count as added
  : > "$ADDED_LIST"
  _failed=0
  while IFS= read -r _chk_pkg; do
    [ -z "$_chk_pkg" ] && continue
    if _at_target_present "$_chk_pkg"; then
      echo "$_chk_pkg" >> "$ADDED_LIST"
    else
      _failed=$((_failed + 1))
      log "AUTO_TARGET" "Failed to add $_chk_pkg via $KEYSTORE_NAME"
    fi
  done < "$NEW_LIST"
  _added=$(wc -l < "$ADDED_LIST" 2>/dev/null | tr -d ' ')
  [ -z "$_added" ] && _added=0

  if [ "$_added" -gt 0 ]; then
    if [ "$KEYSTORE_BACKEND" = "omk" ] || [ "$KEYSTORE_BACKEND" = "teesim" ]; then
      log "AUTO_TARGET" "Added $_added new app(s) via $KEYSTORE_NAME [$AT_MODE]"
    else
      log "AUTO_TARGET" "Added $_added new app(s) to target.txt [$AT_MODE]"
    fi
    if [ "$_baseline" = "1" ]; then
      log "AUTO_TARGET" "First scan (baseline) — notification skipped"
    elif [ "$(cfg_get toggle_auto_target_notify 1)" = "0" ]; then
      log "AUTO_TARGET" "Notification disabled (toggle_auto_target_notify=0)"
    else
      _at_notify_added
    fi
  fi
  [ "$_failed" -gt 0 ] && log "AUTO_TARGET" "$_failed app(s) could not be added"
else
  _at_vlog "AUTO_TARGET" "No new apps found"
fi

cp "$TEMP_LIST" "$KNOWN_PKGS" 2>/dev/null || true

_at_vlog "AUTO_TARGET" "Finish"
exit 0
