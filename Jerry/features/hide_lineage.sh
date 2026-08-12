#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"

HIDE_LINEAGE_PROP_FILE="$MODDIR/hide_lineage.prop"
HIDE_LINEAGE_LOG="$JERRYKEY_DIR/hide_lineage.log"

if [ "$(cfg_get "safemode" "0")" = "1" ]; then
    log "HIDE_LINEAGE" "Skipped — Safe Mode is on"
    exit 0
fi

if [ ! -f "$HIDE_LINEAGE_PROP_FILE" ]; then
    log "HIDE_LINEAGE" "No hide_lineage.prop found — nothing to spoof"
    exit 0
fi

ensure_dir "$JERRYKEY_DIR"
echo "[hide_lineage debug log]" > "$HIDE_LINEAGE_LOG"
echo "[INFO] Script started at $(date)" >> "$HIDE_LINEAGE_LOG"

while IFS= read -r _hl_line || [ -n "$_hl_line" ]; do
    _hl_clean=$(echo "$_hl_line" | sed -E 's/^\[(.*)\]=\[(.*)\]$/\1=\2/')

    if [ -z "$_hl_clean" ] || echo "$_hl_clean" | grep -qE '^#'; then
        echo "[SKIP] Empty or comment: $_hl_line" >> "$HIDE_LINEAGE_LOG"
        continue
    fi

    _hl_key=$(echo "$_hl_clean" | cut -d '=' -f1)
    _hl_value=$(echo "$_hl_clean" | cut -d '=' -f2-)

    if [ -z "$_hl_key" ] || [ -z "$_hl_value" ]; then
        echo "[SKIP] Malformed line: $_hl_line" >> "$HIDE_LINEAGE_LOG"
        continue
    fi

    case "$_hl_key" in
        init.svc.*|ro.boottime.*)
            echo "[SKIP] Dynamic prop (not changeable): $_hl_key" >> "$HIDE_LINEAGE_LOG"
            continue
            ;;
        ro.crypto.state)
            echo "[SKIP] Encryption state spoof skipped: $_hl_key" >> "$HIDE_LINEAGE_LOG"
            continue
            ;;
        *)
            resetprop -n "$_hl_key" "$_hl_value" 2>/dev/null
            _hl_actual=$(resetprop "$_hl_key" 2>/dev/null)
            if [ "$_hl_actual" = "$_hl_value" ]; then
                echo "[OK] Overridden: $_hl_key=$_hl_value" >> "$HIDE_LINEAGE_LOG"
            else
                echo "[WARN] Failed to override: $_hl_key. Current value: $_hl_actual" >> "$HIDE_LINEAGE_LOG"
            fi
            ;;
    esac
done < "$HIDE_LINEAGE_PROP_FILE"

resetprop -c >/dev/null 2>&1 || true

echo "[INFO] Script completed at $(date)" >> "$HIDE_LINEAGE_LOG"
unset _hl_line _hl_clean _hl_key _hl_value _hl_actual
log "HIDE_LINEAGE" "Done — see hide_lineage.log for details"
exit 0
