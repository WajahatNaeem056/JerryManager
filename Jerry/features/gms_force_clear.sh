#!/system/bin/sh
# One-tap action: kill DroidGuard, force-stop the GMS family and clear Play Store data.
# Only com.android.vending is cleared; GMS/GSF are force-stopped, never cleared (Google accounts live there).
# Runs regardless of the boot-time toggles (those only control features/gms.sh).
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/package_list.sh"

log "GMS_CLEAR" "Start"

# Without root (e.g. WebUI opened in a file manager) nothing below can work: report it instead of "Done"
[ "$(id -u 2>/dev/null)" = "0" ] || die "Root access required, open Jerry from your root manager (KernelSU / Magisk / APatch)"

EXTRA_PKGS="com.google.android.gms.persistent com.google.android.gms.unstable com.google.android.rkpdapp com.android.chrome com.google.android.googlequicksearchbox"

_installed=$(pm list packages 2>/dev/null)
[ -n "$_installed" ] || die "Cannot read installed packages (package manager not available)"
_killed=0
_stopped=0
_rc=0

for _pid in $(pgrep -f 'droidguard' 2>/dev/null) $(pgrep -f 'com\.google\.android\.gms\b' 2>/dev/null); do
  kill -9 "$_pid" 2>/dev/null && _killed=$((_killed + 1))
done

for _pkg in $GMS_APPS $EXTRA_PKGS; do
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
