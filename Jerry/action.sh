#!/system/bin/sh
MODDIR=${0%/*}

. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/paths.sh"
. "$MODDIR/lib/config_env.sh"

echo ""
echo "Running full integrity pipeline"
echo ""

_step_label() {
    case "$1" in
        kill_all.sh) echo "Kill Non-GMS Apps" ;;
        gms.sh) echo "GMS Management" ;;
        target.sh) echo "App Targeting" ;;
        security_patch.sh) echo "Security Patch" ;;
        boot_hash.sh) echo "Boot Hash" ;;
        keybox.sh) echo "Keybox" ;;
        pif.sh) echo "PIF" ;;
        cleanup.sh) echo "Cleanup" ;;
        *) echo "$1" ;;
    esac
}

_format_fact() {
    _ff_line="$1"
    _ff_feature="$2"
    case "$_ff_feature:$_ff_line" in
        cleanup.sh:Finish)
            echo "Cleanup process finished"
            unset _ff_line _ff_feature
            return 0
            ;;
        pif.sh:Start)
            echo "Starting PIF fingerprint update"
            unset _ff_line _ff_feature
            return 0
            ;;
        pif.sh:Finish)
            echo "PIF fingerprint updating complete"
            unset _ff_line _ff_feature
            return 0
            ;;
    esac
    case "$_ff_line" in
        "Cleared "*)
            _ff_paren=$(printf '%s' "$_ff_line" | sed -n 's/.*(\(.*\))$/\1/p')
            _ff_main=$(printf '%s' "$_ff_line" | sed 's/ (.*)$//')
            echo "$_ff_main"
            if [ -n "$_ff_paren" ]; then
                echo "$_ff_paren" | sed 's/, / • /g'
            fi
            unset _ff_paren _ff_main
            ;;
        "Force-stopped "*)
            echo "$_ff_line"
            ;;
        "OhMyKeymint active"*)
            echo "Backend: OhMyKeymint"
            ;;
        "OhMyKeymint: processed "*)
            _ff_n=$(echo "$_ff_line" | sed -n 's/^OhMyKeymint: processed \([0-9]*\) .*/\1/p')
            echo "Mode: merge"
            [ -n "$_ff_n" ] && echo "Added: $_ff_n entries"
            unset _ff_n
            ;;
        "TEESimulator — generating"*)
            echo "Mode: TEESimulator"
            ;;
        "Merge pass: added "*)
            _ff_n=$(echo "$_ff_line" | sed -n 's/^Merge pass: added \([0-9]*\) .*/\1/p')
            echo "Mode: merge"
            [ -n "$_ff_n" ] && echo "Added: $_ff_n entries"
            case "$_ff_line" in
                *"existing manual entries untouched"*) echo "Manual entries: untouched" ;;
            esac
            unset _ff_n
            ;;
        "Writing "*" via "*)
            _ff_date=$(echo "$_ff_line" | sed -n 's/^Writing \([^ ]*\) via .*/\1/p')
            _ff_backend=$(echo "$_ff_line" | sed -n 's/^Writing .* via \(.*\)$/\1/p')
            [ -n "$_ff_date" ] && echo "Applied: $_ff_date"
            [ -n "$_ff_backend" ] && echo "Backend: $_ff_backend"
            unset _ff_date _ff_backend
            ;;
        "Wrote hash to "*)
            echo "Hash written successfully"
            echo "${_ff_line#Wrote hash to }"
            ;;
        "Custom keybox installed from "*)
            echo "Source: custom"
            echo "Installed successfully"
            ;;
        "Checking Google revocation for serial "*)
            echo "Serial: ${_ff_line#Checking Google revocation for serial }"
            ;;
        "Keybox is not revoked — clean")
            echo "Revocation: clean"
            ;;
        "locked.xml written to "*)
            echo "Mode: TEESimulator"
            echo "Installed successfully"
            ;;
        "Placeholder locked.xml written")
            echo "Mode: TEESimulator (placeholder — no ECDSA key found)"
            ;;
        "Keybox installed successfully")
            echo "Installed successfully"
            ;;
        "Detected "*" variant")
            _ff_variant=$(printf '%s' "$_ff_line" | sed -n 's/^Detected \(.*\) variant$/\1/p')
            echo "Detected: ${_ff_variant:-$_ff_line}"
            unset _ff_variant
            ;;
        "Selected device: "*)
            echo "Selected Device: ${_ff_line#Selected device: }"
            ;;
        Warning:*)
            echo "⚠ ${_ff_line#Warning: }"
            ;;
        Error:*)
            echo "✕ ${_ff_line#Error: }"
            ;;
        *)
            echo "$_ff_line"
            ;;
    esac
    unset _ff_line _ff_feature
}

_print_start_line() {
    _ps_feature="$1"
    [ -z "$_ps_feature" ] && return 0
    if [ "$_pl_printed_section" = "true" ]; then
        echo ""
    fi
    _pl_printed_section=true
    echo "→ $(_step_label "$_ps_feature")"
    case "$_ps_feature" in
        keybox.sh) echo "Checking revocation status..." ;;
    esac
    unset _ps_feature
}

_print_fact_line() {
    _pf_feature="$1" _pf_line="$2"
    [ -z "$_pf_feature" ] && return 0
    _pf_line=$(printf '%s' "$_pf_line" | sed 's/¦/|/g')
    _format_fact "$_pf_line" "$_pf_feature"
    unset _pf_feature _pf_line
}

_print_done_line() {
    _pd_feature="$1" _pd_rc="$2" _pd_had_error="$3"
    [ -z "$_pd_feature" ] && return 0
    if [ "$_pd_rc" -ne 0 ] 2>/dev/null && [ "$_pd_had_error" != "true" ]; then
        echo "✕ Failed"
    fi
    unset _pd_feature _pd_rc _pd_had_error
}

if [ ! -f "$MODDIR/pipelines/full_integrity" ]; then
    echo ""
    echo "Pipeline definition missing"
    [ "${0##*/}" = "action.sh" ] && exit 1 || return 1
fi

_al_rc_tmp=$(mktemp 2>/dev/null || echo "/data/local/tmp/.jerry_action_rc_$$")
_al_current_had_error=false
{ sh "$MODDIR/orchestrator.sh" full_integrity 3>&1 1>/dev/null 2>/dev/null; echo $? > "$_al_rc_tmp"; } | \
    while IFS= read -r _al_result_line; do
        case "$_al_result_line" in
            __START__\|*)
                _al_current_had_error=false
                _print_start_line "${_al_result_line#__START__|}"
                ;;
            __FACT__\|*)
                _al_rest="${_al_result_line#__FACT__|}"
                _al_feat="${_al_rest%%|*}"
                _al_fact="${_al_rest#*|}"
                case "$_al_fact" in Error:*) _al_current_had_error=true ;; esac
                _print_fact_line "$_al_feat" "$_al_fact"
                unset _al_rest _al_feat _al_fact
                ;;
            __DONE__\|*)
                _al_rest="${_al_result_line#__DONE__|}"
                _al_feat="${_al_rest%%|*}"
                _al_rc="${_al_rest#*|}"
                _print_done_line "$_al_feat" "$_al_rc" "$_al_current_had_error"
                unset _al_rest _al_feat _al_rc
                ;;
        esac
    done
_pipeline_rc=$(cat "$_al_rc_tmp" 2>/dev/null)
rm -f "$_al_rc_tmp"
unset _al_rc_tmp _al_current_had_error
[ -z "$_pipeline_rc" ] && _pipeline_rc=1

echo ""

if [ "$_pipeline_rc" -eq 0 ]; then
    echo "Integrity pipeline execution completed ✓"
    echo ""
fi
unset _pipeline_rc

if [ -f "$MODDIR/webroot/common/device-info.sh" ]; then
  sh "$MODDIR/webroot/common/device-info.sh" >/dev/null 2>&1
elif [ -f /data/adb/modules_update/Jerrykey/webroot/common/device-info.sh ]; then
  sh /data/adb/modules_update/Jerrykey/webroot/common/device-info.sh >/dev/null 2>&1
fi

update_description >/dev/null 2>&1

[ "${0##*/}" = "action.sh" ] && exit 0 || return 0
