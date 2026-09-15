#!/bin/sh
# ==============================================================================
# VCRT OS v2.0 - MODULE BẢO MẬT & XÁC THỰC (mod_auth.sh)
# Tương thích chuẩn POSIX / BusyBox 1.33+ OpenWrt
# ==============================================================================

_CUR_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd 2>/dev/null || echo "")"
if [ -f "$_CUR_DIR/../lib/constants.sh" ]; then
    . "$_CUR_DIR/../lib/constants.sh"
elif [ -f "$_CUR_DIR/../constants.sh" ]; then
    . "$_CUR_DIR/../constants.sh"
elif [ -f "$_CUR_DIR/constants.sh" ]; then
    . "$_CUR_DIR/constants.sh"
elif [ -f "/www/cgi-bin/lib/constants.sh" ]; then
    . "/www/cgi-bin/lib/constants.sh"
elif [ -f "/www/cgi-bin/constants.sh" ]; then
    . "/www/cgi-bin/constants.sh"
elif [ -f "/etc/vcrt/constants.sh" ]; then
    . "/etc/vcrt/constants.sh"
fi

: "${CONFIG_DIR:=/etc/vcrt}"
: "${AUTH_FILE:=/etc/vcrt/passwd}"
: "${SALT_FILE:=/etc/vcrt/salt}"
: "${SESSIONS_DIR:=/tmp/vcrt_sessions}"
: "${LOGIN_ATTEMPTS_FILE:=/tmp/vcrt_login_attempts}"

CURRENT_USER=""
CURRENT_TOKEN=""

json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' -e 's/\r/\\r/g' -e 's/\n/\\n/g'
}

send_response() {
    local status="${1:-200 OK}"
    local extra_hdr="$2"
    local body="$3"

    if [ "$CGI_HEADERS_SENT" != "1" ]; then
        printf 'Access-Control-Allow-Origin: *\r\n'
        printf 'Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n'
        printf 'Access-Control-Allow-Headers: Content-Type, Authorization\r\n'
        printf 'Status: %s\r\n' "$status"
        [ -n "$extra_hdr" ] && printf '%s\r\n' "$extra_hdr"
        printf 'Content-Type: application/json; charset=utf-8\r\n\r\n'
    fi
    printf '%s\n' "$body"
}

generate_salt() {
    local s
    s=$(head -c 16 /dev/urandom 2>/dev/null | sha256sum | cut -d' ' -f1 | cut -c1-16)
    [ -z "$s" ] && s=$(date +%s%N 2>/dev/null | sha256sum | cut -d' ' -f1 | cut -c1-16)
    [ -z "$s" ] && s=$(date +%s | sha256sum | cut -d' ' -f1 | cut -c1-16)
    printf '%s' "$s"
}

hash_password() {
    local salt="$1" pass="$2"
    printf '%s:%s' "$salt" "$pass" | sha256sum | cut -d' ' -f1
}

init_auth() {
    mkdir -p "$CONFIG_DIR" "$SESSIONS_DIR" 2>/dev/null
    if [ ! -f "$AUTH_FILE" ] || [ ! -s "$AUTH_FILE" ]; then
        local def_u="admin" def_p="admin"
        if [ -f "/etc/vcrt_auth.conf" ]; then
            local old_u old_p
            old_u=$(head -n1 "/etc/vcrt_auth.conf" 2>/dev/null | cut -d: -f1 | tr -d ' \r\n')
            old_p=$(head -n1 "/etc/vcrt_auth.conf" 2>/dev/null | cut -d: -f2 | tr -d ' \r\n')
            [ -n "$old_u" ] && def_u="$old_u"
            [ -n "$old_p" ] && def_p="$old_p"
        fi
        local s h
        s=$(generate_salt)
        h=$(hash_password "$s" "$def_p")
        printf '%s:%s:%s\n' "$def_u" "$s" "$h" > "$AUTH_FILE"
        chmod 600 "$AUTH_FILE" 2>/dev/null
        printf '%s\n' "$s" > "$SALT_FILE" 2>/dev/null
        chmod 600 "$SALT_FILE" 2>/dev/null
    fi
}

check_rate_limit() {
    local ip="$1"
    [ -z "$ip" ] && return 0
    [ ! -f "$LOGIN_ATTEMPTS_FILE" ] && return 0

    local line
    line=$(grep "^${ip}:" "$LOGIN_ATTEMPTS_FILE" 2>/dev/null | head -n1)
    [ -z "$line" ] && return 0

    local cnt first_ts now elapsed
    cnt=$(printf '%s' "$line" | cut -d: -f2)
    first_ts=$(printf '%s' "$line" | cut -d: -f3)
    now=$(date +%s)
    elapsed=$((now - first_ts))

    if [ "$cnt" -ge 5 ]; then
        if [ "$elapsed" -lt 600 ]; then
            local wait_sec=$((600 - elapsed))
            send_response "429 Too Many Requests" "Retry-After: $wait_sec" "{\"status\":\"error\",\"authenticated\":false,\"message\":\"Quá nhiều lần thử sai. IP bị khoá, vui lòng đợi $wait_sec giây.\",\"retry_after\":$wait_sec}"
            return 1
        else
            sed -i "/^${ip}:/d" "$LOGIN_ATTEMPTS_FILE" 2>/dev/null
            return 0
        fi
    else
        if [ "$elapsed" -gt 300 ]; then
            sed -i "/^${ip}:/d" "$LOGIN_ATTEMPTS_FILE" 2>/dev/null
            return 0
        fi
    fi
    return 0
}

record_login_failure() {
    local ip="$1"
    [ -z "$ip" ] && return 0
    local now=$(date +%s)
    touch "$LOGIN_ATTEMPTS_FILE" 2>/dev/null

    local line
    line=$(grep "^${ip}:" "$LOGIN_ATTEMPTS_FILE" 2>/dev/null | head -n1)
    if [ -z "$line" ]; then
        printf '%s:1:%s\n' "$ip" "$now" >> "$LOGIN_ATTEMPTS_FILE"
    else
        local cnt first_ts elapsed
        cnt=$(printf '%s' "$line" | cut -d: -f2)
        first_ts=$(printf '%s' "$line" | cut -d: -f3)
        elapsed=$((now - first_ts))

        if [ "$elapsed" -gt 300 ] && [ "$cnt" -lt 5 ]; then
            sed -i "s/^${ip}:.*/${ip}:1:${now}/" "$LOGIN_ATTEMPTS_FILE" 2>/dev/null
        else
            local new_cnt=$((cnt + 1))
            sed -i "s/^${ip}:.*/${ip}:${new_cnt}:${first_ts}/" "$LOGIN_ATTEMPTS_FILE" 2>/dev/null
        fi
    fi
}

reset_login_attempts() {
    local ip="$1"
    [ -n "$ip" ] && [ -f "$LOGIN_ATTEMPTS_FILE" ] && sed -i "/^${ip}:/d" "$LOGIN_ATTEMPTS_FILE" 2>/dev/null
}

validate_session() {
    local tok="$1"
    [ -z "$tok" ] && return 1
    tok=$(printf '%s' "$tok" | tr -cd 'a-zA-Z0-9_-')
    [ -z "$tok" ] && return 1
    [ ! -f "$SESSIONS_DIR/$tok" ] && return 1

    local ts now
    ts=$(awk '{print $2}' "$SESSIONS_DIR/$tok" 2>/dev/null)
    [ -z "$ts" ] && { rm -f "$SESSIONS_DIR/$tok" 2>/dev/null; return 1; }
    now=$(date +%s)

    if [ $((now - ts)) -gt 1800 ]; then
        rm -f "$SESSIONS_DIR/$tok" 2>/dev/null
        return 1
    fi

    sed -i "s/$ts/$now/" "$SESSIONS_DIR/$tok" 2>/dev/null
    CURRENT_USER=$(awk '{print $1}' "$SESSIONS_DIR/$tok" 2>/dev/null)
    CURRENT_TOKEN="$tok"
    return 0
}

require_auth() {
    local tok="$PARAM_TOKEN"
    if [ -z "$tok" ] && [ -n "$POST_BODY" ]; then
        tok=$(printf '%s' "$POST_BODY" | grep -o '"token":"[^"]*"' | head -n1 | cut -d'"' -f4)
    fi
    if [ -z "$tok" ] && [ -n "$HTTP_AUTHORIZATION" ]; then
        tok=$(printf '%s' "$HTTP_AUTHORIZATION" | sed -n 's/^[Bb]earer[[:space:]]*//p' | tr -d ' \r\n')
    fi
    if [ -z "$tok" ] && [ -n "$HTTP_COOKIE" ]; then
        tok=$(printf '%s' "$HTTP_COOKIE" | sed -n 's/.*vcrt_token=\([^;]*\).*/\1/p' | tr -d ' \r\n')
    fi

    if ! validate_session "$tok"; then
        send_response "401 Unauthorized" "" '{"status":"error","authenticated":false,"message":"session_expired"}'
        exit 0
    fi
}

action_login() {
    init_auth
    local u="${PARAM_USER}"
    local p="${PARAM_PASS}"

    if [ -z "$u" ] && [ -n "$POST_BODY" ]; then
        u=$(printf '%s' "$POST_BODY" | grep -o '"user":"[^"]*"' | head -n1 | cut -d'"' -f4)
        [ -z "$u" ] && u=$(printf '%s' "$POST_BODY" | grep -o '"username":"[^"]*"' | head -n1 | cut -d'"' -f4)
    fi
    if [ -z "$p" ] && [ -n "$POST_BODY" ]; then
        p=$(printf '%s' "$POST_BODY" | grep -o '"pass":"[^"]*"' | head -n1 | cut -d'"' -f4)
        [ -z "$p" ] && p=$(printf '%s' "$POST_BODY" | grep -o '"password":"[^"]*"' | head -n1 | cut -d'"' -f4)
    fi
    [ -z "$u" ] && u="admin"

    local client_ip="${REMOTE_ADDR:-${PARAM_IP:-127.0.0.1}}"
    check_rate_limit "$client_ip" || exit 0

    local line stored_u salt expected_hash
    line=$(grep "^${u}:" "$AUTH_FILE" 2>/dev/null | head -n1)
    if [ -z "$line" ]; then
        record_login_failure "$client_ip"
        send_response "401 Unauthorized" "" '{"status":"error","authenticated":false,"message":"Tài khoản hoặc mật khẩu không chính xác"}'
        exit 0
    fi

    stored_u=$(printf '%s' "$line" | cut -d: -f1)
    salt=$(printf '%s' "$line" | cut -d: -f2)
    expected_hash=$(printf '%s' "$line" | cut -d: -f3)

    local cal_hash
    cal_hash=$(hash_password "$salt" "$p")

    if [ "$u" = "$stored_u" ] && [ "$cal_hash" = "$expected_hash" ] && [ -n "$expected_hash" ]; then
        reset_login_attempts "$client_ip"
        local tok
        tok=$(head -c 32 /dev/urandom 2>/dev/null | sha256sum | cut -d' ' -f1)
        [ -z "$tok" ] && tok="tok_$(date +%s)_$RANDOM"
        printf '%s %s\n' "$u" "$(date +%s)" > "$SESSIONS_DIR/$tok"
        chmod 600 "$SESSIONS_DIR/$tok" 2>/dev/null

        local esc_tok esc_u cookie_hdr
        esc_tok=$(json_escape "$tok")
        esc_u=$(json_escape "$u")
        cookie_hdr="Set-Cookie: vcrt_token=$tok; HttpOnly; SameSite=Strict; Path=/"
        send_response "200 OK" "$cookie_hdr" "{\"status\":\"ok\",\"authenticated\":true,\"token\":\"$esc_tok\",\"user\":\"$esc_u\"}"
        exit 0
    else
        record_login_failure "$client_ip"
        send_response "401 Unauthorized" "" '{"status":"error","authenticated":false,"message":"Tài khoản hoặc mật khẩu không chính xác"}'
        exit 0
    fi
}

action_logout() {
    local tok="$PARAM_TOKEN"
    [ -z "$tok" ] && [ -n "$POST_BODY" ] && tok=$(printf '%s' "$POST_BODY" | grep -o '"token":"[^"]*"' | head -n1 | cut -d'"' -f4)
    [ -z "$tok" ] && [ -n "$HTTP_COOKIE" ] && tok=$(printf '%s' "$HTTP_COOKIE" | sed -n 's/.*vcrt_token=\([^;]*\).*/\1/p' | tr -d ' \r\n')
    tok=$(printf '%s' "$tok" | tr -cd 'a-zA-Z0-9_-')
    [ -n "$tok" ] && rm -f "$SESSIONS_DIR/$tok" 2>/dev/null

    local clear_cookie="Set-Cookie: vcrt_token=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT"
    send_response "200 OK" "$clear_cookie" '{"status":"ok","message":"Đã đăng xuất"}'
    exit 0
}

action_change_password() {
    require_auth
    local u="${CURRENT_USER:-admin}"
    local old_p="$PARAM_PASS"
    local new_p="$PARAM_NEW_PASS"

    if [ -n "$POST_BODY" ]; then
        local bp
        bp=$(printf '%s' "$POST_BODY" | grep -o '"old_pass":"[^"]*"' | head -n1 | cut -d'"' -f4)
        [ -n "$bp" ] && old_p="$bp"
        bp=$(printf '%s' "$POST_BODY" | grep -o '"new_pass":"[^"]*"' | head -n1 | cut -d'"' -f4)
        [ -n "$bp" ] && new_p="$bp"
    fi

    if [ -z "$new_p" ]; then
        send_response "400 Bad Request" "" '{"status":"error","message":"Mật khẩu mới không được để trống"}'
        exit 0
    fi

    local line salt expected_hash cal_hash
    line=$(grep "^${u}:" "$AUTH_FILE" 2>/dev/null | head -n1)
    if [ -z "$line" ]; then
        send_response "404 Not Found" "" '{"status":"error","message":"Không tìm thấy tài khoản người dùng"}'
        exit 0
    fi

    salt=$(printf '%s' "$line" | cut -d: -f2)
    expected_hash=$(printf '%s' "$line" | cut -d: -f3)
    cal_hash=$(hash_password "$salt" "$old_p")

    if [ "$cal_hash" != "$expected_hash" ]; then
        send_response "403 Forbidden" "" '{"status":"error","message":"Mật khẩu cũ không chính xác"}'
        exit 0
    fi

    local new_salt new_hash
    new_salt=$(generate_salt)
    new_hash=$(hash_password "$new_salt" "$new_p")

    local tmp_auth="${AUTH_FILE}.tmp.$$"
    touch "$tmp_auth" && chmod 600 "$tmp_auth" 2>/dev/null
    if [ -f "$AUTH_FILE" ]; then
        grep -v "^${u}:" "$AUTH_FILE" > "$tmp_auth" 2>/dev/null || true
    fi
    printf '%s:%s:%s\n' "$u" "$new_salt" "$new_hash" >> "$tmp_auth"
    mv -f "$tmp_auth" "$AUTH_FILE"
    printf '%s\n' "$new_salt" > "$SALT_FILE" 2>/dev/null

    rm -rf "${SESSIONS_DIR:?}"/* 2>/dev/null

    local clear_cookie="Set-Cookie: vcrt_token=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT"
    send_response "200 OK" "$clear_cookie" '{"status":"ok","message":"Đã đổi mật khẩu thành công. Vui lòng đăng nhập lại."}'
    exit 0
}

action_auth_check() {
    local tok="$PARAM_TOKEN"
    [ -z "$tok" ] && [ -n "$POST_BODY" ] && tok=$(printf '%s' "$POST_BODY" | grep -o '"token":"[^"]*"' | head -n1 | cut -d'"' -f4)
    [ -z "$tok" ] && [ -n "$HTTP_AUTHORIZATION" ] && tok=$(printf '%s' "$HTTP_AUTHORIZATION" | sed -n 's/^[Bb]earer[[:space:]]*//p' | tr -d ' \r\n')
    [ -z "$tok" ] && [ -n "$HTTP_COOKIE" ] && tok=$(printf '%s' "$HTTP_COOKIE" | sed -n 's/.*vcrt_token=\([^;]*\).*/\1/p' | tr -d ' \r\n')

    if validate_session "$tok"; then
        local u="${CURRENT_USER:-admin}"
        local esc_u
        esc_u=$(json_escape "$u")
        send_response "200 OK" "" "{\"status\":\"ok\",\"authenticated\":true,\"user\":\"$esc_u\"}"
    else
        send_response "401 Unauthorized" "" '{"status":"error","authenticated":false,"message":"Chưa đăng nhập hoặc phiên làm việc đã hết hạn"}'
    fi
    exit 0
}

case "$ACTION" in
    login) action_login ;;
    logout) action_logout ;;
    auth_check) action_auth_check ;;
    change_password) action_change_password ;;
esac
