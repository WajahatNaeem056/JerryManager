#!/bin/sh
# Sanity-checks Jerry/module.prop: required fields present, versionCode is
# numeric, and version/versionCode look like they belong together
# (e.g. version=v4.0 -> versionCode should start with "40").
set -u
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROP="$SCRIPT_DIR/../Jerry/module.prop"

if [ ! -f "$PROP" ]; then
    echo "FAIL: cannot find $PROP"
    exit 1
fi

status=0
get_field() { grep -m1 "^$1=" "$PROP" | cut -d= -f2-; }

id=$(get_field id)
name=$(get_field name)
version=$(get_field version)
versionCode=$(get_field versionCode)

for field_name in id name version versionCode; do
    value=$(get_field "$field_name")
    if [ -z "$value" ]; then
        echo "FAIL: module.prop missing '$field_name'"
        status=1
    else
        echo "  ok: $field_name=$value"
    fi
done

case "$versionCode" in
    ''|*[!0-9]*)
        echo "FAIL: versionCode '$versionCode' is not numeric"
        status=1
        ;;
    *)
        echo "  ok: versionCode is numeric"
        ;;
esac

# version like "v4.0" should share its leading digits with versionCode "40"
version_digits=$(echo "$version" | tr -dc '0-9')
case "$versionCode" in
    "$version_digits"*|*"$version_digits")
        echo "  ok: version ($version) and versionCode ($versionCode) look related"
        ;;
    *)
        echo "  WARN: version ($version) and versionCode ($versionCode) don't obviously match — double check before release"
        ;;
esac

exit $status
