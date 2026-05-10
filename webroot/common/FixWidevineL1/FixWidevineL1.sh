_abi=$(getprop ro.product.cpu.abi 2>/dev/null)
case "$_abi" in
  arm64|x86_64) _lib="/vendor/lib64/hw" ;;
  *)            _lib="/vendor/lib/hw" ;;
esac
LD_LIBRARY_PATH="$_lib" /vendor/bin/KmInstallKeybox /data/local/tmp/attestation attestation true
unset _abi _lib