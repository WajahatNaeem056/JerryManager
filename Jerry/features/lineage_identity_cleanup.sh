#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"

LINEAGE_IDENTITY_CLEANUP_PROP_FILE="$MODDIR/lineage_identity_cleanup.prop"

if [ "$(cfg_get "safemode" "0")" = "1" ]; then
    log_customrom "LINEAGE_IDENTITY_CLEANUP" "Skipped — Safe Mode is on"
    exit 0
fi

if [ ! -f "$LINEAGE_IDENTITY_CLEANUP_PROP_FILE" ]; then
    log_customrom "LINEAGE_IDENTITY_CLEANUP" "No lineage_identity_cleanup.prop found — nothing to spoof"
    exit 0
fi

ensure_dir "$JERRYMANAGER_DIR"
log_customrom "LINEAGE_IDENTITY_CLEANUP" "Script started"

while IFS= read -r _hl_line || [ -n "$_hl_line" ]; do
    _hl_clean=$(echo "$_hl_line" | sed -E 's/^\[(.*)\]=\[(.*)\]$/\1=\2/')

    if [ -z "$_hl_clean" ] || echo "$_hl_clean" | grep -qE '^#'; then
        continue
    fi

    _hl_key=$(echo "$_hl_clean" | cut -d '=' -f1)
    _hl_value=$(echo "$_hl_clean" | cut -d '=' -f2-)

    if [ -z "$_hl_key" ]; then
        log_customrom "LINEAGE_IDENTITY_CLEANUP" "SKIP malformed line: $_hl_line"
        continue
    fi

    case "$_hl_key" in
        init.svc.*|ro.boottime.*)
            log_customrom "LINEAGE_IDENTITY_CLEANUP" "SKIP dynamic prop (not changeable): $_hl_key"
            continue
            ;;
        ro.crypto.state)
            log_customrom "LINEAGE_IDENTITY_CLEANUP" "SKIP encryption state spoof: $_hl_key"
            continue
            ;;
        *)
            resetprop -n "$_hl_key" "$_hl_value" 2>/dev/null
            _hl_actual=$(resetprop "$_hl_key" 2>/dev/null)
            if [ "$_hl_actual" = "$_hl_value" ]; then
                log_customrom "LINEAGE_IDENTITY_CLEANUP" "OK overridden: $_hl_key=$_hl_value"
            elif [ -z "$_hl_value" ]; then
                # Empty-value set can silently fail/no-op on some Android
                # versions — fall back to deleting the prop outright, which
                # achieves the same "not present" signal for detection.
                resetprop --delete "$_hl_key" 2>/dev/null
                resetprop -p --delete "$_hl_key" 2>/dev/null
                _hl_actual=$(resetprop "$_hl_key" 2>/dev/null)
                if [ -z "$_hl_actual" ]; then
                    log_customrom "LINEAGE_IDENTITY_CLEANUP" "OK deleted (empty-set fallback): $_hl_key"
                else
                    log_customrom "LINEAGE_IDENTITY_CLEANUP" "WARN failed to override or delete: $_hl_key (current: $_hl_actual)"
                fi
            else
                log_customrom "LINEAGE_IDENTITY_CLEANUP" "WARN failed to override: $_hl_key (current: $_hl_actual)"
            fi
            ;;
    esac
done < "$LINEAGE_IDENTITY_CLEANUP_PROP_FILE"

resetprop -c >/dev/null 2>&1 || true

unset _hl_line _hl_clean _hl_key _hl_value _hl_actual
log_customrom "LINEAGE_IDENTITY_CLEANUP" "Done"
exit 0
