#!/system/bin/sh
# Writes only the currently active PIF (Play Integrity Fix) spoofed device
# model to its own small JSON file. Deliberately separate from
# device-info.sh, which also does root-type detection (multiple `pm list
# packages` and `getprop` calls) — too heavy to rerun on a fast poll
# interval just to catch a PIF change. This script does one cheap file read.
#
# Checks both candidate paths Integrity Box's own PlayIntegrityFork page
# checks (module dir first, then the legacy /data/adb/ fallback), since all
# three PIF variants JerryManager's pif.sh handles (INJECT, Fork, original)
# converge on the same custom.pif.prop format.
MODDIR="${0%/*}"
MODDIR="${MODDIR%/*}"
MODDIR="${MODDIR%/*}"
. "$MODDIR/lib/common.sh"

PIF_STATUS_PATH="$MODDIR/webroot/json/pif_status.json"
# Note: the WebUI polls this script's stdout directly via the bridge
# (runScript), not this file — the file below is written only as an
# on-device debug artifact (e.g. `cat` it over adb), not read by anything
# in this module currently.

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

# Also print to stdout — this is what the WebUI's bridge poll actually reads
# (runScript captures stdout/exit-code via the KSU/MMRL exec bridge, not
# files). The file write above is a secondary on-device debug copy only.
cat <<EOF
{
  "pif_status": "$_pif_model"
}
EOF

unset _pif_model
