#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/paths.sh"
. "$MODDIR/../lib/config_env.sh"
. "$MODDIR/../lib/package_list.sh"
. "$MODDIR/../lib/urls.sh"

log "BANKING" "=== Banking Mode Start ==="

# ═══════════════════════════════════════════════════════════════════════════════
# APPROACH: App list se nahi — root detection ke EVERY SOURCE ko band karo.
#
# Root detect hone ke tamam raste:
#  [A] System props    — ro.debuggable, ro.build.type, ro.build.tags
#  [B] Filesystem      — /su, /sbin/su, /data/local/tmp/frida, etc.
#  [C] Running procs   — frida-server, su daemon (/proc/maps leak)
#  [D] Installed pkgs  — Magisk app, root checker apps
#  [E] ADB/USB state   — Settings.Global.adb_enabled
#  [F] Dev Options     — Settings.Global.development_settings_enabled
#  [G] SELinux state   — permissive = root likely
#  [H] Play Integrity  — DroidGuard cached bad result
#  [I] Zygisk traces   — /proc/maps mein zygisk linker dikhta hai
#  [J] LSPosed traces  — base.odex, lspd socket, odex files
#  [K] Logcat leaks    — tombstones, dropbox crash logs
#
# Yeh script har ek [A-K] route ko band karti hai.
# Koi banking app hardcode karne ki zaroorat nahi — worldwide works.
# ═══════════════════════════════════════════════════════════════════════════════

_installed_pkgs=$(pm list packages 2>/dev/null || echo "")
_is_installed() { echo "$_installed_pkgs" | grep -q "package:$1"; }

_full_wipe() {
    _fw_p="$1"
    _is_installed "$_fw_p" || return 0
    am force-stop "$_fw_p"                                >/dev/null 2>&1 || true
    pm clear      "$_fw_p"                                >/dev/null 2>&1 || true
    rm -rf "/storage/emulated/0/Android/data/$_fw_p"      2>/dev/null || true
    rm -rf "/storage/emulated/0/Android/obb/$_fw_p"       2>/dev/null || true
    rm -rf "/storage/emulated/0/Android/media/$_fw_p"     2>/dev/null || true
    unset _fw_p
}

# ─────────────────────────────────────────────────────────────────────────────
# [H] STEP 1 — GMS stack kill + Play Integrity / DroidGuard cache wipe
# Reason: cached bad integrity result banking app ko fail dikhata hai
# ─────────────────────────────────────────────────────────────────────────────
log "BANKING" "Step 1: Killing GMS stack & wiping Integrity cache (accounts preserved)"

# NOTE: pm clear GMS se Google accounts wipe hote hain — KABHI pm clear mat karo GMS pe
for _gms in \
    com.google.android.gms \
    com.google.android.gms.unstable \
    com.google.android.gms.persistent \
    com.google.android.gms.droidguard \
    com.google.android.gsf \
    com.google.android.ims \
    com.google.android.safetycore \
    com.google.android.contactkeys; do
    am force-stop "$_gms" >/dev/null 2>&1 || true
done
am force-stop com.android.vending >/dev/null 2>&1 || true

# Sirf trim-caches — pm clear nahi
cmd package trim-caches 999999999 com.google.android.gms >/dev/null 2>&1 || true
cmd package trim-caches 999999999 com.android.vending     >/dev/null 2>&1 || true

# Sirf DroidGuard/integrity cache delete — baaki data safe
for _pi in com.google.android.gms com.android.vending; do
    rm -rf "/data/data/$_pi/app_dg_cache"    2>/dev/null || true
    rm -rf "/data/data/$_pi/app_droidguard"  2>/dev/null || true
    rm -rf "/data/data/$_pi/cache/dg_cache"  2>/dev/null || true
    rm -rf "/data/data/$_pi/cache/integrity" 2>/dev/null || true
    rm -rf "/data/data/$_pi/cache/attestation" 2>/dev/null || true
    rm -rf "/data/data/$_pi/cache/com.google.android.gms.droidguard" 2>/dev/null || true
done
unset _gms _pi

# ─────────────────────────────────────────────────────────────────────────────
# [D] STEP 2 — Root detector apps full wipe
# ─────────────────────────────────────────────────────────────────────────────
log "BANKING" "Step 2: Wiping root detector apps"
for _pkg in $DETECTOR_APPS; do
    _full_wipe "$_pkg"
done
unset _pkg

# ─────────────────────────────────────────────────────────────────────────────
# [B] STEP 3 — Filesystem artifact cleanup
# Reason: apps use access(), openat(), /proc/maps to find these files
# ─────────────────────────────────────────────────────────────────────────────
log "BANKING" "Step 3: Removing root filesystem artifacts"

# /data/local/tmp — most commonly checked location
for _f in \
    frida frida-server frida-inject frida-gadget re.frida.server \
    hluda linjector inject \
    shizuku shizuku_starter byyang resetprop \
    HyperCeiler luckys input_devices \
    su .su magisk apatch ksu \
    lspd edxp XposedInstaller \
    zygisk .zygisk shamiko; do
    rm -rf "/data/local/tmp/$_f" 2>/dev/null || true
done
unset _f

# sdcard root traces
rm -f  "/storage/emulated/0/meow_detector.log"           2>/dev/null || true
rm -f  "/storage/emulated/0/keybox_status.json"          2>/dev/null || true
rm -rf "/storage/emulated/0/.frida"                      2>/dev/null || true
rm -f  "/storage/emulated/0/frida"                       2>/dev/null || true

# Tool app sdcard data (from cleanup.sh)
for _tpkg in $TOOL_APPS; do
    rm -rf "/storage/emulated/0/Android/data/$_tpkg" 2>/dev/null || true
done
rm -rf "/storage/emulated/0/MT2"                         2>/dev/null || true
rm -rf "/storage/emulated/0/bin.mt.termux"               2>/dev/null || true
rm -rf "/storage/emulated/0/com.termux"                  2>/dev/null || true
rm -rf "/storage/emulated/0/xzr.hkf"                    2>/dev/null || true
rm -rf "/storage/emulated/0/Download/WechatXposed"       2>/dev/null || true
rm -rf "/storage/emulated/0/WechatXposed"                2>/dev/null || true
rm -rf "/storage/emulated/0/Android/naki"                2>/dev/null || true
rm -f  "/storage/emulated/0/最新版隐藏配置.json"          2>/dev/null || true
rm -rf "/storage/emulated/0/rlgg"                        2>/dev/null || true
unset _tpkg

# Remote control sdcard data
for _rcpkg in $REMOTE_CONTROL_APPS; do
    rm -rf "/storage/emulated/0/Android/data/$_rcpkg" 2>/dev/null || true
done
rm -rf "/storage/emulated/0/.anydesk"                    2>/dev/null || true
rm -rf "/storage/emulated/0/anydesk"                     2>/dev/null || true
rm -rf "/storage/emulated/0/.rustdesk"                   2>/dev/null || true
rm -rf "/storage/emulated/0/rustdesk"                    2>/dev/null || true
rm -rf "/storage/emulated/0/.vysor"                      2>/dev/null || true
rm -rf "/storage/emulated/0/Vysor"                       2>/dev/null || true
unset _rcpkg

# /dev socket traces — LSPosed daemon
rm -f  /dev/lspd                                         2>/dev/null || true
rm -f  /dev/.lspd*                                       2>/dev/null || true

# /data/system — graphicsstats, junge, NoActive, Freezer can leak app info
rm -rf /data/system/graphicsstats                        2>/dev/null || true
rm -rf /data/system/package_cache                        2>/dev/null || true
rm -rf /data/system/NoActive                             2>/dev/null || true
rm -rf /data/system/Freezer                              2>/dev/null || true
rm -rf /data/system/junge                                2>/dev/null || true
rm -f  /data/swap_config.conf                            2>/dev/null || true
rm -rf /dev/memcg/scene_idle                             2>/dev/null || true
rm -rf /dev/memcg/scene_active                           2>/dev/null || true
rm -rf /dev/scene                                        2>/dev/null || true
rm -rf /dev/cpuset/scene-daemon                          2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────────
# [K] STEP 4 — Log/crash leaks
# Reason: tombstones & dropbox expose root app names to any reading app
# ─────────────────────────────────────────────────────────────────────────────
log "BANKING" "Step 4: Clearing log & crash leaks"
rm -f  /data/tombstones/tombstone_0*                     2>/dev/null || true
rm -f  /data/system/dropbox/data_app_crash*              2>/dev/null || true
rm -f  /data/system/dropbox/data_app_anr*                2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────────
# [J] STEP 5 — LSPosed traces
# Reason: base.odex files in /data/app expose LSPosed injection to any scanner
# ─────────────────────────────────────────────────────────────────────────────
log "BANKING" "Step 5: Cleaning LSPosed base.odex traces"
_odex_count=0
for _odex in $(find /data/app -type f -name base.odex 2>/dev/null); do
    rm -f "$_odex" 2>/dev/null && _odex_count=$((_odex_count + 1)) || true
done
[ "$_odex_count" -gt 0 ] && log "BANKING" "Deleted $_odex_count base.odex files"
unset _odex _odex_count

# ─────────────────────────────────────────────────────────────────────────────
# [A] STEP 6 — System props hardening
# Reason: JNI getprop() calls, /proc/cmdline, /proc/bootconfig checks
# ─────────────────────────────────────────────────────────────────────────────
log "BANKING" "Step 6: Hardening system props"
apply_boot_props
block_rom_spoof_engines

# Extra root indicator props not covered by apply_boot_props
for _rp in \
    ro.magisk.version ro.boot.magisk \
    ro.build.fingerprint.original ro.build.fingerprint.backup \
    debug.atrace.tags.enableflags debug.force_rtl \
    libc.debug.malloc libc.debug.malloc.options \
    ro.debuggable.test service.adb.root; do
    resetprop --delete "$_rp"    2>/dev/null || true
    resetprop -p --delete "$_rp" 2>/dev/null || true
done
unset _rp

# ─────────────────────────────────────────────────────────────────────────────
# [G] STEP 7 — SELinux enforce check
# Reason: permissive SELinux = obvious root flag for any app doing getenforce()
# ─────────────────────────────────────────────────────────────────────────────
log "BANKING" "Step 7: Checking SELinux state"
if [ -f "/sys/fs/selinux/enforce" ]; then
    _enforce=$(cat /sys/fs/selinux/enforce 2>/dev/null || echo "1")
    if [ "$_enforce" = "0" ]; then
        # Cannot re-enforce kernel-level, but at least fix the prop
        resetprop -n ro.boot.selinux enforcing 2>/dev/null || true
        resetprop -n ro.build.selinux 1        2>/dev/null || true
        log "BANKING" "Warning: SELinux is permissive — prop spoofed but kernel-level unfixable"
    else
        resetprop -n ro.boot.selinux enforcing 2>/dev/null || true
        resetprop -n ro.build.selinux 1        2>/dev/null || true
        log "BANKING" "SELinux: Enforcing — good"
    fi
fi
unset _enforce

# ─────────────────────────────────────────────────────────────────────────────
# [F] [E] STEP 8 — Developer Options + ADB disable
# Reason: Settings.Global is readable by any app with no special permission
# ─────────────────────────────────────────────────────────────────────────────
log "BANKING" "Step 8: Disabling Developer Options & ADB"
for _p in \
    persist.service.adb.enable persist.service.debuggable \
    persist.sys.developer_options persist.sys.dev_mode \
    persist.sys.debuggable persist.sys.dev.mode \
    persist.hyperceiler.log.level persist.adb.notify \
    persist.sys.root_access persist.sys.usb.config \
    persist.traced.enable persist.debug.wfd.enable \
    persist.zygote.app_data_isolation \
    persist.com.luckyzyx.luckytool.log.level \
    persist.com.luckyzyx.luckytool.debug \
    persist.com.luckyzyx.luckytool.enable; do
    resetprop -p --delete "$_p" 2>/dev/null || true
done
unset _p

sp_persist persist.sys.developer_options 0
sp_persist persist.sys.dev_mode          0
sp_persist persist.sys.debuggable        0

settings put global development_settings_enabled 0 >/dev/null 2>&1 || true
settings put global adb_enabled                  0 >/dev/null 2>&1 || true
settings put global oem_unlock_allowed           0 >/dev/null 2>&1 || true
settings put global adb_wifi_enabled             0 >/dev/null 2>&1 || true
settings put global adb_wifi_port               -1 >/dev/null 2>&1 || true

# ADB daemon kill
_adbd=$(getprop init.svc.adbd 2>/dev/null || echo "")
[ "$_adbd" = "running" ] && setprop ctl.stop adbd 2>/dev/null || true
unset _adbd

# TCP ADB port clear
_tcp=$(getprop service.adb.tcp.port 2>/dev/null || echo "")
[ -n "$_tcp" ] && resetprop service.adb.tcp.port -1 2>/dev/null || true
unset _tcp

# USB state — force MTP only
setprop sys.usb.config mtp 2>/dev/null || true
setprop sys.usb.state  mtp 2>/dev/null || true
[ -f /sys/class/android_usb/android0/functions ] && \
    echo "mtp" > /sys/class/android_usb/android0/functions 2>/dev/null || true

# Boot hardening (from apply_boot_hardening in common.sh)
apply_boot_hardening

# ─────────────────────────────────────────────────────────────────────────────
# [C] STEP 9 — Kill live root processes
# Reason: /proc/<pid>/maps read karne se banking app frida/su dekh sakti hai
# ─────────────────────────────────────────────────────────────────────────────
log "BANKING" "Step 9: Killing live root/injection processes"
for _proc in \
    frida-server frida-inject hluda linjector \
    "re.frida.server" magiskd apatchd ksucd; do
    pkill -9 -f "$_proc" 2>/dev/null || true
done
unset _proc

# ─────────────────────────────────────────────────────────────────────────────
# [I] STEP 10 — Zygisk Next hardening (THE most important step for modern apps)
# Reason: Zygisk linker namespace dikhta hai /proc/maps mein
# zygisk_next commands: anonymous memory, builtin linker = invisible
# ─────────────────────────────────────────────────────────────────────────────
log "BANKING" "Step 10: Zygisk Next hardening"
_znext=""
for _zd in /data/adb/modules/zygisksu /data/adb/modules_update/zygisksu; do
    [ -f "$_zd/bin/zygiskd" ] && _znext="$_zd/bin/zygiskd" && break
done

if [ -n "$_znext" ]; then
    "$_znext" enforce-denylist just_umount 2>/dev/null || true
    "$_znext" memory-type anonymous        2>/dev/null || true
    "$_znext" linker builtin               2>/dev/null || true
    log "BANKING" "Zygisk Next hardened (anonymous memory + builtin linker)"
else
    log "BANKING" "Zygisk Next not found — skipping (may use Magisk built-in)"
fi
unset _znext _zd

# ─────────────────────────────────────────────────────────────────────────────
# [D] STEP 11 — Remote control apps stop + cache wipe
# Reason: screen sharing app chal raha ho to banking app detect kar sakti hai
# ─────────────────────────────────────────────────────────────────────────────
log "BANKING" "Step 11: Stopping remote control & tool apps"
for _rca in $REMOTE_CONTROL_APPS; do
    _is_installed "$_rca" || continue
    am force-stop "$_rca"                    >/dev/null 2>&1 || true
    rm -rf "/data/data/$_rca/cache"           2>/dev/null || true
    rm -rf "/data/data/$_rca/code_cache"      2>/dev/null || true
done
unset _rca

# com.juom — known detection app (from cleanup.sh)
pm clear com.juom >/dev/null 2>&1 || true

# ─────────────────────────────────────────────────────────────────────────────
# STEP 12 — Auto-detect & clean ALL installed financial apps
# No hardcoded country/bank list — pattern match on package name
# HIGH RISK: deep clean (shared_prefs wipe — login safe hai)
# OTHERS: cache-only clean (auto-scan from pm list)
# ─────────────────────────────────────────────────────────────────────────────
log "BANKING" "Step 13: Auto-detect & clean all finance apps"

# Known high-risk apps that store root flags in shared_prefs
_HIGH_RISK="
net.one97.paytm com.phonepe.app com.csam.icici.bank.imobile
com.axis.mobile com.axis.mobile.plus com.snapwork.hdfc com.enstage.wibmo.hdfc
com.kotak.mahindra.kotak811 com.kotak.mahindra.kotakBank
com.indusind.ibmobile com.rbl.rblmobilebanking com.dreamplug.androidapp
com.hsbc.hsbcnet com.barclays.android.barclaysmobilebanking
com.lloydsbank.mobile com.rbs.mobile.android.santander
com.chase.sig.android com.bankofamerica.connect
com.wellsfargo.ceomobile com.usaa.mobile.android.usaa
com.citibank.mobile.au com.commbank.netbank com.bendigobank.mobile
com.ing.mobile com.anz.android com.nab.mobile com.westpac.bank
com.revolut.revolut com.n26.mobile com.starling.android com.monzo.android
com.nubank.nubank com.itau com.bradesco.prime com.bb.mobile
com.kasikorn.retail.mbanking.wap com.bangkokbank.bblmobile com.scb.phone
"
for _hp in $_HIGH_RISK; do
    _is_installed "$_hp" || continue
    am force-stop "$_hp"                        >/dev/null 2>&1 || true
    rm -rf "/data/data/$_hp/cache"              2>/dev/null || true
    rm -rf "/data/data/$_hp/code_cache"         2>/dev/null || true
    rm -rf "/data/data/$_hp/files/detector"     2>/dev/null || true
    rm -rf "/data/data/$_hp/files/integrity"    2>/dev/null || true
    pm set-installer "$_hp" com.android.vending 2>/dev/null || true
    log "BANKING" "Deep clean: $_hp"
done
unset _hp _HIGH_RISK

# Auto-scan: koi bhi finance-pattern app — worldwide, no country hardcoding
# Multilingual patterns: banca(IT), banque(FR), sparkasse/volksbank(DE),
# gcash/paymaya(PH), mpesa(KE/TZ), momo(VN/GH), kasse(Scandinavian)
echo "$_installed_pkgs" | sed 's/package://g' | while read -r _ap; do
    [ -z "$_ap" ] && continue
    # Skip system & Google apps
    case "$_ap" in
        com.google.*|com.android.*|android|com.qualcomm.*|com.mediatek.*) continue ;;
    esac
    case "$_ap" in
        *bank*|*\.pay|*\.pay\.*|*payment*|*wallet*|*finance*|*credit*|\
        *\.cash|*\.cash\.*|*money*|*invest*|*trading*|*bourse*|*broker*|\
        *lending*|*loan*|*banca*|*banque*|*kasse*|*volksbank*|*raiffeisen*|\
        *caixa*|*fintech*|*neobank*|*mpesa*|*momo*|*gcash*|*paymaya*|\
        *instamojo*|*upi*|*bhim*|*neft*|*imps*|*netbanking*)
            am force-stop "$_ap"                        >/dev/null 2>&1 || true
            rm -rf "/data/data/$_ap/cache"              2>/dev/null || true
            rm -rf "/data/data/$_ap/code_cache"         2>/dev/null || true
            cmd package trim-caches 999999999 "$_ap"    >/dev/null 2>&1 || true
            pm set-installer "$_ap" com.android.vending 2>/dev/null || true
            log "BANKING" "Auto clean: $_ap"
            ;;
    esac
done
unset _ap

# ─────────────────────────────────────────────────────────────────────────────
# STEP 13 — GMS fresh restart + fresh DroidGuard token
# ─────────────────────────────────────────────────────────────────────────────
log "BANKING" "Step 14: GMS fresh restart + DroidGuard token"
sleep 1
am startservice \
    -n com.google.android.gms/.chimera.GmsIntentOperationService \
    >/dev/null 2>&1 || true
sleep 2
am startservice \
    -n com.google.android.gms/.droidguard.DroidGuardService \
    >/dev/null 2>&1 || true
sleep 1
am force-stop com.android.vending >/dev/null 2>&1 || true

# ─────────────────────────────────────────────────────────────────────────────
# STEP 14 — Kernel pointer hide + Magisk app hide
# ─────────────────────────────────────────────────────────────────────────────
log "BANKING" "Step 15: Kernel pointers hide + Magisk app hide"

# Kernel pointers — /proc/kallsyms se root detect nahi hoga
echo 2 > /proc/sys/kernel/kptr_restrict      2>/dev/null || true
echo 1 > /proc/sys/kernel/perf_event_paranoid 2>/dev/null || true

# Magisk app hide — banking apps seedha Magisk nahi dekh payengi
for _magisk_pkg in \
    com.topjohnwu.magisk \
    io.github.vvb2060.magisk \
    io.github.huskydg.magisk; do
    _is_installed "$_magisk_pkg" && \
        pm hide "$_magisk_pkg" >/dev/null 2>&1 || true
done
unset _magisk_pkg

# ─────────────────────────────────────────────────────────────────────────────
# STEP 15 — Save state & cleanup
# ─────────────────────────────────────────────────────────────────────────────
cfg_set banking_mode 1
log "BANKING" "=== Banking Mode Done — open your banking app now ==="

unset _installed_pkgs
unset -f _is_installed _full_wipe
exit 0
