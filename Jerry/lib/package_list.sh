FIXED_TARGETS="\
android
com.android.vending
com.google.android.gsf
com.google.android.gms
com.google.android.contactkeys
com.google.android.ims
com.google.android.safetycore
com.google.android.apps.walletnfcrel
com.google.android.apps.nbu.paisa.user"

DETECTOR_APPS="com.zhenxi.hunter icu.nullptr.nativetest icu.nullptr.applistdetector com.byxiaorun.detector io.github.huskydg.memorydetector com.OrangeEnvironment.Detector com.Longze.detector.pro2 rikka.safetynetchecker io.github.vvb2060.keyattestation io.github.vvb2060.mahoshojo com.lingqing.detector aidepro.top com.junge.algorithmAidePro chunqiu.safe luna.safe.luna io.liankong.riskdetector com.studio.duckdetector com.android.nativetest com.byyoung.setting com.scottyab.rootbeer com.scottyab.rootbeer.sample com.topjohnwu.magisk.detector com.devadvance.rootcloak com.fde.xposed.detector com.zhenxi.checker com.example.nativelibtest com.example.memcheck com.example.syscallchecker com.jrummyapps.rootchecker com.kimchangyoun.magiskdetector com.reveny.nativechecker com.reveny.environmentchecker com.reveny.rootchecker com.guardian.detect com.security.environmentchecker com.integrity.checker com.integrity.attestation com.lody.virtual com.lody.virtual.client com.lody.virtual.server com.lody.whale com.kimchangyoun.rootbeerfresh com.didikee.rootcheck com.joeykrim.rootcheck com.freeandroidtools.rootchecker com.bluestacks.rootchecker com.moonshine.checker com.ramdroid.appdetector com.smlj.rootcheck com.devadvance.rootcloakplus com.formyhm.hideroot com.example.emulatordetector com.vmcheck.detector com.virtual.checker com.antivm.detector com.xposed.checker com.google.snet.test com.attestation.checker com.integrity.check com.native.checker com.syscall.detector com.memory.scan me.garfieldhan.holmes"

GMS_APPS="com.android.vending com.google.android.gsf com.google.android.gms com.google.android.contactkeys com.google.android.ims com.google.android.safetycore com.google.android.apps.walletnfcrel com.google.android.apps.nbu.paisa.user"

REMOTE_CONTROL_APPS="com.anydesk.anydeskandroid com.teamviewer.teamviewer.market.mobile com.teamviewer.quicksupport.market com.sand.airdroid com.sand.airmirror com.koushikdutta.vysor com.genymobile.scrcpy com.microsoft.rdc.androidx com.realvnc.viewer.android com.splashtop.remote.pad.v2 com.dwservice.dwagent com.carriez.flutter_hbb com.carriez.flutter_hbbclient com.rustdesk.rustdesk"

TOOL_APPS="com.omarea.vtools moe.shizuku.privileged.api com.estrongs.android.pop com.sevtinge.hyperceiler com.coderstory.toolkit"

# Packages Auto Target must never target (root managers, Xposed/LSPosed managers)
AUTO_TARGET_EXCLUDE="\
com.topjohnwu.magisk
io.github.vvb2060.magisk
io.github.huskydg.magisk
me.weishu.kernelsu
com.rifsxd.ksunext
com.sukisu.ultra
com.resukisu.resukisu
me.bmax.apatch
me.garfieldhan.apatch.next
com.android.patch
org.lsposed.manager
org.meowcat.edxposed.manager
de.robv.android.xposed.installer
com.solohsu.android.edxp.manager
com.coderstory.toolkit
moe.shizuku.privileged.api"

# True if $1 is excluded or already cached as an Xposed module
is_auto_target_excluded() {
  _iae_pkg="$1"
  for _iae_e in $AUTO_TARGET_EXCLUDE; do
    [ "$_iae_pkg" = "$_iae_e" ] && { unset _iae_pkg _iae_e; return 0; }
  done
  unset _iae_e
  case "$MODDIR" in
    */features) _iae_root="${MODDIR%/*}" ;;
    *)          _iae_root="$MODDIR" ;;
  esac
  _iae_xp="$_iae_root/webroot/tmp/xposed_found"
  unset _iae_root
  if [ -f "$_iae_xp" ] && grep -Fxq "$_iae_pkg" "$_iae_xp" 2>/dev/null; then
    unset _iae_xp
    unset _iae_pkg
    return 0
  fi
  unset _iae_pkg
  return 1
}

SUSPICIOUS_PROPS="\
persist.hyperceiler.log.level|warning|HyperCeiler modding tool persistent log
persist.sys.vold_app_data_isolation_enabled|warning|App data isolation leak from modding tool
persist.zygote.app_data_isolation|critical|Zygote data isolation — root-level hooking artifact
persist.com.luckyzyx.luckytool.log.level|warning|LuckyTool Xposed module debug log
persist.com.luckyzyx.luckytool.debug|warning|LuckyTool Xposed module debug mode
persist.com.luckyzyx.luckytool.enable|warning|LuckyTool Xposed module enabled state
persist.service.adb.enable|critical|ADB was persistently enabled — debug bridge exposure
persist.service.debuggable|critical|Debug mode was persistently enabled
persist.sys.developer_options|warning|Developer options were previously enabled
persist.sys.xposed|critical|Xposed framework persistent state detected
persist.sys.edxposed|critical|EdXposed framework persistent state detected
persist.sys.lsposed|critical|LSPosed framework persistent state detected
persist.sys.root_access|critical|Root access persistent flag detected
persist.sys.root_mode|critical|Root mode persistent flag detected"
