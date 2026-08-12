MODDIR=${0%/*}
MODDIR=${MODDIR%/features}
. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/paths.sh"
. "$MODDIR/lib/config_env.sh"

_out="${1:-$(dirname "$JERRYKEY_CONFIG_DIR")/JerryManager.log}"
mkdir -p "$(dirname "$_out")" 2>/dev/null

_version=$(grep '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d'=' -f2)
_version_code=$(grep '^versionCode=' "$MODDIR/module.prop" 2>/dev/null | cut -d'=' -f2)
_now=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")

# Every log tag any script in this module writes with log() (lib/common.sh).
# Kept as one explicit list (rather than discovered at runtime) so section
# order is stable across exports and new tags are a deliberate addition here.
_LOG_TAGS="BOOT SERVICE ACTION ADB AUTO_TARGET BANKING BOOT_HASH \
CLEANUP CUSTOM_KEYBOX GMS KEYBOX KEYBOX_INFO KILL_ALL LSPOSED PIF \
ROM_FP SECURITY_PATCH SUSPICIOUS TARGET TWRP WIDEVINE ZYGISK_NEXT"

{
  echo "JerryManager — Full Report (device info, keybox, security patch, app targeting, toggles, properties, per-feature logs)"
  echo "version=$_version ($_version_code) | exported=$_now"
  echo ""

  # ── Device info (reuses device-info.sh's own JSON — no duplicate detection
  # logic here, so this can never drift out of sync with what the WebUI shows) ──
  echo "=== DEVICE INFO ==="
  _info_json="$MODDIR/webroot/json/info.json"
  if [ -f "$_info_json" ]; then
    for _field in android root rom version; do
      _val=$(grep -o "\"$_field\": *\"[^\"]*\"" "$_info_json" 2>/dev/null | sed 's/.*: *"//;s/"$//')
      [ -n "$_val" ] && echo "${_field}=${_val}"
    done
    unset _field _val
  else
    echo "(not available — run the WebUI once to generate webroot/json/info.json)"
  fi

  # ── Pif status — same detection logic as update_description(), so this
  # can never drift out of sync with what the module description shows ──────
  _pif_dir="/data/adb/modules/playintegrityfix"
  if [ -d "$_pif_dir" ]; then
    _pif="unknown"
    for _pif_cfg in "$_pif_dir/custom.pif.prop" "$_pif_dir/pif.json" "$_pif_dir/pif.prop"; do
      if [ -f "$_pif_cfg" ]; then
        _pif_model=$(grep -m1 '^MODEL=' "$_pif_cfg" 2>/dev/null | cut -d= -f2-)
        [ -z "$_pif_model" ] && _pif_model=$(grep -m1 '"MODEL"' "$_pif_cfg" 2>/dev/null | sed -n 's/.*"MODEL"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        if [ -n "$_pif_model" ]; then
          _pif="$_pif_model"
          break
        fi
      fi
    done
    echo "pif=$_pif"
    unset _pif_cfg _pif_model
  else
    echo "pif=not installed"
  fi
  unset _pif_dir _pif

  if [ -f "$_info_json" ]; then
    _kernel_val=$(grep -o '"kernel": *"[^"]*"' "$_info_json" 2>/dev/null | sed 's/.*: *"//;s/"$//')
    [ -n "$_kernel_val" ] && echo "kernel=$_kernel_val"
    unset _kernel_val
  fi
  unset _info_json
  echo ""

  # ── Keybox status ──────────────────────────────────────────────────────────
  echo "=== KEYBOX ==="
  if [ -f "$TARGET_FILE" ]; then
    _kb_marker=$(grep -oE 'jerryroot:[0-9]+|JERRY-KEYBOX:[0-9]+' "$TARGET_FILE" 2>/dev/null | head -1)
    _kb_device=$(grep -oE 'DeviceID="[^"]*"' "$TARGET_FILE" 2>/dev/null | head -1 | sed 's/DeviceID="//;s/"$//')
    echo "installed=true"
    [ -n "$_kb_marker" ] && echo "installed_by_jerry=true ($_kb_marker)" || echo "installed_by_jerry=unknown (no jerryroot marker found)"
    [ -n "$_kb_device" ] && echo "device_id=$_kb_device"
    unset _kb_marker _kb_device
  else
    echo "installed=false"
  fi
  [ -f "$BACKUP_FILE" ] && echo "backup_present=true" || echo "backup_present=false"
  echo ""

  # ── Security patch ─────────────────────────────────────────────────────────
  echo "=== SECURITY PATCH ==="
  if [ -f "$SECURITY_PATCH_FILE" ]; then
    cat "$SECURITY_PATCH_FILE" 2>/dev/null
  else
    echo "(not set)"
  fi
  echo ""

  # ── App Targeting summary — count only, never the full package list, to
  # keep this export a reasonable size on devices with hundreds of apps ──────
  echo "=== APP TARGETING ==="
  if [ -f "$TARGET_TXT" ]; then
    _tt_count=$(grep -c . "$TARGET_TXT" 2>/dev/null || echo 0)
    echo "target.txt entries=$_tt_count"
    unset _tt_count
  else
    echo "target.txt not found"
  fi
  echo ""

  # ── Toggles (unchanged from the previous export format) ─────────────────────
  echo "# --- Toggles (live config dir: $JERRYKEY_CONFIG_DIR) ---"
  if [ -d "$JERRYKEY_CONFIG_DIR" ]; then
    for _f in "$JERRYKEY_CONFIG_DIR"/*.val; do
      [ -e "$_f" ] || continue
      _name=$(basename "$_f" .val)
      _val=$(cat "$_f" 2>/dev/null)
      echo "${_name}=${_val}"
      unset _name _val
    done | sort
  else
    echo "(config dir not found — no toggle has ever been written)"
  fi
  echo ""

  # ── Key runtime properties (unchanged from the previous export format) ──────
  echo "# --- Key runtime properties (as currently visible via getprop) ---"
  for _p in \
    sys.oem_unlock_allowed \
    ro.oem_unlock_supported \
    ro.warranty_bit \
    ro.boot.warranty_bit \
    ro.boot.verifiedbootstate \
    vendor.boot.verifiedbootstate \
    ro.boot.flash.locked \
    ro.debuggable \
    ro.build.tags \
    ro.vendor.warranty_bit \
    ro.vendor.boot.warranty_bit \
    ro.secureboot.lockstate \
    ro.boot.vbmeta.device_state \
    vendor.boot.vbmeta.device_state \
    ro.boot.veritymode \
  ; do
    echo "${_p}=$(getprop "$_p" 2>/dev/null)"
  done
  unset _f _p
  echo ""

  # ── boot.log split into one section per tag, in the fixed order above.
  # Everything logged under an unrecognized tag (e.g. a future feature this
  # list hasn't been updated for) is dumped last under "OTHER", so an export
  # never silently drops log lines. ──────────────────────────────────────────
  echo "# --- boot.log, split by feature ---"
  if [ -f "$JERRYKEY_LOG_FILE" ]; then
    _seen_tags=" "
    for _tag in $_LOG_TAGS; do
      _seen_tags="$_seen_tags$_tag "
      echo ""
      echo "=== $_tag.log ==="
      _section_lines=$(grep "\[$_tag\]" "$JERRYKEY_LOG_FILE" 2>/dev/null | sed "s/^.*\[$_tag\] //")
      if [ -n "$_section_lines" ]; then
        echo "$_section_lines"
      else
        echo "(no entries)"
      fi
      unset _section_lines
    done
    echo ""
    echo "=== OTHER.log ==="
    _other_found=0
    while IFS= read -r _line; do
      _line_tag=$(echo "$_line" | grep -oE '\[[A-Za-z_]+\]' | head -1 | tr -d '[]')
      [ -z "$_line_tag" ] && continue
      case " $_seen_tags" in
        *" $_line_tag "*) continue ;;
      esac
      echo "$_line"
      _other_found=1
    done < "$JERRYKEY_LOG_FILE"
    [ "$_other_found" = "0" ] && echo "(no entries)"
    unset _seen_tags _tag _line _line_tag _other_found
  else
    echo "(boot.log not found — module may not have completed a boot cycle yet)"
  fi
} > "$_out" 2>/dev/null

if [ -s "$_out" ]; then
  log "EXPORT" "Full log exported to $_out"
  echo "$_out"
  exit 0
else
  log "EXPORT" "Error: failed to write $_out"
  exit 1
fi
