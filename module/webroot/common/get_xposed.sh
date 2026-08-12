#!/system/bin/sh
# Live Xposed/LSPosed module detector for the App Targeting "Deselect
# Unnecessary" action. Same-to-same port of Tricky Addon's
# common/get_extra.sh --xposed: for every user-installed app, unzip its
# APK and check for the xposed_init resource or an xposed/module.prop
# entry — either one marks it as an Xposed module, regardless of package
# name. This catches modules that aren't in any hardcoded or remote
# exclude list, unlike the static AT_LOCAL_UNNECESSARY_PKGS list the
# WebUI also checks against.
#
# Output: one package name per line (stdout), matching what the WebUI's
# atDeselectUnnecessary() expects to merge into its exclude Set.
MODDIR="${0%/*}"
MODDIR="${MODDIR%/*}"
MODDIR="${MODDIR%/*}"
TMP_DIR="$MODDIR/webroot/tmp"
XPOSED_CACHE="$TMP_DIR/xposed_found"
SKIP_CACHE="$TMP_DIR/xposed_skiplist"

mkdir -p "$TMP_DIR"
touch "$XPOSED_CACHE" "$SKIP_CACHE"

pm list packages -3 | cut -d':' -f2 | grep -vxF -f "$SKIP_CACHE" | grep -vxF -f "$XPOSED_CACHE" | \
while IFS= read -r PACKAGE; do
    [ -z "$PACKAGE" ] && continue
    APK_PATH=$(pm path "$PACKAGE" 2>/dev/null | head -n1 | cut -d: -f2)
    [ -z "$APK_PATH" ] && continue
    if unzip -l "$APK_PATH" 2>/dev/null | grep -qE "xposed_init|xposed/module.prop"; then
        echo "$PACKAGE" >> "$XPOSED_CACHE"
    else
        echo "$PACKAGE" >> "$SKIP_CACHE"
    fi
done

cat "$XPOSED_CACHE"
