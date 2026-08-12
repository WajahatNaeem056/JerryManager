#!/system/bin/sh
# ── ROM identity detection ────────────────────────────────────────────────────
# Returns the actual ROM name (e.g. "PixelOS", "LineageOS", "One UI",
# "ColorOS") instead of a generic Stock/Custom label.
#
# IMPORTANT: This must be sourced and run BEFORE features/rom_fingerprint.sh,
# since that script deletes/rewrites the exact props this relies on. Callers
# (service.sh / boot-completed.sh) cache the result via cfg_set so it survives
# even after the props are stripped later in the same boot.
#
# Coverage note: custom-ROM detection below is reliable (each ROM ships its
# own version prop). Stock OEM-skin detection is best-effort — there is no
# universal "ROM name" prop across OEMs, marketing names change over time
# (MIUI -> HyperOS, OxygenOS merging into ColorOS), and unlisted OEMs fall
# back to a generic "Stock (<brand>)" rather than a guessed marketing name.
#
# "AOSP (Unrecognized)" fallback (step 4) is a test-keys heuristic — it is
# NOT reliable proof of a custom ROM. Some budget/OEM stock builds ship with
# test-keys due to sloppy signing pipelines, so this can false-positive on
# genuine stock devices. Accepted trade-off, not a guarantee.

detect_rom() {
    # 1. Dedicated custom-ROM version/maintainer props → mapped to real display name
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

    # 2. Fingerprint / description pattern match — catches ROMs that skip a
    #    dedicated version prop but still leave their name in the build strings.
    #    Matched case-insensitively: build strings don't reliably match a ROM's
    #    "marketing" casing (e.g. AxionOS ships build IDs as "axion-2.2.1-...",
    #    not "AxionOS-2.2.1-...").
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

    # 3. Stock OEM skins — best-effort, only for brands with a well-documented prop
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
            printf '%s' "OxygenOS"
            return
            ;;
        *oppo*|*realme*)
            printf '%s' "ColorOS"
            return
            ;;
        *vivo*|*iqoo*)
            printf '%s' "OriginOS/FuntouchOS"
            return
            ;;
        *google*)
            printf '%s' "Stock (Pixel/AOSP)"
            return
            ;;
    esac

    # 4. Nothing named matched. test-keys heuristic: NOT proof of a custom ROM —
    #    some stock budget/OEM builds also ship test-keys due to sloppy signing.
    #    Only applied here because no known OEM brand matched in step 3 either.
    _rd_tags=$(resetprop ro.build.tags 2>/dev/null)
    case "$_rd_tags" in
        *test-keys*)
            printf '%s' "AOSP (Unrecognized)"
            return
            ;;
    esac

    # 5. Truly nothing to go on — generic fallback, name the brand if known
    if [ -n "$_rd_brand" ]; then
        printf '%s' "Stock ($_rd_brand)"
    else
        printf '%s' "Stock"
    fi
}
