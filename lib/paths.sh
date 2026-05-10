# Tricky Store paths
TRICKY_DIR="/data/adb/tricky_store"
TARGET_FILE="$TRICKY_DIR/keybox.xml"
BACKUP_FILE="$TRICKY_DIR/keybox.xml.bak"
TARGET_TXT="$TRICKY_DIR/target.txt"
SECURITY_PATCH_FILE="$TRICKY_DIR/security_patch.txt"
TEE_STATUS="$TRICKY_DIR/tee_status"

# Other system paths
BOOT_HASH_FILE="/data/adb/boot_hash"
HMA_DIR="/data/user/0/org.frknkrc44.hma_oss/files"
HMA_FILE="$HMA_DIR/config.json"
IDFILE="/data/local/tmp/jerryid"

# Module-local paths — derived from MODDIR (set by caller before sourcing)
# Handles both feature scripts (MODDIR ends with /features) and root scripts
if [ -n "$MODDIR" ]; then
  case "$MODDIR" in
    */features) _JERRYKEY_ROOT="${MODDIR%/*}" ;;
    *)          _JERRYKEY_ROOT="$MODDIR" ;;
  esac
  BBIN="$_JERRYKEY_ROOT/bin"
  JERRYKEY_CONFIG_DIR="$_JERRYKEY_ROOT/config"
  MIGRATION_MARKER="$_JERRYKEY_ROOT/.migrated"
  unset _JERRYKEY_ROOT
fi
