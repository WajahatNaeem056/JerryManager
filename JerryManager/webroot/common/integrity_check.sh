#!/system/bin/sh
MODDIR="${0%/*}"
MODDIR="${MODDIR%/*}"
MODDIR="${MODDIR%/*}"
. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/paths.sh"

OUT="$MODDIR/webroot/json/integrity_verdict.json"
mkdir -p "$(dirname "$OUT")"

_basic=false
_device=false
_strong=false
_source="keybox_estimate"

# ── Real Play Integrity Logic ─────────────────────────────────────────────────
#
# Scenario A: No root / locked bootloader
#   → basic=true, device=true, strong=true  (Google trusts hardware fully)
#
# Scenario B: Root + no keybox (or revoked keybox)
#   → basic=false, device=false, strong=false  (Google kills all 3)
#
# Scenario C: Root + valid keybox (TrickyStore working)
#   → basic=true, device=true, strong=true
#
# Scenario D: Root + keybox but Strong still failing (key attestation mismatch)
#   → basic=true, device=true, strong=false  (2/3 — keybox issue)
#
# ─────────────────────────────────────────────────────────────────────────────

# Method 1: Key Attestation app result (real Play Integrity verdict)
for _prefs in \
  "/data/data/io.github.vvb2060.keyattestation/shared_prefs/key_attestation.xml" \
  "/data/user/0/io.github.vvb2060.keyattestation/shared_prefs/key_attestation.xml"; do
  if [ -f "$_prefs" ]; then
    _b=$(grep -o 'name="basic_integrity"[^/]*/>' "$_prefs" | grep -o 'value="[^"]*"' | grep -o '[^"]*$' | tr -d '"')
    _d=$(grep -o 'name="ctsProfileMatch"[^/]*/>'  "$_prefs" | grep -o 'value="[^"]*"' | grep -o '[^"]*$' | tr -d '"')
    _s=$(grep -o 'name="strong_integrity"[^/]*/>' "$_prefs" | grep -o 'value="[^"]*"' | grep -o '[^"]*$' | tr -d '"')
    if [ -n "$_b" ]; then
      [ "$_b" = "true" ] && _basic=true  || _basic=false
      [ "$_d" = "true" ] && _device=true || _device=false
      [ "$_s" = "true" ] && _strong=true || _strong=false
      _source="keyattestation_app"
      log "INTEGRITY" "keyattestation app: basic=$_basic device=$_device strong=$_strong"
      break
    fi
  fi
done

# Method 2: GMS cache (real verdict stored by Google Play Services)
if [ "$_source" = "keybox_estimate" ]; then
  for _gms in \
    "/data/data/com.google.android.gms/shared_prefs" \
    "/data/user/0/com.google.android.gms/shared_prefs"; do
    _pif="$_gms/PlayIntegrity.xml"
    if [ -f "$_pif" ]; then
      _b=$(grep -o 'MEETS_BASIC_INTEGRITY[^<]*' "$_pif"  | grep -o 'true\|false' | head -1)
      _d=$(grep -o 'MEETS_DEVICE_INTEGRITY[^<]*' "$_pif" | grep -o 'true\|false' | head -1)
      _s=$(grep -o 'MEETS_STRONG_INTEGRITY[^<]*' "$_pif" | grep -o 'true\|false' | head -1)
      if [ -n "$_b" ]; then
        [ "$_b" = "true" ] && _basic=true  || _basic=false
        [ "$_d" = "true" ] && _device=true || _device=false
        [ "$_s" = "true" ] && _strong=true || _strong=false
        _source="gms_cache"
        log "INTEGRITY" "GMS cache: basic=$_basic device=$_device strong=$_strong"
        break
      fi
    fi
  done
fi

# Method 3: Accurate keybox-based estimate (real logic, not just props)
if [ "$_source" = "keybox_estimate" ]; then

  _kb_file="$TARGET_FILE"   # /data/adb/tricky_store/keybox.xml from paths.sh
  _kb_info="$MODDIR/webroot/json/keybox_info.json"

  _kb_installed=false
  _kb_revoked=false

  [ -f "$_kb_file" ] && _kb_installed=true

  if $_kb_installed && [ -f "$_kb_info" ]; then
    _rev=$(grep -o '"revoked":[^,}]*' "$_kb_info" | grep -o 'true\|false')
    [ "$_rev" = "true" ] && _kb_revoked=true
  fi

  # Apply exact real Play Integrity logic:
  if $_kb_installed && ! $_kb_revoked; then
    # Valid keybox = Google trusts the device fully (via TrickyStore attestation)
    _basic=true
    _device=true
    _strong=true
    log "INTEGRITY" "Valid keybox → all 3 pass (estimate)"
  elif $_kb_installed && $_kb_revoked; then
    # Revoked keybox = Google rejects everything
    _basic=false
    _device=false
    _strong=false
    log "INTEGRITY" "Revoked keybox → all 3 fail (estimate)"
  else
    # No keybox at all = basic might pass via PIF props but device/strong fail
    _boot=$(getprop ro.boot.verifiedbootstate 2>/dev/null || echo "orange")
    _build=$(getprop ro.build.type 2>/dev/null || echo "user")
    if [ "$_boot" != "red" ] && [ "$_build" != "eng" ]; then
      # PIF is active, props are spoofed → basic passes
      _basic=true
      _device=false   # Without keybox, device attestation fails
      _strong=false
      log "INTEGRITY" "No keybox, PIF active → basic only (estimate)"
    else
      _basic=false
      _device=false
      _strong=false
      log "INTEGRITY" "No keybox, props bad → all fail (estimate)"
    fi
  fi
fi

_ts=$(date +%s)
cat <<JSON > "$OUT"
{
  "basic": $_basic,
  "device": $_device,
  "strong": $_strong,
  "source": "$_source",
  "timestamp": $_ts
}
JSON

log "INTEGRITY" "Done: basic=$_basic device=$_device strong=$_strong source=$_source"
unset _basic _device _strong _source _ts _b _d _s _prefs _gms _pif
unset _kb_file _kb_info _kb_installed _kb_revoked _rev _boot _build
