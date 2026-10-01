#!/system/bin/sh
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
