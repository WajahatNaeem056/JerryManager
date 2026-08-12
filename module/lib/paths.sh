# Tricky Store paths
TRICKY_DIR="/data/adb/tricky_store"
TARGET_FILE="$TRICKY_DIR/keybox.xml"
BACKUP_FILE="$TRICKY_DIR/keybox.xml.bak"
LOCKED_FILE="$TRICKY_DIR/locked.xml"
LOCKED_BACKUP="$TRICKY_DIR/locked.xml.bak"
TARGET_TXT="$TRICKY_DIR/target.txt"
SECURITY_PATCH_FILE="$TRICKY_DIR/security_patch.txt"
TEE_STATUS="$TRICKY_DIR/tee_status"

# Other system paths
BOOT_HASH_FILE="/data/adb/boot_hash"
IDFILE="/data/local/tmp/jerryid"

# Module-local paths — derived from MODDIR (set by caller before sourcing)
# Handles both feature scripts (MODDIR ends with /features) and root scripts
if [ -n "$MODDIR" ]; then
  case "$MODDIR" in
    */features) _JERRYKEY_ROOT="${MODDIR%/*}" ;;
    *)          _JERRYKEY_ROOT="$MODDIR" ;;
  esac
  BBIN="$_JERRYKEY_ROOT/bin"
  MIGRATION_MARKER="$_JERRYKEY_ROOT/.migrated"
  unset _JERRYKEY_ROOT
fi

# Toggle config storage — INTENTIONALLY OUTSIDE the module directory.
# KernelSU-Next (and KernelSU) stage customize.sh in /data/adb/modules_update/<id>
# and later swap/replace /data/adb/modules/<id> with that staged content on
# activation (reboot). Anything stored inside MODDIR — including a "config"
# subfolder — can get wiped or replaced by that swap on every reinstall/update.
# Storing config in an independent path outside the module directory (a
# pattern used by several root modules for this exact reason) means it
# is never touched by module activation, so toggle values survive reinstalls.
JERRYKEY_CONFIG_DIR="/data/adb/JerryManager/config"
