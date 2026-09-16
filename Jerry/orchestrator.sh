#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/paths.sh"

PIPELINE="$1"
PIPELINE_FILE="$MODDIR/pipelines/$PIPELINE"

[ -z "$PIPELINE" ] && die "No pipeline specified"
[ ! -f "$PIPELINE_FILE" ] && die "Pipeline not found: $PIPELINE"

# dash aborts on a redirection error even inside 2>/dev/null unless it's
# wrapped in a real subshell — needed to detect fd 3 safely.
_HAVE_FD3=false
if ( : >&3 ) 2>/dev/null; then
    _HAVE_FD3=true
fi

# Patterns copied verbatim from each script's real log() calls — never
# guessed by log position, so a progress line can't be mistaken for a result.
_reliable_patterns_for_tag() {
    case "$1" in
        KILL_ALL) echo "Cleared *" ;;
        GMS) echo "Force-stopped * package(s)" ;;
        TARGET) echo "OhMyKeymint active *|OhMyKeymint: processed * FIXED_TARGETS entries|TEESimulator — generating *|Merge pass: added *" ;;
        SECURITY_PATCH) echo "Writing * via *" ;;
        BOOT_HASH) echo "Wrote hash to *" ;;
        KEYBOX) echo "OhMyKeymint active *|Custom keybox installed from *|Checking Google revocation for serial *|Keybox is not revoked — clean|locked.xml written to *|Placeholder locked.xml written|Keybox installed successfully" ;;
        PIF) echo "Start|Detected * variant|Selected device: *|Finish" ;;
        CLEANUP) echo "Finish" ;;
        *) echo "" ;;
    esac
}

_is_reliable_line() {
    _irl_tag="$1" _irl_line="$2"
    case "$_irl_line" in
        Warning:*|Error:*) return 0 ;;
    esac
    _irl_patterns=$(_reliable_patterns_for_tag "$_irl_tag")
    _irl_ifs_bak="$IFS"; IFS='|'
    for _irl_pat in $_irl_patterns; do
        IFS="$_irl_ifs_bak"
        [ -z "$_irl_pat" ] && continue
        case "$_irl_line" in
            $_irl_pat) IFS="$_irl_ifs_bak"; unset _irl_tag _irl_line _irl_patterns _irl_pat; return 0 ;;
        esac
    done
    IFS="$_irl_ifs_bak"
    unset _irl_tag _irl_line _irl_patterns _irl_pat
    return 1
}

_count_log_lines() {
    [ -f "$JERRYMANAGER_LOG_FILE" ] || { echo 0; return 0; }
    wc -l < "$JERRYMANAGER_LOG_FILE" 2>/dev/null || echo 0
}

_run_feature_live() {
    _rf_tag="$1" _rf_feature="$2" _rf_path="$3"

    _rf_before=$(_count_log_lines)
    sh "$_rf_path" &
    _rf_pid=$!

    _rf_seen="$_rf_before"
    _rf_running=true
    while [ "$_rf_running" = "true" ]; do
        if ! kill -0 "$_rf_pid" 2>/dev/null; then
            _rf_running=false
        fi
        _rf_now=$(_count_log_lines)
        if [ "$_rf_now" -gt "$_rf_seen" ] 2>/dev/null; then
            tail -n "+$((_rf_seen + 1))" "$JERRYMANAGER_LOG_FILE" 2>/dev/null | \
                head -n "$((_rf_now - _rf_seen))" | \
                grep -F "[$_rf_tag]" | sed "s/^.*\[$_rf_tag\] //" | \
                while IFS= read -r _rf_line; do
                    [ -z "$_rf_line" ] && continue
                    if _is_reliable_line "$_rf_tag" "$_rf_line"; then
                        _rf_clean=$(printf '%s' "$_rf_line" | sed 's/~~//g; s/|/¦/g')
                        if [ "$_HAVE_FD3" = "true" ]; then
                            printf '__FACT__|%s|%s\n' "$_rf_feature" "$_rf_clean" >&3 2>/dev/null
                        fi
                        unset _rf_clean
                    fi
                done
            _rf_seen="$_rf_now"
        fi
        [ "$_rf_running" = "true" ] && sleep 0.2
    done
    wait "$_rf_pid"
    _rf_rc=$?
    unset _rf_tag _rf_feature _rf_path _rf_before _rf_pid _rf_seen _rf_running _rf_now
    return "$_rf_rc"
}

while IFS= read -r line; do
    [ -z "$line" ] && continue
    [ "${line#\#}" != "$line" ] && continue

    feature="$line"
    optional=false
    [ "${feature%\?}" != "$feature" ] && optional=true && feature="${feature%\?}"

    FEATURE_PATH="$MODDIR/features/$feature"
    if [ "$optional" = "true" ] && [ ! -f "$FEATURE_PATH" ]; then
        log "ORCH" "Warning: Optional feature '$feature' not found -- skipping"
        continue
    fi

    log "ORCH" "Running: $feature"
    if [ "$_HAVE_FD3" = "true" ]; then
        printf '__START__|%s\n' "$feature" >&3 2>/dev/null
    fi
    _tag_name=$(echo "$feature" | tr '[:lower:]' '[:upper:]' | sed 's/\.SH$//')
    if _run_feature_live "$_tag_name" "$feature" "$FEATURE_PATH"; then
        _feature_rc=0
    else
        _feature_rc=$?
        log "ORCH" "Warning: $feature failed — continuing with remaining pipeline steps"
    fi
    if [ "$_HAVE_FD3" = "true" ]; then
        printf '__DONE__|%s|%s\n' "$feature" "$_feature_rc" >&3 2>/dev/null
    fi
    unset _tag_name _feature_rc
done < "$PIPELINE_FILE"

exit 0
