#!/system/bin/sh
set -e
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"

# block_rom_spoof_engines is defined in Jerry's common.sh
block_rom_spoof_engines
