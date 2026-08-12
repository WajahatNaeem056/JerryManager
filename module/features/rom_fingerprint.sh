#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/config_env.sh"

[ "$(cfg_get toggle_rom_fingerprint 1)" = "0" ] && exit 0

log "ROM_FP" "Start"
_cleaned=0

# ── Strip custom-ROM identifying props (lineage/crDroid/PixelOS/etc.) ────────
for _rf_pattern in \
  lineage crDroid PixelExperience PixelOS EvolutionX ArrowOS \
  HavocOS ResurrectionRemix AICP AOSiP AOSPA Bootleggers \
  CarbonROM ColtOS DotOS DirtyUnicorns DerpFest ExtendedUI \
  FluidOS FusionOS GenesisOS GZOSP HalogenOS IonOS \
  LegionOS LiquidRemix LLuviaOS Mokee MSM-Xtended \
  NitrogenOS NusantaraOS OctaviOS OmniROM ParanoidAndroid \
  POSP ProjectSakura RevengeOS RisingOS ShapeShiftOS \
  SlimRoms SpiceOS StagOS SuperiorOS SyberiaOS \
  TequilaOS TheAndroidProject titanium ValidusOS \
  ViperOS XOSP ZenithOS ZephyrusOS crDroidProject AxionOS; do
  _rf_props=$(resetprop 2>/dev/null | grep -i "$_rf_pattern" | cut -d'[' -f2 | cut -d']' -f1 || true)
  for _rf_prop in $_rf_props; do
    [ -z "$_rf_prop" ] && continue
    resetprop --delete "$_rf_prop" 2>/dev/null && _cleaned=$((_cleaned + 1))
  done
done
unset _rf_pattern _rf_props _rf_prop

# ── Strip aosp_/lineage_ prefix from key build props ─────────────────────────
for _rf_build_prop in ro.build.fingerprint ro.build.display.id ro.build.description ro.build.version.incremental ro.product.vendor.name; do
  _rf_val=$(resetprop "$_rf_build_prop" 2>/dev/null || echo "")
  [ -z "$_rf_val" ] && continue
  _rf_new_val="$_rf_val"
  for _rf_pref in aosp_ lineage_; do
    case "$_rf_new_val" in
      "$_rf_pref"*) _rf_new_val=${_rf_new_val#"$_rf_pref"} ;;
    esac
  done
  if [ "$_rf_new_val" != "$_rf_val" ]; then
    resetprop -n "$_rf_build_prop" "$_rf_new_val" 2>/dev/null && _cleaned=$((_cleaned + 1))
  fi
done
unset _rf_build_prop _rf_val _rf_new_val _rf_pref

# ── LineageOS camera packagelist scrub ────────────────────────────────────────
_rf_cam=$(resetprop vendor.camera.aux.packagelist 2>/dev/null || echo "")
case "$_rf_cam" in
  *org.lineageos*)
    resetprop -n vendor.camera.aux.packagelist "com.android.camera" 2>/dev/null && _cleaned=$((_cleaned + 1))
    log "ROM_FP" "Scrubbed vendor.camera.aux.packagelist"
    ;;
esac
unset _rf_cam

_rf_cam_priv=$(resetprop persist.vendor.camera.privapp.list 2>/dev/null || echo "")
case "$_rf_cam_priv" in
  *org.lineageos*)
    resetprop -n persist.vendor.camera.privapp.list "com.android.camera" 2>/dev/null && _cleaned=$((_cleaned + 1))
    log "ROM_FP" "Scrubbed persist.vendor.camera.privapp.list"
    ;;
esac
unset _rf_cam_priv

# ── Stop vendor.lineage_health service if present ─────────────────────────────
_rf_health=$(resetprop init.svc.vendor.lineage_health 2>/dev/null || echo "")
if [ -n "$_rf_health" ]; then
  setprop ctl.stop vendor.lineage_health 2>/dev/null
  resetprop -d init.svc.vendor.lineage_health 2>/dev/null
  _cleaned=$((_cleaned + 1))
  log "ROM_FP" "Stopped vendor.lineage_health"
fi
unset _rf_health

if [ "$_cleaned" -gt 0 ]; then
  log "ROM_FP" "Cleaned $_cleaned ROM-specific fingerprint(s)"
else
  log "ROM_FP" "No ROM fingerprints to clean"
fi
unset _cleaned

log "ROM_FP" "Finish"
exit 0
