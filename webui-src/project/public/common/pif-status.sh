#!/system/bin/sh
MODDIR="${0%/*}"
MODDIR="${MODDIR%/*}"
MODDIR="${MODDIR%/*}"
. "$MODDIR/lib/common.sh"

PIF_STATUS_PATH="$MODDIR/webroot/json/pif_status.json"

# PIF counts as installed when the built-in one shipped (zygisk/ folder, removed at install if skipped)
# or a standalone Play Integrity Fix/Fork module is present and not disabled/removed.
_pif_installed=0
[ -d "$MODDIR/zygisk" ] && _pif_installed=1
_pif_sa="/data/adb/modules/playintegrityfix"
if [ -d "$_pif_sa" ] && [ ! -f "$_pif_sa/disable" ] && [ ! -f "$_pif_sa/remove" ]; then
    _pif_installed=1
fi

_pif_model=""
if [ "$_pif_installed" != "1" ]; then
    _pif_model="Not Installed"
else
    _pif_prop=""
    for _candidate in \
        "/data/adb/pif.prop" \
        "/data/adb/modules/JerryManager/custom.pif.prop" \
        "/data/adb/modules/JerryManager/pif.prop" \
        "/data/adb/custom.pif.prop"
    do
        if [ -f "$_candidate" ]; then
            _pif_prop="$_candidate"
            break
        fi
    done

    if [ -n "$_pif_prop" ]; then
        _pif_model=$(awk -F= '/^MODEL=/{print $2}' "$_pif_prop" | head -1)
    fi
fi
_pif_model=$(_escape_json "$_pif_model")
unset _pif_prop _candidate _pif_sa _pif_installed

cat <<EOT > "$PIF_STATUS_PATH"
{
  "pif_status": "$_pif_model"
}
EOT

cat <<EOT
{
  "pif_status": "$_pif_model"
}
EOT

unset _pif_model
