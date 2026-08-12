#!/bin/sh
# Sources lib/common.sh and exercises version_ge() with known cases.
set -u
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
COMMON="$SCRIPT_DIR/../Jerry/lib/common.sh"

if [ ! -f "$COMMON" ]; then
    echo "FAIL: cannot find $COMMON"
    exit 1
fi

# shellcheck disable=SC1090
. "$COMMON"

status=0

assert_ge() {
    a="$1" b="$2"
    if version_ge "$a" "$b"; then
        echo "  ok: $a >= $b"
    else
        echo "  FAIL: expected $a >= $b to be true"
        status=1
    fi
}

assert_lt() {
    a="$1" b="$2"
    if version_ge "$a" "$b"; then
        echo "  FAIL: expected $a >= $b to be false"
        status=1
    else
        echo "  ok: $a < $b"
    fi
}

echo "version_ge: equal versions"
assert_ge "4.0.0" "4.0.0"

echo "version_ge: higher major"
assert_ge "5.0.0" "4.9.9"

echo "version_ge: higher minor"
assert_ge "4.1.0" "4.0.9"

echo "version_ge: higher patch"
assert_ge "4.0.1" "4.0.0"

echo "version_ge: lower version"
assert_lt "3.9.9" "4.0.0"

exit $status
