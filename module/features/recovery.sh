#!/system/bin/sh
set -e
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"

# hide_recovery_folders is defined in Jerry's common.sh
hide_recovery_folders
