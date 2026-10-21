# Built-in Play Integrity Fix helpers (shared by features/pif.sh and features/pif_config.sh)
# Callers must already have sourced lib/common.sh and lib/config_env.sh.

PIF_ROOT="${PIF_ROOT:-/data/adb/modules/JerryManager}"
PIF_PROP="${JERRY_PIF_PROP:-/data/adb/pif.prop}"
PIF_FLAG_KEYS="spoofBuild spoofProps spoofProvider spoofSignature spoofVendingBuild spoofVendingSdk DEBUG"

pif_prop_get() {
  grep -m1 "^$2=" "$1" 2>/dev/null | cut -d= -f2-
}

pif_prop_set() {
  _pps_file="$1" _pps_key="$2" _pps_val="$3"
  [ -f "$_pps_file" ] || : > "$_pps_file"
  if grep -q "^${_pps_key}=" "$_pps_file" 2>/dev/null; then
    sed -i "s|^${_pps_key}=.*|${_pps_key}=${_pps_val}|" "$_pps_file"
  else
    [ -s "$_pps_file" ] && [ -n "$(tail -c1 "$_pps_file" 2>/dev/null)" ] && echo >> "$_pps_file"
    echo "${_pps_key}=${_pps_val}" >> "$_pps_file"
  fi
  unset _pps_file _pps_key _pps_val
}

# Make sure /data/adb/pif.prop exists (seed from the bundled default)
pif_ensure_prop() {
  [ -s "$PIF_PROP" ] && return 0
  [ -f "$PIF_ROOT/pif.prop" ] && cp "$PIF_ROOT/pif.prop" "$PIF_PROP" 2>/dev/null
  [ -s "$PIF_PROP" ]
}

# Copy the user's spoof* / DEBUG choices from the old prop into a freshly fetched one
pif_merge_flags() {
  _pmf_new="$1" _pmf_old="$2"
  [ -f "$_pmf_old" ] || { unset _pmf_new _pmf_old; return 0; }
  for _pmf_k in $PIF_FLAG_KEYS; do
    _pmf_v=$(pif_prop_get "$_pmf_old" "$_pmf_k")
    case "$_pmf_v" in true|false) pif_prop_set "$_pmf_new" "$_pmf_k" "$_pmf_v" ;; esac
  done
  unset _pmf_new _pmf_old _pmf_k _pmf_v
}

# Restart the processes PIF injects into so new settings apply
pif_kill_gms() {
  for _pk_p in com.google.android.gms.unstable com.android.vending; do
    for _pk_pid in $(pidof "$_pk_p" 2>/dev/null || busybox pidof "$_pk_p" 2>/dev/null); do
      kill -9 "$_pk_pid" 2>/dev/null
    done
  done
  unset _pk_p _pk_pid
}
