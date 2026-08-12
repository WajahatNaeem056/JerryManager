#!/system/bin/sh
set -e
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"

# disable_bootloader_spoofer is defined in Jerry's common.sh
disable_bootloader_spoofer
