#!/bin/sh
# Turns a clean checkout of this repository into the Trick Store variant (built-in Tricky Store OSS only).
# Run it in the CI workspace or in a throw-away copy, never on a tree you want to keep as the Normal build.
#   sh variants/trickstore/apply.sh
# Steps: verify the stored binaries against SHA256SUMS -> dry-run every patch -> apply -> copy the overlay
# -> verify the copied files again. Any failure exits non-zero and the build must not continue.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
cd "$ROOT"
fail() { echo "apply.sh: $*" >&2; exit 1; }

[ -f Jerry/module.prop ] || fail "Jerry/module.prop not found (run from a repository checkout)"
[ ! -e Jerry/ts ] && [ ! -e Jerry/sepolicy.rule ] || fail "Trick Store variant already applied to this tree"
grep -q 'TS_CONFLICT_IDS' Jerry/lib/paths.sh 2>/dev/null && fail "Trick Store patches already applied to this tree"

echo "== verify stored Trick Store OSS binaries (SHA256)"
( cd "$HERE" && sha256sum -c SHA256SUMS ) || fail "SHA256 mismatch in variants/trickstore/overlay"

echo "== patch dry-run (no fuzz)"
for p in "$HERE"/patches/*.patch; do
  patch -p1 --dry-run --fuzz=0 --no-backup-if-mismatch -i "$p" >/dev/null || fail "patch does not apply cleanly: $(basename "$p")"
done

echo "== apply patches"
for p in "$HERE"/patches/*.patch; do
  patch -p1 --fuzz=0 --no-backup-if-mismatch -i "$p" || fail "failed applying $(basename "$p")"
done

echo "== copy overlay"
cp -a "$HERE/overlay/Jerry/." Jerry/

echo "== verify copied files (SHA256)"
sed 's#  overlay/Jerry/#  Jerry/#' "$HERE/SHA256SUMS" | sha256sum -c - || fail "SHA256 mismatch after copying the overlay"

echo "Trick Store variant applied."
