#!/system/bin/sh
# Live root detection.
#
# Nothing is cached: every detect_root call asks the device what is running now.
#
# Evidence order, the first match wins:
#   1. the shell that runs this script lives inside a root manager's folder
#   2. the manager's environment markers (APATCH, KSU, KSU_VER)
#   3. a root tool that answers on its live interface right now (apd, ksud, magiskd)
#   4. leftover folders under /data/adb (stale evidence, display only)
#
# A binary that merely exists never counts: ksud and apd must answer `module list`.
# Tools missing from PATH (WebUI shells) are tried by their full /data/adb path.
# APatch is checked ahead of KernelSU wherever the evidence is shared, because
# APatch exports KSU=true as well. The variant is then picked inside the family:
#   KernelSU     KernelSU, KernelSU-Next, KernelSU-Next (Spoofed), SukiSU-Ultra,
#                ReSukiSU
#   APatch       APatch, APatch-Next, FolkPatch
#   Magisk       Magisk, Magisk-Kitsune, Magisk-Delta, Magisk-Alpha
# "Spoofed" = Next runs in the kernel/ksud but its normal manager package is not
# installed, so the spoofed manager build (another package name) is in use.
#
# Usage:   . lib/root_detect.sh; detect_root          (prints the root name)
#          . lib/root_detect.sh; detect_root_family   (prints apatch, kernelsu or
#                                                      magisk; live evidence only)
# detect_root returns 1 when its answer is not backed by live evidence (do not cache it).

_RT_ADB="${_RT_ADB:-/data/adb}"
_RT_KSU_SYS="${_RT_KSU_SYS:-/sys/module/kernelsu/parameters}"

_rt_lc() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

_rt_tool() {
    command -v "$1" 2>/dev/null && return 0
    for _rt_cand in "$_RT_ADB/$1" "$_RT_ADB/$2/$1" "$_RT_ADB/$2/bin/$1"; do
        if [ -f "$_rt_cand" ] && [ -x "$_rt_cand" ]; then
            printf '%s' "$_rt_cand"
            return 0
        fi
    done
    return 1
}

_rt_load() {
    _RT_KSUD_LIVE=""
    _RT_APD_LIVE=""
    _RT_KSUD_VER=""
    _RT_APD_VER=""
    _RT_MAGISK_VER=""
    _RT_PKGS=""

    _RT_KSUD=$(_rt_tool ksud ksu)
    _RT_APD=$(_rt_tool apd ap)
    _RT_MAGISK=$(_rt_tool magisk magisk)

    if [ -n "$_RT_KSUD" ] && "$_RT_KSUD" module list >/dev/null 2>&1; then
        _RT_KSUD_LIVE=1
        _RT_KSUD_VER=$(_rt_lc "$("$_RT_KSUD" --version 2>/dev/null || "$_RT_KSUD" version 2>/dev/null)")
    fi
    if [ -n "$_RT_APD" ] && "$_RT_APD" module list >/dev/null 2>&1; then
        _RT_APD_LIVE=1
        _RT_APD_VER=$(_rt_lc "$("$_RT_APD" --version 2>/dev/null || "$_RT_APD" version 2>/dev/null)")
    fi
    if [ -n "$_RT_MAGISK" ]; then
        _RT_MAGISK_VER=$(_rt_lc "$("$_RT_MAGISK" --version 2>/dev/null)")
    fi
    _RT_KSU_PROP=$(_rt_lc "$(getprop ro.kernelsu.version 2>/dev/null)")
}

# Installed packages, loaded on first use (`pm` is slow, so only variant checks pay for it).
_rt_load_pkgs() {
    [ -n "$_RT_PKGS" ] || _RT_PKGS=$(_rt_lc "$(pm list packages 2>/dev/null)")
}

_rt_family_of_exe() {
    case "$1" in
        "$_RT_ADB"/ap/*|"$_RT_ADB"/apd|"$_RT_ADB"/fp/*) printf '%s' "apatch" ;;
        "$_RT_ADB"/ksu/*|"$_RT_ADB"/ksud)               printf '%s' "kernelsu" ;;
        "$_RT_ADB"/magisk|"$_RT_ADB"/magisk/*)          printf '%s' "magisk" ;;
    esac
}

_rt_has_word() {
    case "$1" in
        *"$2"*) return 0 ;;
    esac
    return 1
}

_rt_has_pkg() {
    _rt_load_pkgs
    _rt_has_word "$_RT_PKGS" "$1"
}

_rt_has_prop() {
    [ -n "$(getprop "$1" 2>/dev/null)" ]
}

_rt_magisk_alive() {
    [ -n "$MAGISK_VER_CODE" ] || pidof magiskd >/dev/null 2>&1
}

_rt_family_live() {
    for _rt_pid in $$ $PPID; do
        _rt_fam=$(_rt_family_of_exe "$(readlink "/proc/$_rt_pid/exe" 2>/dev/null)")
        if [ -n "$_rt_fam" ]; then
            printf '%s' "$_rt_fam"
            return 0
        fi
    done

    if [ "$APATCH" = "true" ] || [ -n "$APATCH_VER$APATCH_VER_CODE" ] || [ -n "$_RT_APD_LIVE" ]; then
        printf '%s' "apatch"
    elif [ "$KSU" = "true" ] || [ -n "$KSU_VER$KSU_VER_CODE" ] || [ -n "$_RT_KSUD_LIVE" ]; then
        printf '%s' "kernelsu"
    elif _rt_magisk_alive; then
        printf '%s' "magisk"
    else
        return 1
    fi
}

_rt_family() {
    _rt_family_live && return 0

    if [ -d "$_RT_ADB/ap" ] || [ -d "$_RT_ADB/fp" ]; then
        printf '%s' "apatch"
    elif [ -d "$_RT_ADB/ksu" ]; then
        printf '%s' "kernelsu"
    elif [ -d "$_RT_ADB/magisk" ] || [ -f "$_RT_ADB/magisk.db" ]; then
        printf '%s' "magisk"
    else
        return 1
    fi
}

_rt_apatch_variant() {
    if _rt_has_word "$_RT_APD_VER" "folk" \
        || [ -f "$_RT_ADB/ap/.folkpatch" ] \
        || _rt_has_prop ro.folkpatch.version \
        || _rt_has_pkg "me.yuki.folk" \
        || _rt_has_pkg "folkpatch"; then
        printf '%s' "FolkPatch"
    elif _rt_has_pkg "apatch.next"; then
        printf '%s' "APatch-Next"
    else
        [ -n "$_RT_PKGS" ] || _rt_live=""
        printf '%s' "APatch"
    fi
}

_rt_next_at_runtime() {
    _rt_has_word "$1" "next" \
        || [ -n "$KSU_NEXT" ] \
        || [ -f "$_RT_ADB/ksu/.next" ] \
        || [ -e "$_RT_KSU_SYS/expected_manager_size" ] \
        || _rt_has_prop ro.kernelsu.next.version
}

# The normal KernelSU-Next manager is installed (the spoofed build is not named like it).
_rt_next_manager_installed() {
    _rt_has_pkg "ksunext" || _rt_has_pkg "kernelsu.next"
}

_rt_kernelsu_variant() {
    _rt_who="$_RT_KSUD_VER $_RT_KSU_PROP"

    if _rt_has_word "$_rt_who" "resuki" \
        || [ -f "$_RT_ADB/ksu/.resukisu" ] \
        || _rt_has_prop ro.resukisu.version \
        || _rt_has_pkg "resukisu"; then
        printf '%s' "ReSukiSU"

    elif _rt_has_word "$_rt_who" "suki" \
        || [ -n "$KSU_SUKISU" ] \
        || [ -f "$_RT_ADB/ksu/.dynamic_sign" ] \
        || [ -f "$_RT_ADB/ksu/.sukisu" ] \
        || _rt_has_prop ro.sukisu.version \
        || [ "$(getprop ro.boot.sukisu 2>/dev/null)" = "1" ] \
        || _rt_has_pkg "sukisu"; then
        printf '%s' "SukiSU-Ultra"

    elif _rt_next_at_runtime "$_rt_who"; then
        _rt_load_pkgs
        if [ -z "$_RT_PKGS" ]; then
            _rt_live=""
            printf '%s' "KernelSU-Next"
        elif ! _rt_next_manager_installed; then
            printf '%s' "KernelSU-Next (Spoofed)"
        else
            printf '%s' "KernelSU-Next"
        fi

    elif _rt_next_manager_installed; then
        printf '%s' "KernelSU-Next"

    else
        [ -n "$_RT_PKGS" ] || _rt_live=""
        printf '%s' "KernelSU"
    fi
}

_rt_magisk_variant() {
    case "$_RT_MAGISK_VER" in
        *kitsune*|*husky*) printf '%s' "Magisk-Kitsune" ;;
        *delta*)           printf '%s' "Magisk-Delta" ;;
        *alpha*)           printf '%s' "Magisk-Alpha" ;;
        *)
            [ -n "$_RT_MAGISK_VER" ] || _rt_live=""
            printf '%s' "Magisk"
            ;;
    esac
}

detect_root_family() {
    _rt_load
    _rt_family_live
}

detect_root() {
    _rt_load
    _rt_live=1
    _rt_fam=$(_rt_family_live) || _rt_live=""
    [ -n "$_rt_live" ] || _rt_fam=$(_rt_family)
    case "$_rt_fam" in
        apatch)   _rt_apatch_variant ;;
        kernelsu) _rt_kernelsu_variant ;;
        magisk)   _rt_magisk_variant ;;
        *)        printf '%s' "Unknown"; return 1 ;;
    esac
    [ -n "$_rt_live" ]
}
