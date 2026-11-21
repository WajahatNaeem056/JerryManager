# shellcheck shell=sh
# Generate RKP Keybox backend: wraps dex/duckd, built from the RKP-only Duck-ToolBox source
# (rkp-device feature only: no Play Integrity / Tricky Store / kernel-modules etc).
# arm64-v8a only — the upstream binary is not built for v7a/x86_64.

RKP_DEVICE_DATA_ROOT="/data/adb/JerryManager/rkp_device"
RKP_DEVICE_OUTPUT=""
# Scratch space for duckd's worker (TMPDIR). Removed after every call.
RKP_DEVICE_TMP="$RKP_DEVICE_DATA_ROOT/.tmp"

# True if this device's ABI can run the vendored binary.
rkp_device_supported() {
    [ "$(uname -m 2>/dev/null)" = "aarch64" ]
}

# BBIN ("<root>/bin") is set by lib/paths.sh, sourced before this file — reuse its root
# rather than re-deriving MODDIR, since duckd lives in dex/, not bin/.
_rkp_device_bin() {
    printf '%s' "${BBIN%/bin}/dex/duckd"
}

# rkp_device/ must retain completed numbered run folders only: no var/ (outputs, logs, tmp),
# scratch dir, fake module files or legacy rkp_device_root shim.
_rkp_device_cleanup() {
    rm -rf "$RKP_DEVICE_DATA_ROOT/var" \
           "$RKP_DEVICE_TMP" \
           "$RKP_DEVICE_DATA_ROOT/module.prop" \
           "$RKP_DEVICE_DATA_ROOT/bin" \
           "$RKP_DEVICE_DATA_ROOT/ui" \
           "$RKP_DEVICE_DATA_ROOT/webroot" \
           "/data/adb/JerryManager/rkp_device_root" 2>/dev/null
}

_rkp_device_exec() {
    DUCK_TOOLBOX_ROOT="$RKP_DEVICE_DATA_ROOT" \
    DUCK_TOOLBOX_DATA_ROOT="$RKP_DEVICE_DATA_ROOT" \
    TMPDIR="$RKP_DEVICE_TMP" \
        "$(_rkp_device_bin)" rkp-device "$@"
}

# Run one duckd rkp-device subcommand with its root pointed at rkp_device/ itself (no
# separate shim root). Prints duckd's JSON envelope on stdout; mirrors its exit code.
# A duckd built before the root fix refuses a root without module.prop; for that build only,
# a marker is created for one retry and removed again by cleanup.
_rkp_device_run() {
    [ -x "$(_rkp_device_bin)" ] || { echo '{"ok":false,"error":{"code":"binary_missing"}}'; return 1; }
    ensure_dir "$RKP_DEVICE_DATA_ROOT"
    ensure_dir "$RKP_DEVICE_TMP"
    _rdr_out="$(_rkp_device_exec "$@")"; _rdr_rc=$?
    case "$_rdr_out" in
        *"valid Duck ToolBox module root"*)
            printf 'id=duck-toolbox\nname=Jerry Manager RKP\nversion=0.2.2-Stable\nversionCode=155\n' \
                > "$RKP_DEVICE_DATA_ROOT/module.prop"
            ensure_dir "$RKP_DEVICE_DATA_ROOT/bin"
            _rdr_out="$(_rkp_device_exec "$@")"; _rdr_rc=$?
            ;;
    esac
    # Provision must keep var/outputs until its generated run folder has been moved.
    case "$1" in
        provision) ;;
        *) _rkp_device_cleanup ;;
    esac
    printf '%s\n' "$_rdr_out"
    unset _rdr_out
    return "$_rdr_rc"
}

# Locate the one run directory Duck created. Its actual name is
# rkp-device-<unix-milliseconds>-<random-suffix>; preserve that generated suffix.
_rkp_device_find_run_dir() {
    _rdp_outputs="$RKP_DEVICE_DATA_ROOT/var/outputs"
    [ -d "$_rdp_outputs" ] || return 1
    _rdp_found=""
    _rdp_count=0
    for _rdp_candidate in "$_rdp_outputs"/rkp-device-*; do
        [ -d "$_rdp_candidate" ] || continue
        _rdp_found="$_rdp_candidate"
        _rdp_count=$((_rdp_count + 1))
    done
    [ "$_rdp_count" -eq 1 ] || return 1
    printf '%s\n' "$_rdp_found"
}

# JSON envelope: prerequisites_met, android_arm64, root, qualcomm_soc, mediatek_soc,
# v1_available, v1_native_available, v2_available, blockers[], etc.
rkp_device_status() {
    rkp_device_supported || { echo '{"ok":false,"error":{"code":"arch_unsupported"}}'; return 1; }
    _rkp_device_run status
}

# protocol: auto | v1 | v2 | v1-native. Default Duck provision writes the complete
# artifact set to var/outputs/rkp-device-<timestamp>-<random>/.
# Move that exact generated directory into rkp_device/rkp_device_<timestamp>-<random>/.
rkp_device_provision() {
    _rdp_protocol="${1:-auto}"
    RKP_DEVICE_OUTPUT=""
    rkp_device_supported || { unset _rdp_protocol; return 2; }

    # Start with a clean Duck workspace, but do not touch previously retained numbered runs.
    _rkp_device_cleanup
    ensure_dir "$RKP_DEVICE_DATA_ROOT"

    _rdp_result=$(_rkp_device_run provision \
        --protocol "$_rdp_protocol" \
        --acknowledge-limitations)
    _rdp_rc=$?
    if [ "$_rdp_rc" -ne 0 ]; then
        _rkp_device_cleanup
        printf '%s\n' "$_rdp_result"
        unset _rdp_protocol _rdp_result
        return "$_rdp_rc"
    fi

    _rdp_run_dir=$(_rkp_device_find_run_dir) || {
        echo "Duck provision succeeded but exactly one generated RKP run folder was not found" >&2
        printf '%s\n' "$_rdp_result"
        unset _rdp_protocol _rdp_result
        return 1
    }

    # Require all four artifacts before moving anything. On an incomplete run, leave var/
    # intact for diagnosis instead of deleting potentially recoverable output.
    for _rdp_file in keybox.xml private_key.pem cert_chain.der csr.cbor; do
        [ -s "$_rdp_run_dir/$_rdp_file" ] || {
            echo "RKP output is incomplete: missing $_rdp_file" >&2
            printf '%s\n' "$_rdp_result"
            unset _rdp_protocol _rdp_result
            return 1
        }
    done

    _rdp_run_name=${_rdp_run_dir##*/}
    _rdp_suffix=${_rdp_run_name#rkp-device-}
    [ -n "$_rdp_suffix" ] || {
        echo "Duck generated an unexpected RKP run folder name" >&2
        printf '%s\n' "$_rdp_result"
        unset _rdp_protocol _rdp_result
        return 1
    }
    _rdp_destination="$RKP_DEVICE_DATA_ROOT/rkp_device_$_rdp_suffix"
    [ ! -e "$_rdp_destination" ] || {
        echo "RKP destination already exists; refusing to overwrite it: $_rdp_destination" >&2
        printf '%s\n' "$_rdp_result"
        unset _rdp_protocol _rdp_result
        return 1
    }

    mv "$_rdp_run_dir" "$_rdp_destination" || {
        echo "Could not move the generated RKP folder; original output was preserved" >&2
        printf '%s\n' "$_rdp_result"
        unset _rdp_protocol _rdp_result
        return 1
    }

    RKP_DEVICE_OUTPUT="$_rdp_destination/keybox.xml"
    # The completed run is now outside var/, so cleanup cannot remove its four artifacts.
    _rkp_device_cleanup
    printf '%s\n' "$_rdp_result"

    unset _rdp_protocol _rdp_result _rdp_run_dir _rdp_run_name _rdp_suffix \
          _rdp_destination _rdp_file _rdp_outputs _rdp_found _rdp_count _rdp_candidate
    return 0
}
