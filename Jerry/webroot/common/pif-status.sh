#!/system/bin/sh
MODDIR="${0%/*}"
MODDIR="${MODDIR%/*}"
MODDIR="${MODDIR%/*}"
. "$MODDIR/lib/common.sh"

PIF_STATUS_PATH="$MODDIR/webroot/json/pif_status.json"

_pif_prop=""
for _candidate in \
    "/data/adb/modules/playintegrityfix/custom.pif.prop" \
    "/data/adb/custom.pif.prop"
do
    if [ -f "$_candidate" ]; then
        _pif_prop="$_candidate"
        break
    fi
done

if [ -n "$_pif_prop" ]; then
    _pif_model=$(awk -F= '/^MODEL=/{print $2}' "$_pif_prop" | head -1)
else
    _pif_model=""
fi
_pif_model=$(_escape_json "$_pif_model")
unset _pif_prop _candidate

cat <<EOF > "$PIF_STATUS_PATH"
{
  "pif_status": "$_pif_model"
}
EOF

cat <<EOF
{
  "pif_status": "$_pif_model"
}
EOF

unset _pif_model
