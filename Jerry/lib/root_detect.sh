#!/system/bin/sh
# Live root detection.
#
# Nothing is cached: every detect_root call asks the device what is running now.
#
# Evidence order, the first match wins:
#   1. the shell that runs this script lives inside a root manager's folder
#   2. a root binary or daemon that answers right now (ksud, apd, magiskd)
#   3. leftover folders under /data/adb (stale evidence, last resort)
#
# APatch is checked ahead of KernelSU wherever the evidence is shared, because
# APatch exports KSU=true as well. The variant is then picked inside the family:
#   KernelSU     KernelSU, KernelSU-Next, KernelSU-Next (Spoofed), SukiSU-Ultra,
#                ReSukiSU
#   APatch       APatch, FolkPatch
#   Magisk       Magisk, Magisk-Kitsune, Magisk-Delta, Magisk-Alpha
# "Spoofed" = Next runs in the kernel/ksud but its normal manager package is not
# installed, so the spoofed manager build (another package name) is in use.
#
# Usage:   . lib/root_detect.sh; detect_root      (prints the root name)

_RT_ADB="${_RT_ADB:-/data/adb}"

# ---- Snapshots ---------------------------------------------------------------

# $1 = text. Lowercased.
_rt_lc() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Collect what the root tools report about themselves, once per detect_root call.
_rt_load() {
    _RT_KSUD_VER=$(_rt_lc "$(ksud --version 2>/dev/null || ksud version 2>/dev/null)")
    _RT_APD_VER=$(_rt_lc "$(apd --version 2>/dev/null || apd version 2>/dev/null)")
    _RT_MAGISK_VER=$(_rt_lc "$(magisk --version 2>/dev/null)")
    _RT_KSU_PROP=$(_rt_lc "$(getprop ro.kernelsu.version 2>/dev/null)")
    _RT_PKGS=""
}

# Installed packages, loaded on first use (`pm` is slow, so only variant checks pay for it).
_rt_load_pkgs() {
    [ -n "$_RT_PKGS" ] || _RT_PKGS=$(_rt_lc "$(pm list packages 2>/dev/null)")
}

# ---- Small checks ------------------------------------------------------------

# $1 = path of a process executable. Prints the root family it belongs to.
_rt_family_of_exe() {
    case "$1" in
        "$_RT_ADB"/ap/*|"$_RT_ADB"/apd|"$_RT_ADB"/fp/*) printf '%s' "apatch" ;;
        "$_RT_ADB"/ksu/*|"$_RT_ADB"/ksud)               printf '%s' "kernelsu" ;;
        "$_RT_ADB"/magisk|"$_RT_ADB"/magisk/*)          printf '%s' "magisk" ;;
    esac
}

# $1 = text, $2 = word. Succeeds when the text contains the word.
_rt_has_word() {
    case "$1" in
        *"$2"*) return 0 ;;
    esac
    return 1
}

# $1 = word. Succeeds when an installed package name contains it.
_rt_has_pkg() {
    _rt_load_pkgs
    _rt_has_word "$_RT_PKGS" "$1"
}

# $1 = prop. Succeeds when the prop has a value.
_rt_has_prop() {
    [ -n "$(getprop "$1" 2>/dev/null)" ]
}

_rt_ksud_answers() { [ -n "$_RT_KSUD_VER" ] || [ -x "$_RT_ADB/ksud" ]; }
_rt_apd_present()  { [ -n "$_RT_APD_VER" ] || [ -x "$_RT_ADB/apd" ]; }
_rt_magisk_alive() {
    [ -n "$MAGISK_VER_CODE" ] || [ -n "$_RT_MAGISK_VER" ] || pidof magiskd >/dev/null 2>&1
}

# ---- 1-3. Which root family is running ----------------------------------------

# Prints apatch, kernelsu or magisk. Returns 1 when nothing is found.
_rt_family() {
    for _rt_pid in $$ $PPID; do
        _rt_fam=$(_rt_family_of_exe "$(readlink "/proc/$_rt_pid/exe" 2>/dev/null)")
        if [ -n "$_rt_fam" ]; then
            printf '%s' "$_rt_fam"
            return 0
        fi
    done

    if [ "$APATCH" = "true" ]; then
        printf '%s' "apatch"
    elif _rt_ksud_answers; then
        printf '%s' "kernelsu"
    elif _rt_apd_present; then
        printf '%s' "apatch"
    elif [ "$KSU" = "true" ]; then
        printf '%s' "kernelsu"
    elif _rt_magisk_alive; then
        printf '%s' "magisk"
    elif [ -d "$_RT_ADB/ap" ] || [ -d "$_RT_ADB/fp" ]; then
        printf '%s' "apatch"
    elif [ -d "$_RT_ADB/ksu" ]; then
        printf '%s' "kernelsu"
    elif [ -d "$_RT_ADB/magisk" ] || [ -f "$_RT_ADB/magisk.db" ]; then
        printf '%s' "magisk"
    else
        return 1
    fi
}

# ---- Variants ----------------------------------------------------------------

_rt_apatch_variant() {
    if _rt_has_word "$_RT_APD_VER" "folk" \
        || [ -f "$_RT_ADB/ap/.folkpatch" ] \
        || _rt_has_prop ro.folkpatch.version \
        || _rt_has_pkg "me.yuki.folk" \
        || _rt_has_pkg "folkpatch"; then
        printf '%s' "FolkPatch"
    else
        printf '%s' "APatch"
    fi
}

# $1 = "<ksud version> <kernelsu prop>". KernelSU-Next shows itself in ksud and
# the script environment, not only through its manager app.
_rt_next_at_runtime() {
    _rt_has_word "$1" "next" \
        || [ -n "$KSU_NEXT" ] \
        || [ -f "$_RT_ADB/ksu/.next" ] \
        || _rt_has_prop ro.kernelsu.next.version
}

# The normal KernelSU-Next manager is installed (the spoofed build is not named like it).
_rt_next_manager_installed() {
    _rt_has_pkg "ksunext" || _rt_has_pkg "kernelsu.next"
}

_rt_kernelsu_variant() {
    _rt_who="$_RT_KSUD_VER $_RT_KSU_PROP"
    _rt_major=$(printf '%s' "$_RT_KSUD_VER" | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)

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
        if [ -n "$_RT_PKGS" ] && ! _rt_next_manager_installed; then
            printf '%s' "KernelSU-Next (Spoofed)"
        else
            printf '%s' "KernelSU-Next"
        fi

    elif _rt_next_manager_installed; then
        printf '%s' "KernelSU-Next"

    elif [ "${_rt_major:-0}" -ge 4 ] 2>/dev/null; then
        # Last resort: a ksud 4.x with no other marker is taken as SukiSU-Ultra
        printf '%s' "SukiSU-Ultra"

    else
        printf '%s' "KernelSU"
    fi
}

_rt_magisk_variant() {
    case "$_RT_MAGISK_VER" in
        *kitsune*|*husky*) printf '%s' "Magisk-Kitsune" ;;
        *delta*)           printf '%s' "Magisk-Delta" ;;
        *alpha*)           printf '%s' "Magisk-Alpha" ;;
        *)                 printf '%s' "Magisk" ;;
    esac
}

# ---- Entry point -------------------------------------------------------------

detect_root() {
    _rt_load
    case "$(_rt_family)" in
        apatch)   _rt_apatch_variant ;;
        kernelsu) _rt_kernelsu_variant ;;
        magisk)   _rt_magisk_variant ;;
        *)        printf '%s' "Unknown" ;;
    esac
}
