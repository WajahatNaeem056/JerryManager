#!/system/bin/sh
# Kernel build-time sync (ro.build.date / date.utc)
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"

if [ "$(cfg_get "safemode" "0")" = "1" ]; then
    log "BUILD_SANITIZE" "Skipped — Safe Mode is on"
    exit 0
fi

_bs_time=$(cfg_get toggle_kernel_buildtime 0)
[ "$_bs_time" = "0" ] && exit 0

log "BUILD_SANITIZE" "Start"

# 1) Kernel build time -> ro.build.date / ro.build.date.utc
if [ "$_bs_time" != "0" ]; then
    _bs_kv=$(uname -v 2>/dev/null)
    # Expect e.g. "#1 SMP PREEMPT Mon Mar 10 12:34:56 UTC 2025"
    _bs_stamp=$(printf '%s' "$_bs_kv" | sed -nE 's/.*([A-Z][a-z]{2} [A-Z][a-z]{2} +[0-9]{1,2} [0-9]{2}:[0-9]{2}:[0-9]{2} [A-Za-z0-9+-]+ [0-9]{4}).*/\1/p')
    if [ -z "$_bs_stamp" ]; then
        log "BUILD_SANITIZE" "Warning: could not parse kernel build time from uname -v"
    else
        _bs_mon=$(echo "$_bs_stamp" | awk '{print $2}')
        _bs_day=$(echo "$_bs_stamp" | awk '{print $3}')
        _bs_hms=$(echo "$_bs_stamp" | awk '{print $4}')
        _bs_year=$(echo "$_bs_stamp" | awk '{print $NF}')
        case "$_bs_mon" in
            Jan) _bs_m=01;; Feb) _bs_m=02;; Mar) _bs_m=03;; Apr) _bs_m=04;;
            May) _bs_m=05;; Jun) _bs_m=06;; Jul) _bs_m=07;; Aug) _bs_m=08;;
            Sep) _bs_m=09;; Oct) _bs_m=10;; Nov) _bs_m=11;; Dec) _bs_m=12;;
            *) _bs_m="" ;;
        esac
        _bs_day=$(printf '%02d' "$_bs_day" 2>/dev/null)
        _bs_epoch=""
        [ -n "$_bs_m" ] && _bs_epoch=$(date -u -d "$_bs_year-$_bs_m-$_bs_day $_bs_hms" +%s 2>/dev/null)
        if [ -n "$_bs_epoch" ] && [ "$_bs_epoch" -gt 0 ] 2>/dev/null; then
            resetprop -n ro.build.date "$_bs_stamp" 2>/dev/null
            resetprop -n ro.build.date.utc "$_bs_epoch" 2>/dev/null
            log "BUILD_SANITIZE" "Build time synced: $_bs_stamp (epoch $_bs_epoch)"
        else
            log "BUILD_SANITIZE" "Warning: invalid epoch from kernel build time — skipped"
        fi
    fi
    unset _bs_kv _bs_stamp _bs_mon _bs_day _bs_hms _bs_year _bs_m _bs_epoch
fi

log "BUILD_SANITIZE" "Finish"
exit 0
