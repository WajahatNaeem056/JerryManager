# shellcheck shell=sh
# Android system notifications from root shell scripts (no app/APK needed).
# Uses the platform notification service via `cmd notification post`.
# Support is probed at runtime; every attempt is verified against
# `dumpsys notification`, so a silent no-op is logged instead of claimed.

# Single-quote a string so it survives `su -c "<string>"`
_jn_sq() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# 0 if this device's notification service has the "post" shell command
jn_supported() {
    command -v cmd >/dev/null 2>&1 || return 1
    cmd notification help 2>&1 | grep -qi 'post'
}

# 0 if a notification with this tag is currently known to the system
_jn_visible() {
    sleep 1
    dumpsys notification 2>/dev/null | grep -qF "$1"
}

# Run one post attempt. $1=label, $2=tag, rest of the command comes via _jn_cmd.
# Return: 0 verified, 2 posted but unverifiable, 1 failed
_jn_attempt() {
    _ja_label="$1" _ja_tag="$2"
    shift 2
    _ja_out=$("$@" 2>&1)
    _ja_rc=$?
    if [ "$_ja_rc" -ne 0 ] || printf '%s' "$_ja_out" | grep -qiE '^(error|exception|java\.|unknown|can.t find service|permission denial)'; then
        log "NOTIFY" "Attempt '$_ja_label' failed (rc=$_ja_rc)"
        unset _ja_label _ja_tag _ja_out _ja_rc
        return 1
    fi
    if _jn_visible "$_ja_tag"; then
        log "NOTIFY" "Posted via '$_ja_label' (verified in notification service)"
        unset _ja_label _ja_tag _ja_out _ja_rc
        return 0
    fi
    if dumpsys notification >/dev/null 2>&1; then
        # dumpsys works but the tag is not listed: the post did not stick
        log "NOTIFY" "Attempt '$_ja_label' returned OK but notification not listed"
        unset _ja_label _ja_tag _ja_out _ja_rc
        return 1
    fi
    log "NOTIFY" "Posted via '$_ja_label' (could not verify, dumpsys unavailable)"
    unset _ja_label _ja_tag _ja_out _ja_rc
    return 2
}

# jn_post <title> <text> <unique-tag>
jn_post() {
    _jp_title="$1" _jp_text="$2" _jp_tag="$3"

    _jp_try=0
    while ! jn_supported; do
        _jp_try=$((_jp_try + 1))
        if [ "$_jp_try" -ge 3 ]; then
            log "NOTIFY" "'cmd notification post' not available on this device — no notification sent"
            unset _jp_title _jp_text _jp_tag _jp_try
            return 1
        fi
        sleep 2
    done
    unset _jp_try

    _jp_to=""
    command -v timeout >/dev/null 2>&1 && _jp_to="timeout 20"

    # 1) as the shell user (uid 2000), the identity `cmd notification` is built for.
    #    Some ROMs (ColorOS) accept a root post but never show it, so this goes first.
    if command -v su >/dev/null 2>&1; then
        _jp_cmd="cmd notification post -S bigtext -t $(_jn_sq "$_jp_title") $(_jn_sq "$_jp_tag") $(_jn_sq "$_jp_text")"
        # shellcheck disable=SC2086
        _jn_attempt "shell uid (su 2000)" "$_jp_tag" $_jp_to su 2000 -c "$_jp_cmd"
        _jp_rc=$?
        [ "$_jp_rc" -ne 1 ] && { unset _jp_title _jp_text _jp_tag _jp_to _jp_cmd; return 0; }
        # shellcheck disable=SC2086
        _jn_attempt "shell uid (su -lp 2000)" "$_jp_tag" $_jp_to su -lp 2000 -c "$_jp_cmd"
        _jp_rc=$?
        [ "$_jp_rc" -ne 1 ] && { unset _jp_title _jp_text _jp_tag _jp_to _jp_cmd; return 0; }
    fi

    # 2) as the current (root) user
    # shellcheck disable=SC2086
    _jn_attempt "root" "$_jp_tag" $_jp_to cmd notification post -S bigtext -t "$_jp_title" "$_jp_tag" "$_jp_text"
    _jp_rc=$?
    [ "$_jp_rc" -ne 1 ] && { unset _jp_title _jp_text _jp_tag _jp_to _jp_cmd; return 0; }

    log "NOTIFY" "All notification attempts failed — apps were still added, only the notification is missing"
    unset _jp_title _jp_text _jp_tag _jp_to _jp_cmd _jp_rc
    return 1
}
