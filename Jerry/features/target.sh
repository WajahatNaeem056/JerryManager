#!/system/bin/sh
set -e
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/package_list.sh"
. "$MODDIR/../lib/config_env.sh"

log "TARGET" "Start"

[ -d "$TRICKY_DIR" ] || die "Tricky Store data directory not found"

if _is_teesimulator; then
    log "TARGET" "TEESimulator — generating locked.xml section"
    _cust="/sdcard/JerryManager/customize.txt"
    if [ -f "$_cust" ] && [ "$(head -1 "$_cust" 2>/dev/null)" != "#disable" ]; then
      _locked=$(grep -v '^#' "$_cust" | sed 's/[!?]$//' 2>/dev/null || echo "")
      if [ -n "$_locked" ]; then
        [ -f "$TARGET_TXT" ] && cp "$TARGET_TXT" "${TARGET_TXT}.bak"
        _tmp=$(mktemp 2>/dev/null || echo "/data/local/tmp/.jerry_tee_$$")
        _locked_f="/data/local/tmp/.jerry_locked.$$"
        printf '%s\n' $_locked > "$_locked_f"
        if [ -f "$TARGET_TXT" ] && [ -s "$TARGET_TXT" ]; then
          sed '/^\[/d' "$TARGET_TXT" | grep -Fvxf "$_locked_f" > "$_tmp"
        fi
        rm -f "$_locked_f"
        printf '%s\n' '[locked.xml]' $_locked >> "$_tmp"
        [ -s "$_tmp" ] && mv -f "$_tmp" "$TARGET_TXT" || rm -f "$_tmp"
        unset _tmp
      fi
      unset _locked
    fi
    unset _cust
    log "TARGET" "Finish (TEESimulator)"
    exit 0
fi

_count=0
MODULE_ROOT="${MODDIR%/features}"

teeBroken="false"
for _tee_file in "$TEE_STATUS" "${TEE_STATUS}.txt"; do
  [ -f "$_tee_file" ] || continue
  teeBroken=$(grep -E '^(teeBroken|tee_broken)=' "$_tee_file" | cut -d= -f2 2>/dev/null || echo "false")
  break
done
unset _tee_file
log "TARGET" "TEE status: teeBroken=$teeBroken"

# Merge-only pass: manual App Targeting selections in target.txt (written
# directly by the WebUI) are the highest-priority source and are NEVER
# cleared or replaced here. This only appends whichever FIXED_TARGETS
# entries (by bare package name, ignoring any existing !/? suffix) are
# not already present. No auto-add-all-installed-apps step — that used to
# flood target.txt with every user app on every boot/update and stomp on
# manual selections.
ensure_dir "$TRICKY_DIR"
touch "$TARGET_TXT"

_EXISTING_BARE="${TARGET_TXT}.barepkgs.$$"
sed 's/[!?]$//' "$TARGET_TXT" | sort -u > "$_EXISTING_BARE"
trap 'rm -f "$_EXISTING_BARE"' EXIT

for entry in $FIXED_TARGETS; do
  _bare=$(printf '%s' "$entry" | sed 's/[!?]$//')
  if ! grep -Fqx "$_bare" "$_EXISTING_BARE"; then
    _suffix=""
    case "$entry" in
      *!) _suffix="!" ;;
      *\?)
        if [ "$teeBroken" != "true" ]; then _suffix="?"; fi
        ;;
    esac
    echo "${_bare}${_suffix}" >> "$TARGET_TXT"
    _count=$((_count + 1))
  fi
done

log "TARGET" "Merge pass: added $_count missing FIXED_TARGETS entries (existing manual entries untouched)"

# New-app automation lives in auto_target.sh (toggle_auto_target), which
# tracks known packages via auto_known_packages.txt. This used to be
# duplicated here via target_seen.txt/toggle_target — removed to avoid
# two independent systems doing the same job.

rm -f "$_EXISTING_BARE"
log "TARGET" "Finish"
exit 0
