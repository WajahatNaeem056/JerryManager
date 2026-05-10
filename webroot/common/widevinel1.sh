#!/system/bin/sh
SCRIPT_DIR="${0%/*}"
FW_DIR="$SCRIPT_DIR/FixWidevineL1"

if [ -d "$FW_DIR" ]; then
  cp -r "$FW_DIR"/* /data/local/tmp/
fi

chmod 755 /data/local/tmp/FixWidevineL1.sh 2>/dev/null
chmod 755 /data/local/tmp/attestation 2>/dev/null
chown root:root /data/local/tmp/FixWidevineL1.sh 2>/dev/null
chown root:root /data/local/tmp/attestation 2>/dev/null

sh /data/local/tmp/FixWidevineL1.sh
exit 0
