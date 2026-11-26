#!/system/bin/sh
# One-tap action: kill DroidGuard, force-stop the GMS family and clear Play Store data.
# Standalone: no lib/ or toggle dependency. Only com.android.vending is cleared;
# GMS/GSF are force-stopped, never cleared (Google accounts live there).
LOG_FILE="/data/adb/JerryManager/boot.log"
log() {
  _l="$(date '+%Y-%m-%d %H:%M:%S') [$1] $2"
  echo "$_l"
  mkdir -p "${LOG_FILE%/*}" 2>/dev/null
  echo "$_l" >> "$LOG_FILE" 2>/dev/null
}
die() { log "ERROR" "$1"; exit 1; }

log "GMS_CLEAR" "Start"

[ "$(id -u 2>/dev/null)" = "0" ] || die "Root access required, open Jerry from your root manager (KernelSU / Magisk / APatch)"

GMS_PKGS="com.android.vending com.google.android.gsf com.google.android.gms com.google.android.contactkeys com.google.android.ims com.google.android.safetycore com.google.android.apps.walletnfcrel com.google.android.apps.nbu.paisa.user com.google.android.gms.persistent com.google.android.gms.unstable com.google.android.rkpdapp com.android.chrome com.google.android.googlequicksearchbox"

_installed=$(pm list packages 2>/dev/null)
[ -n "$_installed" ] || die "Cannot read installed packages (package manager not available)"
_killed=0
_stopped=0
_rc=0

# No \b: toybox pgrep regex does not support it (bad regex, silently matched nothing)
for _pid in $(pgrep -f 'droidguard' 2>/dev/null) $(pgrep -f 'com\.google\.android\.gms' 2>/dev/null); do
  kill -9 "$_pid" 2>/dev/null && _killed=$((_killed + 1))
done

for _pkg in $GMS_PKGS; do
  echo "$_installed" | grep -Fq "package:$_pkg" || continue
  if am force-stop "$_pkg" >/dev/null 2>&1; then
    _stopped=$((_stopped + 1))
  else
    log "GMS_CLEAR" "Warning: Failed to force-stop $_pkg"
  fi
done

if echo "$_installed" | grep -Fq "package:com.android.vending"; then
  if pm clear com.android.vending >/dev/null 2>&1; then
    log "GMS_CLEAR" "Play Store data cleared"
  else
    log "GMS_CLEAR" "Error: Failed to clear Play Store data"
    _rc=1
  fi
fi

log "GMS_CLEAR" "Killed $_killed process(es), force-stopped $_stopped package(s)"
log "GMS_CLEAR" "Finish (rc=$_rc)"
exit "$_rc"
