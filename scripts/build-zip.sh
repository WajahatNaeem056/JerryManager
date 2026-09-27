#!/usr/bin/env bash
set -euo pipefail

# Read version from module.prop, stripping an optional leading "v"
# (module.prop stores "v4.4", but arithmetic below needs "4.4").
RAW_VER=$(grep '^version=' src/module.prop | cut -d= -f2)
BASE_VER=${RAW_VER#v}
BUILD=$(grep '^versionCode=' src/module.prop | cut -d= -f2)

HASH=$(git rev-parse --short=7 HEAD 2>/dev/null || echo '0000000')
FULL_VER="v${BASE_VER}-g${HASH}"

MAJOR=$(echo "$BASE_VER" | cut -d. -f1)
MINOR=$(echo "$BASE_VER" | cut -d. -f2)
PATCH=$(echo "$BASE_VER" | cut -d. -f3)
MAJOR=${MAJOR:-0}
MINOR=${MINOR:-0}
PATCH=${PATCH:-0}
VC=$((MAJOR * 10000 + MINOR * 1000 + PATCH * 100 + BUILD))

echo "Full version: $FULL_VER"
echo "Version code: $VC"

cd Module
sed -i "s/^version=.*/version=${FULL_VER}/" module.prop
sed -i "s/^versionCode=.*/versionCode=${VC}/" module.prop
rm -f "../module.zip" "../JerryManager-${FULL_VER}.zip"
zip -r "../JerryManager-${FULL_VER}.zip" . > /dev/null
cd ..

echo "Built: JerryManager-${FULL_VER}.zip"
