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
    die "No active keystore backend found"
fi

if [ "$KEYSTORE_BACKEND" = "omk" ]; then
    log "TARGET" "OhMyKeymint active — merging FIXED_TARGETS into injector.toml"
    _omk_count=0
    for entry in $FIXED_TARGETS; do
        _bare=$(printf '%s' "$entry" | sed 's/[!?]$//')
        if keystore_add_target "$_bare"; then
            _omk_count=$((_omk_count + 1))
        fi
    done
    unset _bare
    log "TARGET" "OhMyKeymint: processed $_omk_count FIXED_TARGETS entries"
    log "TARGET" "Finish (OhMyKeymint)"
    exit 0
fi

if [ "$KEYSTORE_BACKEND" = "teesim" ]; then
    log "TARGET" "$KEYSTORE_NAME active — merging FIXED_TARGETS into config.json"
    _teesim_count=0
    for entry in $FIXED_TARGETS; do
        _bare=$(printf '%s' "$entry" | sed 's/[!?]$//')
        if keystore_add_target "$_bare"; then
            _teesim_count=$((_teesim_count + 1))
        fi
    done
    unset _bare
    log "TARGET" "$KEYSTORE_NAME: processed $_teesim_count FIXED_TARGETS entries"
    log "TARGET" "Finish ($KEYSTORE_NAME)"
    exit 0
fi

[ -d "$TRICKY_DIR" ] || die "Tricky Store data directory not found"

# Tricky Store with config.ini: add FIXED_TARGETS to [target] through the backend helper
if [ "$KEYSTORE_FORMAT" = "ini" ]; then
  teeBroken="false"
  for _tee_file in "$TEE_STATUS" "${TEE_STATUS}.txt"; do
    [ -f "$_tee_file" ] || continue
    teeBroken=$(grep -E '^(teeBroken|tee_broken)=' "$_tee_file" | cut -d= -f2 2>/dev/null || echo "false")
    break
  done
  log "TARGET" "TEE status: teeBroken=$teeBroken (config.ini)"
  _ini_count=0
  for entry in $FIXED_TARGETS; do
    _bare=$(printf '%s' "$entry" | sed 's/[!?]$//')
    _suffix=""
    case "$entry" in
      *!) _suffix="!" ;;
      *\?) if [ "$teeBroken" != "true" ]; then _suffix="?"; fi ;;
    esac
    _had=0
    keystore_read_targets | sed 's/[!?]$//' | grep -Fxq "$_bare" && _had=1
    if [ "$_had" = "0" ] && keystore_add_target "$_bare" "$_suffix"; then
      _ini_count=$((_ini_count + 1))
    fi
  done
  log "TARGET" "Merge pass: added $_ini_count missing FIXED_TARGETS entries to config.ini"
  log "TARGET" "Finish ($KEYSTORE_NAME)"
  exit 0
fi

_count=0

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
