# shellcheck shell=sh
# Tricky Store paths
TRICKY_DIR="/data/adb/tricky_store"
TARGET_FILE="$TRICKY_DIR/keybox.xml"
LOCKED_FILE="$TRICKY_DIR/locked.xml"
LOCKED_BACKUP="$TRICKY_DIR/locked.xml.bak"
TARGET_TXT="$TRICKY_DIR/target.txt"
SECURITY_PATCH_FILE="$TRICKY_DIR/security_patch.txt"
TEE_STATUS="$TRICKY_DIR/tee_status"
# OhMyKeymint paths (alternate keystore backend, see lib/keystore.sh)
OMK_DIR="/data/misc/keystore/omk"
OMK_KEYBOX="$OMK_DIR/keybox.xml"
OMK_INJECTOR="$OMK_DIR/injector.toml"
OMK_CONFIG="$OMK_DIR/config.toml"
OMK_RESTART_DIR="/data/adb/omk"
# TEESimulator paths
TEESIM_DIR="/data/adb/teesim"
TEESIM_CONFIG="$TEESIM_DIR/config.json"

KEYBOX_BACKUP_DIR="/data/adb/JerryManager/KeyBackup"
ensure_dir "$KEYBOX_BACKUP_DIR"

find_keybox_backup() {
  find "$KEYBOX_BACKUP_DIR" -maxdepth 1 -type f -name "${1}_keybox_*.xml" 2>/dev/null | head -n1
}

# BACKUP_FILE / OMK_BACKUP resolve to the EXISTING backup for their backend
# if one was already made, so "[ -f "$BACKUP_FILE" ]" checks and restores
# throughout the codebase keep working unchanged. If no backup exists yet,
# they resolve to a fresh timestamped path (not yet created) ready for the
# next "cp ... "$BACKUP_FILE"" call that makes the one-time backup.
_resolve_keybox_backup_var() {
  _existing="$(find_keybox_backup "$1")"
  if [ -n "$_existing" ]; then
    echo "$_existing"
  else
    echo "$KEYBOX_BACKUP_DIR/${1}_keybox_$(date '+%Y%m%d_%H%M%S').xml"
  fi
}
BACKUP_FILE="$(_resolve_keybox_backup_var trickystore)"
OMK_BACKUP="$(_resolve_keybox_backup_var omk)"

BOOT_HASH_FILE="/data/adb/boot_hash"
IDFILE="/data/local/tmp/jerryid"

if [ -n "$MODDIR" ]; then
  case "$MODDIR" in
    */features) _JERRYMANAGER_ROOT="${MODDIR%/*}" ;;
    *)          _JERRYMANAGER_ROOT="$MODDIR" ;;
  esac
  BBIN="$_JERRYMANAGER_ROOT/bin"
  MIGRATION_MARKER="$_JERRYMANAGER_ROOT/.migrated"
  unset _JERRYMANAGER_ROOT
fi

JERRYMANAGER_CONFIG_DIR="/data/adb/JerryManager/config"

CUSTOM_ROM_LOG_DIR="/data/adb/JerryManager/CustomRomLogs"
