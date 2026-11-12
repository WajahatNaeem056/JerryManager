#!/system/bin/sh
# Live ROM detection.
#
# Nothing is cached: every detect_rom call reads the device as it is right now.
#
# Evidence order, the first match wins:
#   1. a known custom ROM: its own version prop, or its name in the build strings
#   2. an OEM ROM, only when its own marker prop is present
#   3. a neutral label (a ROM name is never guessed from the brand alone)
#
# Cleanup features can delete props from the running system, so every lookup
# falls back to the build.prop files on disk, which those features never touch.
#
# Usage:   . lib/rom_detect.sh; detect_rom      (prints the ROM name)

_RD_NL='
'
_RD_FILES="${_RD_FILES:-/system/build.prop /system_ext/etc/build.prop /product/etc/build.prop}"

# ---- Prop access -------------------------------------------------------------

# Snapshot the running props (one getprop call) and the build.prop files on disk.
# Both snapshots are newline-delimited so a lookup can anchor on the newline.
_rd_load() {
    _RD_LIVE="$_RD_NL$(getprop 2>/dev/null)$_RD_NL"
    _RD_DISK="$_RD_NL"
    for _rd_f in $_RD_FILES; do
        if [ -r "$_rd_f" ]; then
            _RD_DISK="$_RD_DISK$(cat "$_rd_f" 2>/dev/null)$_RD_NL"
        fi
    done
}

# $1 = prop. Value from the running system (getprop dump: "[prop]: [value]").
_rd_live() {
    case "$_RD_LIVE" in
        *"$_RD_NL[$1]: ["*)
            _rd_t="${_RD_LIVE#*"$_RD_NL[$1]: ["}"
            _rd_t="${_rd_t%%"$_RD_NL"*}"
            printf '%s' "${_rd_t%]}"
            ;;
    esac
}

# $1 = prop. Value from the build.prop files ("prop=value").
_rd_disk() {
    case "$_RD_DISK" in
        *"$_RD_NL$1="*)
            _rd_t="${_RD_DISK#*"$_RD_NL$1="}"
            printf '%s' "${_rd_t%%"$_RD_NL"*}"
            ;;
    esac
}

# $1 = prop. Running system first, disk as the fallback.
_rd_get() {
    _rd_v=$(_rd_live "$1")
    [ -n "$_rd_v" ] || _rd_v=$(_rd_disk "$1")
    printf '%s' "$_rd_v"
}

# $1 = prop. Succeeds when the prop has a value.
_rd_has() {
    [ -n "$(_rd_get "$1")" ]
}

# $1 = text. Lowercased.
_rd_lc() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# ---- 1. Known custom ROMs ----------------------------------------------------

# 1a. ROMs that set their own version / maintainer prop.
_rd_named_by_prop() {
    for _rd_pair in \
        "ro.lineage.version:LineageOS" \
        "ro.pixelexperience.version:PixelExperience" \
        "ro.crdroid.version:crDroid" \
        "ro.havoc.version:HavocOS" \
        "ro.arrow.version:ArrowOS" \
        "ro.aosip.version:AOSiP" \
        "ro.aospa.version:AOSPA" \
        "ro.evolution.version:EvolutionX" \
        "ro.derpfest.version:DerpFest" \
        "ro.mokee.version:MoKee" \
        "ro.potato.version:PotatoOpenSource" \
        "ro.statix.version:StatiXOS" \
        "ro.corvus.version:CorvusOS" \
        "ro.pixelos.version:PixelOS" \
        "ro.nameless.version:NamelessROM" \
        "ro.rising.version:RisingOS" \
        "ro.syberia.version:SyberiaOS" \
        "ro.superior.version:SuperiorOS" \
        "ro.yaap.version:YAAP" \
        "ro.lunaris.maintainer:Lunaris AOSP" \
        "ro.axion.maintainer:AxionOS"; do
        if _rd_has "${_rd_pair%%:*}"; then
            printf '%s' "${_rd_pair#*:}"
            return 0
        fi
    done
    return 1
}

# 1b. ROMs found by name in the build strings. The running value and the disk
# value of each prop are both searched.
_rd_named_by_build() {
    _rd_hay=""
    for _rd_k in ro.build.fingerprint ro.build.description ro.build.display.id \
        ro.build.flavor ro.product.name ro.product.system.name \
        ro.system.build.fingerprint; do
        _rd_hay="$_rd_hay|$(_rd_live "$_rd_k")|$(_rd_disk "$_rd_k")"
    done
    _rd_hay=$(_rd_lc "$_rd_hay")

    for _rd_pair in \
        "lineageos:LineageOS" "crdroid:crDroid" "pixelexperience:PixelExperience" \
        "pixelos:PixelOS" "evolutionx:EvolutionX" "arrowos:ArrowOS" \
        "havocos:HavocOS" "resurrectionremix:ResurrectionRemix" "aicp:AICP" \
        "aosip:AOSiP" "aospa:AOSPA" "bootleggers:Bootleggers" \
        "carbonrom:CarbonROM" "coltos:ColtOS" "dotos:DotOS" \
        "dirtyunicorns:DirtyUnicorns" "derpfest:DerpFest" "extendedui:ExtendedUI" \
        "fluidos:FluidOS" "fusionos:FusionOS" "genesisos:GenesisOS" \
        "gzosp:GZOSP" "halogenos:HalogenOS" "ionos:IonOS" \
        "legionos:LegionOS" "liquidremix:LiquidRemix" "lluviaos:LLuviaOS" \
        "mokee:MoKee" "msm-xtended:MSM-Xtended" "nitrogenos:NitrogenOS" \
        "nusantaraos:NusantaraOS" "octavios:OctaviOS" "omnirom:OmniROM" \
        "paranoidandroid:ParanoidAndroid" "posp:POSP" "projectsakura:ProjectSakura" \
        "revengeos:RevengeOS" "risingos:RisingOS" "shapeshiftos:ShapeShiftOS" \
        "slimroms:SlimRoms" "spiceos:SpiceOS" "stagos:StagOS" \
        "superioros:SuperiorOS" "syberiaos:SyberiaOS" "tequilaos:TequilaOS" \
        "theandroidproject:TheAndroidProject" "validusos:ValidusOS" \
        "viperos:ViperOS" "xosp:XOSP" "zenithos:ZenithOS" \
        "zephyrusos:ZephyrusOS" \
        "yaap:YAAP" "infinity:Infinity-X" "matrixx:MatrixX" "mistos:MistOS" \
        "halcyon:Halcyon" "alphadroid:AlphaDroid" "avium:Avium" "bliss:Bliss" \
        "calyx:CalyxOS" "graphene:GrapheneOS" "lmodroid:LMODroid" \
        "lumine:LumineOS" "clover:CloverOS" \
        "axion:AxionOS" "lineage:LineageOS" "lunaris:Lunaris AOSP"; do
        case "$_rd_hay" in
            *"${_rd_pair%%:*}"*)
                printf '%s' "${_rd_pair#*:}"
                return 0
                ;;
        esac
    done
    return 1
}

# ---- 2. OEM ROMs (only with their own marker prop) ---------------------------

# Oplus family: is this the China ROM (ColorOS)? One China marker is enough.
# The markers come from the firmware images and the build id, so a region prop
# changed by the user (for example to PK) cannot hide them.
_rd_oplus_is_cn() {
    case "$(_rd_lc "$(_rd_get ro.oplus.image.my_stock.type)")" in
        domestic*) return 0 ;;
    esac
    case "$(_rd_lc "$(_rd_get ro.vendor.oplus.regionmark)")" in
        cn) return 0 ;;
    esac
    case "$(_rd_lc "$(_rd_get ro.oplus.image.my_region.type)")" in
        cn|cn_*) return 0 ;;
    esac
    case "$(_rd_get ro.build.display.id)" in
        *"(CN"*) return 0 ;;
    esac
    case "$(_rd_lc "$(_rd_get persist.sys.oplus.region)")" in
        cn) return 0 ;;
    esac
    return 1
}

# $1 = oplusrom, for example "V17.0.0". OnePlus ships ColorOS everywhere from
# version 17; version 16 and below is still OxygenOS outside China.
_rd_oplusrom_ge17() {
    _rd_n="${1#[Vv]}"
    _rd_n="${_rd_n%%.*}"
    case "$_rd_n" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$_rd_n" -ge 17 ]
}

# $1 = lowercase brand + manufacturer.
# Prints the OEM ROM, or returns 1 when the OEM marker is missing.
_rd_oem() {
    case "$1" in
        *xiaomi*|*redmi*|*poco*)
            if _rd_has ro.mi.os.version.name; then
                printf '%s' "HyperOS"
            elif _rd_has ro.miui.ui.version.name; then
                printf '%s' "MIUI"
            else
                return 1
            fi
            ;;
        *samsung*)
            if _rd_has ro.build.version.oneui || _rd_has ro.build.version.sem; then
                printf '%s' "One UI"
            else
                return 1
            fi
            ;;
        *oppo*|*realme*)
            if _rd_has ro.build.version.oplusrom || _rd_has ro.build.version.opporom; then
                printf '%s' "ColorOS"
            else
                return 1
            fi
            ;;
        *oneplus*)
            _rd_rom=$(_rd_get ro.build.version.oplusrom)
            if [ -n "$_rd_rom" ]; then
                if _rd_oplus_is_cn || _rd_oplusrom_ge17 "$_rd_rom"; then
                    printf '%s' "ColorOS"
                else
                    printf '%s' "OxygenOS"
                fi
            elif _rd_oplus_is_cn; then
                printf '%s' "ColorOS"
            elif _rd_has ro.oxygen.version; then
                printf '%s' "OxygenOS"
            else
                return 1
            fi
            ;;
        *nothing*)
            case "$(_rd_get ro.build.tags)" in
                *release-keys*) printf '%s' "Nothing OS" ;;
                *) return 1 ;;
            esac
            ;;
        *google*)
            case "$(_rd_get ro.build.tags)" in
                *release-keys*) printf '%s' "Stock (Pixel/AOSP)" ;;
                *) return 1 ;;
            esac
            ;;
        *)
            return 1
            ;;
    esac
}

# ---- 3. Neutral label --------------------------------------------------------

# $1 = lowercase brand + manufacturer.
_rd_fallback() {
    case "$(_rd_get ro.build.tags)" in
        *test-keys*|*dev-keys*)
            printf '%s' "AOSP (Unrecognized)"
            return 0
            ;;
    esac
    case "$1" in
        *oneplus*|*oppo*|*realme*|*xiaomi*|*redmi*|*poco*|*samsung*|*google*|*nothing*)
            # An OEM phone without its OEM marker: not the OEM ROM, name unknown.
            printf '%s' "Custom ROM (Unrecognized)"
            return 0
            ;;
    esac
    _rd_b=$(_rd_lc "$(_rd_get ro.product.brand)")
    if [ -n "$_rd_b" ]; then
        printf '%s' "Stock ($_rd_b)"
    else
        printf '%s' "Stock"
    fi
}

# ---- Entry point -------------------------------------------------------------

detect_rom() {
    _rd_load
    _rd_named_by_prop && return 0
    _rd_named_by_build && return 0
    _rd_ident=$(_rd_lc "$(_rd_get ro.product.brand)$(_rd_get ro.product.manufacturer)")
    _rd_oem "$_rd_ident" && return 0
    _rd_fallback "$_rd_ident"
}
