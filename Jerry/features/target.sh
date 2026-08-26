#!/system/bin/sh
set -e
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/package_list.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/keystore.sh"

log "TARGET" "Start"

resolve_keystore_backend

if [ "$KEYSTORE_BACKEND" = "none" ]; then
    die "No active keystore backend found (Tricky Store / OhMyKeymint)"
fi

if [ "$KEYSTORE_BACKEND" = "omk" ]; then
    log "TARGET" "OhMyKeymint active — merging FIXED_TARGETS into injector.toml"
    _omk_count=0
    for entry in $FIXED_TARGETS; do
        _bare=$(printf '%s' "$entry" | sed 's/[!?]$//')
        keystore_add_target "$_bare" && _omk_count=$((_omk_count + 1))
    done
    unset _bare
    log "TARGET" "OhMyKeymint: processed $_omk_count FIXED_TARGETS entries"
    log "TARGET" "Finish (OhMyKeymint)"
    exit 0
fi

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

rm -f "$_EXISTING_BARE"
log "TARGET" "Finish"
exit 0
