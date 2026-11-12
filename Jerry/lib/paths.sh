# Tricky Store paths
TRICKY_DIR="/data/adb/tricky_store"
TARGET_FILE="$TRICKY_DIR/keybox.xml"
TARGET_TXT="$TRICKY_DIR/target.txt"
SECURITY_PATCH_FILE="$TRICKY_DIR/security_patch.txt"
TRICKY_CONFIG="$TRICKY_DIR/config.ini"
TEE_STATUS="$TRICKY_DIR/tee_status"
# OhMyKeymint paths (alternate keystore backend, see lib/keystore.sh)
# OMK live data dir: /data/adb/omk/omkdata (the old /data/misc/keystore/omk is only a fallback when omkdata does not exist)
OMK_DIR="/data/adb/omk/omkdata"
if [ ! -d "$OMK_DIR" ] && [ -d /data/misc/keystore/omk ]; then
OMK_DIR="/data/misc/keystore/omk"
fi
OMK_KEYBOX="$OMK_DIR/keybox.xml"
OMK_INJECTOR="$OMK_DIR/injector.toml"
OMK_CONFIG="$OMK_DIR/config.toml"
OMK_RESTART_DIR="/data/adb/omk"
# TEESimulator paths
TEESIM_DIR="/data/adb/teesim"
TEESIM_CONFIG="$TEESIM_DIR/config.json"
TEESIM_KEYBOX="$TEESIM_DIR/keybox.xml"

KEYBOX_BACKUP_DIR="/data/adb/JerryManager/KeyBackup"
mkdir -p "$KEYBOX_BACKUP_DIR" 2>/dev/null

find_keybox_backup() {
  find "$KEYBOX_BACKUP_DIR" -maxdepth 1 -type f -name "${1}_keybox_*.xml" 2>/dev/null | head -n1
}

# True if the keybox file was installed by Jerry (marker inside the file). Jerry's own keybox is never backed up.
keybox_is_jerry() {
  grep -qE 'jerryroot|JERRY-KEYBOX' "$1" 2>/dev/null
}

# Existing backup path if one exists, else a fresh timestamped path to create
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
TEESIM_BACKUP="$(_resolve_keybox_backup_var teesim)"

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
