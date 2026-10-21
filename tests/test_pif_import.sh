#!/bin/sh
# Run: dash tests/test_pif_import.sh   (any POSIX sh works)
# Backend tests for `pif_config.sh import`. Runs the real script against a sandbox copy of the module.
SRC=$(cd "$(dirname "$0")/../Jerry" && pwd)
T=$(mktemp -d); MOD=$T/mod; D=$T/data; mkdir -p "$D" "$T/files"
cp -R "$SRC" "$MOD"
export JERRY_PIF_PROP=$D/pif.prop PIF_IMPORT_BACKUP_DIR=$D/bak PIF_IMPORT_WORK_ROOT=$D/work
PIF_PROP=$JERRY_PIF_PROP
F=$T/files; pass=0; failn=0
run() { sh "$MOD/features/pif_config.sh" import "$1" 2>&1; }
ok()   { pass=$((pass+1)); echo "PASS $1"; }
bad()  { failn=$((failn+1)); echo "FAIL $1"; echo "$OUT" | sed 's/^/    | /'; }
expect_ok()  { OUT=$(run "$2"); echo "$OUT" | grep -q '^IMPORT_OK$' && ok "$1" || bad "$1"; }
expect_err() { OUT=$(run "$2"); echo "$OUT" | grep -q "^IMPORT_ERR: .*$3" && ok "$1" || bad "$1"; }
same() { cmp -s "$PIF_PROP" "$T/before" && ok "$1" || { OUT="pif.prop changed"; bad "$1"; }; }
snap() { cp "$PIF_PROP" "$T/before"; }

FP='google/komodo_beta/komodo:CANARY/ZP11.260918.007/16484274:user/release-keys'
cp "$SRC/pif.prop" "$PIF_PROP"
# user toggles that must survive an import
sed -i 's/^spoofProvider=.*/spoofProvider=true/; s/^spoofBuild=.*/spoofBuild=false/' "$PIF_PROP"

# 1 valid pif.json (Fork style, string flags + aliases)
cat > $F/pif.json <<J
{
  "FINGERPRINT": "$FP",
  "MANUFACTURER": "Google",
  "MODEL": "Pixel 9 Pro XL",
  "SECURITY_PATCH": "2026-10-05",
  "DEVICE_INITIAL_SDK_INT": "34",
  "spoofBuild": "true",
  "VERSION.RELEASE": "CANARY",
  "WEIRD_UNKNOWN": "x"
}
J
expect_ok "valid pif.json imports" $F/pif.json
grep -q "^MODEL=Pixel 9 Pro XL$" $PIF_PROP && grep -q "^FINGERPRINT=$FP$" $PIF_PROP && grep -q '^DEVICE_INITIAL_SDK_INT=34$' $PIF_PROP && ok "json values reached pif.prop" || { OUT=$(cat $PIF_PROP); bad "json values reached pif.prop"; }
grep -q '^spoofProvider=true$' $PIF_PROP && grep -q '^spoofBuild=false$' $PIF_PROP && ok "user spoof toggles preserved (file flags ignored)" || { OUT=$(cat $PIF_PROP); bad "toggles preserved"; }
grep -q WEIRD $PIF_PROP && { OUT=$(cat $PIF_PROP); bad "unknown key leaked"; } || ok "unknown keys not written"
[ "$(ls $D/bak | wc -l)" -ge 1 ] && ok "backup created" || bad "backup created"
sh "$MOD/features/pif_config.sh" get | grep -q '"spoofProvider":true' && ok "existing backend 'get' still reads result" || bad "backend get"

# unsupported key names are reported
printf 'FINGERPRINT=%s\nMODEL=Pixel\nMANUFACTURER=Google\nID=ZP11\nBOARD=komodo\n' "$FP" > $F/unk.prop
OUT=$(run $F/unk.prop); echo "$OUT" | grep -q '^Ignored 2 unsupported key(s): ID, BOARD$' && ok "ignored keys are named" || bad "ignored keys are named"
printf 'FINGERPRINT=%s\nMODEL=Pixel\nMANUFACTURER=Google\nA1=1\nA2=1\nA3=1\nA4=1\nA5=1\nA6=1\nA7=1\n' "$FP" > $F/unk7.prop
OUT=$(run $F/unk7.prop); echo "$OUT" | grep -q '^Ignored 7 unsupported key(s): A1, A2, A3, A4, A5, \.\.\.$' && ok "long ignored list is capped" || bad "long ignored list is capped"

# 2 valid pif.prop (comments, CRLF, quotes, spaces)
printf '# my pif\r\nFINGERPRINT = "google/tokay_beta/tokay:CANARY/ZP11.1/123:user/release-keys"\r\nMANUFACTURER=Google\r\nMODEL=Pixel 9\r\n\r\nSECURITY_PATCH=2026-09-05\r\nDEVICE_INITIAL_SDK_INT=34\r\nspoofProps=false' > $F/pif.prop
expect_ok "valid pif.prop (CRLF/quotes/comments/no trailing newline)" $F/pif.prop
grep -q '^MODEL=Pixel 9$' $PIF_PROP && grep -q '^FINGERPRINT=google/tokay_beta' $PIF_PROP && ok "prop values reached pif.prop" || { OUT=$(cat $PIF_PROP); bad "prop values"; }
grep -q '^spoofProvider=true$' $PIF_PROP && ok "toggles still preserved after prop import" || bad "toggles after prop"

# 3 minified json + BOM + numeric sdk + aliases
printf '\357\273\277{"FINGERPRINT":"%s","MODEL":"Pixel 6a","MANUFACTURER":"Google","VERSION.SECURITY_PATCH":"2026-10-05","*.security_patch":"2026-10-05","first_api_level":32}' "$FP" > $F/min.json
expect_ok "minified JSON with BOM and aliases" $F/min.json
grep -q '^DEVICE_INITIAL_SDK_INT=32$' $PIF_PROP && grep -q '^SECURITY_PATCH=2026-10-05$' $PIF_PROP && ok "aliases mapped" || { OUT=$(cat $PIF_PROP); bad "aliases mapped"; }

# ---- rejections: pif.prop must stay byte-identical ----
snap
expect_err "missing file" $F/nope.json "not found"
expect_err "directory" $F "not found"
: > $F/empty.json; expect_err "empty file" $F/empty.json "empty"
printf '{"FINGERPRINT": "%s",}' "$FP" > $F/trail.json; expect_err "trailing comma JSON" $F/trail.json "Malformed"
printf '{"FINGERPRINT": "%s" "MODEL":"x"}' "$FP" > $F/nocomma.json; expect_err "missing comma JSON" $F/nocomma.json "Malformed"
printf '{"FINGERPRINT": "%s", "n": {"a":1}}' "$FP" > $F/nested.json; expect_err "nested object JSON" $F/nested.json "Malformed"
printf '{"FINGERPRINT": "%s"' "$FP" > $F/trunc.json; expect_err "truncated JSON" $F/trunc.json "Malformed"
printf '[{"FINGERPRINT":"x"}]' > $F/arr.json; expect_err "JSON array" $F/arr.json "arrays"
printf 'FINGERPRINT=%s\n' "$FP" > $F/notjson.json; expect_err ".json that is not JSON" $F/notjson.json "Not valid JSON"
printf '{"MODEL":"Pixel"}' > $F/nofp.json; expect_err "JSON without FINGERPRINT" $F/nofp.json "No FINGERPRINT"
printf 'MODEL=Pixel\n' > $F/nofp.prop; expect_err "prop without FINGERPRINT" $F/nofp.prop "No FINGERPRINT"
printf 'FINGERPRINT=not-a-fingerprint\nMODEL=x\n' > $F/badfp.prop; expect_err "malformed fingerprint" $F/badfp.prop "format"
printf 'FINGERPRINT=%s\nthis is junk\n' "$FP" > $F/junk.prop; expect_err "junk line in prop" $F/junk.prop "Line 2"
printf 'FINGERPRINT=%s\nSECURITY_PATCH=yesterday\n' "$FP" > $F/badpatch.prop; expect_err "bad SECURITY_PATCH" $F/badpatch.prop "SECURITY_PATCH"
printf 'FINGERPRINT=%s\nDEVICE_INITIAL_SDK_INT=abc\n' "$FP" > $F/badsdk.prop; expect_err "bad SDK int" $F/badsdk.prop "DEVICE_INITIAL_SDK_INT"
printf 'FINGERPRINT=%s\nMODEL=A\nMODEL=B\n' "$FP" > $F/dup.prop; expect_err "conflicting duplicate (prop)" $F/dup.prop "Conflicting"
printf '{"FINGERPRINT":"%s","MODEL":"A","MODEL":"B"}' "$FP" > $F/dup.json; expect_err "conflicting duplicate (json)" $F/dup.json "Conflicting"
printf '{"FINGERPRINT":"%s","MODEL":"A","MODEL":"A","MANUFACTURER":"G"}' "$FP" > $F/dupok.json; OUT=$(run $F/dupok.json); echo "$OUT" | grep -q IMPORT_OK && ok "identical duplicate tolerated" || bad "identical duplicate tolerated"; cp $T/before $PIF_PROP
printf '<?xml version="1.0"?><x/>' > $F/keybox.xml; expect_err "unsupported type (.xml)" $F/keybox.xml "Unsupported"
printf 'FINGERPRINT=%s\n\000\001bin' "$FP" > $F/bin.prop; expect_err "binary content" $F/bin.prop "binary"
head -c 70000 /dev/zero | tr '\0' 'a' > $F/big.prop; expect_err "oversized file" $F/big.prop "too large"
printf 'FINGERPRINT=%s\nMODEL=Bad\\Model\n' "$FP" > $F/esc.prop; expect_err "backslash in value" $F/esc.prop "unsupported characters"
expect_err "no argument" "" "No file"
same "pif.prop untouched after all rejected imports"

# 4 write failure -> previous config kept
snap
chmod 555 $D 2>/dev/null
if [ "$(id -u)" != 0 ]; then
  OUT=$(run $F/pif.json); echo "$OUT" | grep -q '^IMPORT_ERR:' && ok "write failure reports error" || bad "write failure reports error"
  chmod 755 $D; same "pif.prop intact after write failure"
else echo "SKIP write-failure test (running as root)"; chmod 755 $D; fi

# 5 built-in PIF not installed
rm -rf $MOD/zygisk; OUT=$(run $F/pif.json); echo "$OUT" | grep -q 'IMPORT_ERR: Built-in PIF not installed' && ok "reports missing built-in PIF" || bad "missing built-in PIF"
mkdir $MOD/zygisk

# 6 backup pruning
for i in 1 2 3 4 5 6 7 8; do touch -d "2020-01-0$i" $D/bak/pif.prop.2020010${i}_000000.bak 2>/dev/null; done
OUT=$(run $F/pif.json); n=$(ls $D/bak | wc -l); [ "$n" -le 5 ] && ok "backups pruned to <=5 ($n)" || { OUT="count=$n"; bad "backup pruning"; }
ls -A $D | grep -q '^\.pif' && { OUT=$(ls -A $D); bad "temp files left behind"; } || ok "no temp/work leftovers"

echo "---- $pass passed, $failn failed"; rm -rf $T; [ $failn -eq 0 ]
