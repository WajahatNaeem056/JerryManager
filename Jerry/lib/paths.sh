# Tricky Store paths
TRICKY_DIR="/data/adb/tricky_store"
TARGET_FILE="$TRICKY_DIR/keybox.xml"
BACKUP_FILE="$TRICKY_DIR/keybox.xml.bak"
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

BOOT_HASH_FILE="/data/adb/boot_hash"
IDFILE="/data/local/tmp/jerryid"

if [ -n "$MODDIR" ]; then
  case "$MODDIR" in
    */features) _JERRYKEY_ROOT="${MODDIR%/*}" ;;
    *)          _JERRYKEY_ROOT="$MODDIR" ;;
  esac
  BBIN="$_JERRYKEY_ROOT/bin"
  MIGRATION_MARKER="$_JERRYKEY_ROOT/.migrated"
  unset _JERRYKEY_ROOT
fi

JERRYKEY_CONFIG_DIR="/data/adb/JerryManager/config"
