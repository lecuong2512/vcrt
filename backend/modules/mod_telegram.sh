#!/bin/sh
# VCRT OS v2.0 - Telegram Bot Management Module
# Endpoints: telegram_get, telegram_set, telegram_test, telegram_service

handle_telegram_get() {
    local b_en="0" b_tok="" c_id="" n_wifi="1" n_exp="1" n_daily="1" d_hour="20" a_up="0"
    if [ -f "$TELEGRAM_CONF" ]; then
        while IFS='=' read -r k v; do
            case "$k" in
                BOT_ENABLED|bot_enabled) b_en=$(echo "$v" | tr -d ' "\r\n') ;;
                BOT_TOKEN|bot_token) b_tok=$(echo "$v" | tr -d ' "\r\n') ;;
                CHAT_ID|chat_id) c_id=$(echo "$v" | tr -d '\r\n"') ;;
                AUTO_UPDATE|auto_update) a_up=$(echo "$v" | tr -d ' "\r\n') ;;
                NOTIF_WIFI_JOIN|notif_wifi) n_wifi=$(echo "$v" | tr -d ' "\r\n') ;;
                NOTIF_BLOCK_EXPIRE|notif_expire) n_exp=$(echo "$v" | tr -d ' "\r\n') ;;
                NOTIF_DAILY_REPORT|notif_daily) n_daily=$(echo "$v" | tr -d ' "\r\n') ;;
                DAILY_REPORT_HOUR|daily_hour) d_hour=$(echo "$v" | tr -d ' "\r\n') ;;
            esac
        done < "$TELEGRAM_CONF"
    fi

    local tok_masked="" has_tok="false"
    if [ -n "$b_tok" ]; then
        has_tok="true"
        local tok_len=${#b_tok}
        if [ "$tok_len" -gt 10 ]; then
            local pfx sfx
            pfx=$(echo "$b_tok" | cut -c 1-6)
            sfx=$(echo "$b_tok" | awk '{print substr($0, length($0)-3, 4)}')
            tok_masked="${pfx}****${sfx}"
        else
            tok_masked="******"
        fi
    fi

    local is_running="false"
    if pgrep -f vcrt_bot.sh >/dev/null 2>&1; then
        is_running="true"
    fi

    local en_bool="false" nw_bool="false" ne_bool="false" nd_bool="false" au_bool="false"
    [ "$b_en" = "1" ] && en_bool="true"
    [ "$n_wifi" = "1" ] && nw_bool="true"
    [ "$n_exp" = "1" ] && ne_bool="true"
    [ "$n_daily" = "1" ] && nd_bool="true"
    [ "$a_up" = "1" ] && au_bool="true"

    printf '{"status":"ok","enabled":%s,"running":%s,"has_token":%s,"token_masked":"%s","chat_id":"%s","auto_update":%s,"notif_wifi":%s,"notif_expire":%s,"notif_daily":%s,"daily_hour":%d}\n' \
        "$en_bool" "$is_running" "$has_tok" "$(json_escape "$tok_masked")" "$(json_escape "$c_id")" "$au_bool" "$nw_bool" "$ne_bool" "$nd_bool" "${d_hour:-20}"
}

handle_telegram_set() {
    mkdir -p "$CONFIG_DIR" 2>/dev/null

    local cur_tok="" cur_cid=""
    if [ -f "$TELEGRAM_CONF" ]; then
        cur_tok=$(awk -F= '/^(BOT_TOKEN|bot_token)/{gsub(/[ "\r\n]/,"",$2); print $2}' "$TELEGRAM_CONF" 2>/dev/null)
        cur_cid=$(awk -F= '/^(CHAT_ID|chat_id)/{gsub(/[ "\r\n]/,"",$2); print $2}' "$TELEGRAM_CONF" 2>/dev/null)
    fi

    local t_tok="${PARAM_BOT_TOKEN:-$cur_tok}"
    local t_cid="${PARAM_CHAT_ID:-$cur_cid}"
    t_tok=$(echo "$t_tok" | sed 's/%3A/:/g; s/%3a/:/g')
    t_cid=$(echo "$t_cid" | sed 's/%20/ /g; s/%2C/,/g; s/%2c/,/g; s/+/ /g')

    local t_en="${PARAM_BOT_ENABLED:-1}"
    if [ -n "$t_tok" ] && [ -n "$t_cid" ]; then
        t_en="1"
    fi
    local t_au="${PARAM_AUTO_UPDATE:-0}"
    local t_nw="${PARAM_NOTIF_WIFI:-1}"
    local t_ne="${PARAM_NOTIF_EXPIRE:-1}"
    local t_nd="${PARAM_NOTIF_DAILY:-1}"
    local t_dh="${PARAM_DAILY_HOUR:-20}"

    cat << EOF > "$TELEGRAM_CONF"
BOT_ENABLED=${t_en}
BOT_TOKEN="${t_tok}"
CHAT_ID="${t_cid}"
AUTO_UPDATE=${t_au}
NOTIF_WIFI_JOIN=${t_nw}
NOTIF_BLOCK_EXPIRE=${t_ne}
NOTIF_DAILY_REPORT=${t_nd}
DAILY_REPORT_HOUR=${t_dh}
EOF
    chmod 600 "$TELEGRAM_CONF" 2>/dev/null || true

    # Quản lý service qua procd hoặc trực tiếp
    if [ "$t_en" = "1" ] && [ -n "$t_tok" ] && [ -n "$t_cid" ]; then
        if [ -x /etc/init.d/vcrt_bot ]; then
            /etc/init.d/vcrt_bot enable >/dev/null 2>&1 || true
            /etc/init.d/vcrt_bot restart >/dev/null 2>&1 || true
        else
            killall -9 vcrt_bot.sh 2>/dev/null || true
            ( sleep 1; /usr/bin/vcrt_bot.sh >/dev/null 2>&1 & ) &
        fi
    else
        if [ -x /etc/init.d/vcrt_bot ]; then
            /etc/init.d/vcrt_bot stop >/dev/null 2>&1 || true
            /etc/init.d/vcrt_bot disable >/dev/null 2>&1 || true
        fi
        killall -9 vcrt_bot.sh 2>/dev/null || true
    fi

    json_ok '"message":"saved_telegram_config"'
}

handle_telegram_test() {
    local tok="$PARAM_BOT_TOKEN" cid="$PARAM_CHAT_ID"
    if [ -z "$tok" ] && [ -f "$TELEGRAM_CONF" ]; then
        tok=$(awk -F= '/^(BOT_TOKEN|bot_token)/{gsub(/[ "\r\n]/,"",$2); print $2}' "$TELEGRAM_CONF" 2>/dev/null)
    fi
    if [ -z "$cid" ] && [ -f "$TELEGRAM_CONF" ]; then
        cid=$(awk -F= '/^(CHAT_ID|chat_id)/{gsub(/[ "\r\n]/,"",$2); print $2}' "$TELEGRAM_CONF" 2>/dev/null)
    fi
    tok=$(echo "$tok" | sed 's/%3A/:/g; s/%3a/:/g')
    cid=$(echo "$cid" | sed 's/%20/ /g; s/%2C/,/g; s/%2c/,/g; s/+/ /g')

    if [ -z "$tok" ] || [ -z "$cid" ]; then
        json_error "missing_token_or_chat_id"
        return 1
    fi

    local now_s test_body any_ok=0 err_last=""
    now_s=$(date +'%H:%M:%S - %d/%m/%Y' 2>/dev/null || echo "")
    test_body="🚀 <b>VCRT OS - KIỂM TRA ĐỒNG BỘ TELEGRAM BOT THÀNH CÔNG!</b>
━━━━━━━━━━━━━━━━━
📡 <b>Thiết bị:</b> <code>${DEVICE_NAME_DEFAULT:-Xiaomi MiWiFi Mini}</code>
⏰ <b>Thời gian:</b> <code>${now_s}</code>
🔗 <b>Trạng thái:</b> <code>Kết nối thông suốt với Web Dashboard</code>
━━━━━━━━━━━━━━━━━
<i>Hệ thống thông báo chạy ngầm đã sẵn sàng hoạt động 24/7!</i>"

    for one_cid in $(echo "$cid" | tr ',;' ' '); do
        [ -z "$one_cid" ] && continue
        local res
        res=$(curl -4 --tlsv1.2 -s --max-time 8 -X POST "https://api.telegram.org/bot${tok}/sendMessage" \
            -d "chat_id=${one_cid}" \
            -d "parse_mode=HTML" \
            --data-urlencode "text=${test_body}" 2>&1)
        if echo "$res" | grep -q '"ok":true'; then
            any_ok=1
        else
            err_last=$(echo "$res" | grep -o '"description":"[^"]*"' | head -n 1 | cut -d'"' -f4)
        fi
    done

    if [ "$any_ok" -eq 1 ]; then
        json_ok '"message":"test_message_sent"'
    else
        [ -z "$err_last" ] && err_last="Telegram API request failed"
        json_error "$err_last"
    fi
}

handle_telegram_service() {
    local op="${TYPE:-status}"
    case "$op" in
        start)
            if [ -x /etc/init.d/vcrt_bot ]; then
                /etc/init.d/vcrt_bot start >/dev/null 2>&1 || true
            else
                killall -9 vcrt_bot.sh 2>/dev/null || true
                /usr/bin/vcrt_bot.sh >/dev/null 2>&1 &
            fi
            ;;
        stop)
            if [ -x /etc/init.d/vcrt_bot ]; then
                /etc/init.d/vcrt_bot stop >/dev/null 2>&1 || true
            fi
            killall -9 vcrt_bot.sh 2>/dev/null || true
            ;;
        restart)
            if [ -x /etc/init.d/vcrt_bot ]; then
                /etc/init.d/vcrt_bot restart >/dev/null 2>&1 || true
            else
                killall -9 vcrt_bot.sh 2>/dev/null || true
                /usr/bin/vcrt_bot.sh >/dev/null 2>&1 &
            fi
            ;;
    esac

    local running="false"
    if pgrep -f vcrt_bot.sh >/dev/null 2>&1; then
        running="true"
    fi
    printf '{"status":"ok","operation":"%s","running":%s}\n' "$op" "$running"
}
