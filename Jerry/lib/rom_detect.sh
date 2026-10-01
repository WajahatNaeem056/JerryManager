#!/system/bin/sh

detect_rom() {
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
        "ro.lunaris.maintainer:Lunaris AOSP" \
        "ro.axion.maintainer:AxionOS"; do
        _rd_key="${_rd_pair%%:*}"
        _rd_disp="${_rd_pair#*:}"
        _rd_val=$(resetprop "$_rd_key" 2>/dev/null)
        if [ -n "$_rd_val" ]; then
            printf '%s' "$_rd_disp"
            return
        fi
    done

    _rd_fp_raw="$(resetprop ro.build.fingerprint 2>/dev/null)|$(resetprop ro.build.description 2>/dev/null)|$(resetprop ro.build.display.id 2>/dev/null)"
    _rd_fp=$(printf '%s' "$_rd_fp_raw" | tr '[:upper:]' '[:lower:]')
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
        "zephyrusos:ZephyrusOS" "axion:AxionOS" "lineage:LineageOS" \
        "lunaris:Lunaris AOSP"; do
        _rd_needle="${_rd_pair%%:*}"
        _rd_disp="${_rd_pair#*:}"
        case "$_rd_fp" in
            *"$_rd_needle"*)
                printf '%s' "$_rd_disp"
                return
                ;;
        esac
    done

    # ro.build.version.oplusrom exists on both ColorOS and OxygenOS builds,
    # so it can't tell them apart alone — persist.sys.oplus.region can:
    # "CN" = ColorOS, anything else = OxygenOS.
    _rd_oplusrom=$(resetprop ro.build.version.oplusrom 2>/dev/null)
    if [ -n "$_rd_oplusrom" ]; then
        _rd_region=$(resetprop persist.sys.oplus.region 2>/dev/null | tr '[:upper:]' '[:lower:]')
        if [ "$_rd_region" = "cn" ]; then
            printf '%s' "ColorOS"
        else
            printf '%s' "OxygenOS"
        fi
        unset _rd_oplusrom _rd_region
        return
    fi
    unset _rd_oplusrom

    _rd_brand=$(resetprop ro.product.brand 2>/dev/null | tr '[:upper:]' '[:lower:]')
    _rd_mfr=$(resetprop ro.product.manufacturer 2>/dev/null | tr '[:upper:]' '[:lower:]')

    case "$_rd_brand$_rd_mfr" in
        *samsung*)
            printf '%s' "One UI"
            return
            ;;
        *xiaomi*|*redmi*|*poco*)
            _rd_hyper=$(resetprop ro.mi.os.version.name 2>/dev/null)
            if [ -n "$_rd_hyper" ]; then
                printf '%s' "HyperOS"
            else
                printf '%s' "MIUI"
            fi
            return
            ;;
        *oneplus*)
            # No ro.build.version.oplusrom above, so fall back to the
            # region prop directly.
            _rd_region2=$(resetprop persist.sys.oplus.region 2>/dev/null | tr '[:upper:]' '[:lower:]')
            if [ "$_rd_region2" = "cn" ]; then
                printf '%s' "ColorOS"
            else
                printf '%s' "OxygenOS"
            fi
            unset _rd_region2
            return
            ;;
        *oppo*|*realme*)
            printf '%s' "ColorOS"
            return
            ;;
        *nothing*)
            printf '%s' "Nothing OS"
            return
            ;;
        *google*)
            printf '%s' "Stock (Pixel/AOSP)"
            return
            ;;
    esac

    _rd_tags=$(resetprop ro.build.tags 2>/dev/null)
    case "$_rd_tags" in
        *test-keys*)
            printf '%s' "AOSP (Unrecognized)"
            return
            ;;
    esac

    if [ -n "$_rd_brand" ]; then
        printf '%s' "Stock ($_rd_brand)"
    else
        printf '%s' "Stock"
    fi
}
