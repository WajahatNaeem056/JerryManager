#!/system/bin/sh
set -e
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"

apply_boot_hardening
chmod 440 /proc/cmdline       2>/dev/null || true
chmod 440 /proc/net/unix      2>/dev/null || true
find /vendor/bin /system/bin -name install-recovery.sh \
    -exec chmod 440 {} + 2>/dev/null || true
chmod 750 /system/addon.d     2>/dev/null || true
