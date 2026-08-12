#!/bin/sh
# Jerry test runner — runs every tests/test_*.sh and reports pass/fail counts.
# Each test file should exit 0 on success, non-zero on failure, and print
# what it's checking as it goes.

set -u
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

pass=0
fail=0
failed_names=""

for test_file in test_*.sh; do
    [ -f "$test_file" ] || continue
    echo "── running $test_file ──"
    if sh "$test_file"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        failed_names="$failed_names $test_file"
    fi
    echo ""
done

echo "════════════════════════════════"
echo "Results: $pass passed, $fail failed"

if [ "$fail" -gt 0 ]; then
    echo "Failed:$failed_names"
    exit 1
fi

exit 0
