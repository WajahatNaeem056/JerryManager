#!/system/bin/sh
set -e
MODDIR=${0%/*}

. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/paths.sh"
. "$MODDIR/lib/config_env.sh"

# Fresh boot.log every boot — keeps only the current boot's log lines,
# instead of accumulating across every reboot until the 1MB rotation in
# log() (lib/common.sh) kicks in. This is the earliest module stage, so
# every later log() call in this boot cycle starts from a clean file.
mkdir -p "$(dirname "$JERRYKEY_LOG_FILE")" 2>/dev/null
: > "$JERRYKEY_LOG_FILE" 2>/dev/null || true

resolve_conflicts
