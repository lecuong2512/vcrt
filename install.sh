#!/bin/sh
# ==============================================================================
# VCRT OS v1.0.0 - AUTOMATED INSTALLER & MIGRATION SCRIPT
# ==============================================================================

echo "=================================================="
echo "⚡ DANG CAI DAT VCRT OS v1.0.0 & TELEGRAM DAEMON"
echo "=================================================="

# 1. Tao thu muc can thiet
mkdir -p /etc/vcrt /www/cgi-bin /www/vcrt /tmp 2>/dev/null

# 2. Tu dong bao luu / di chuyen Token tu telegram bot cu neu co
CONF_FILE="/etc/vcrt/telegram.conf"
if [ ! -f "$CONF_FILE" ] || ! grep -q 'BOT_TOKEN="[0-9]' "$CONF_FILE" 2>/dev/null; then
    [ -f telegram.conf.example ] && cp -f telegram.conf.example "$CONF_FILE"
    old_tok=""
    old_cid=""
    for f_cand in /usr/bin/telegram_bot.sh /etc/init.d/telegram-bot /etc/telegram_bot.conf /etc/config/telegram /etc/rc.local; do
        [ ! -f "$f_cand" ] && continue
        if [ -z "$old_tok" ]; then
            old_tok=$(grep -E 'TOKEN=' "$f_cand" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d ' "\r\n;' | sed -e 's/.*:-//' -e 's/}//')
        fi
        if [ -z "$old_cid" ]; then
            old_cid=$(grep -E '(ADMIN_ID|CHAT_ID)=' "$f_cand" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d ' "\r\n;' | sed -e 's/.*:-//' -e 's/}//')
        fi
    done
    if [ -n "$old_tok" ] && [ "$old_tok" != "YOUR_TELEGRAM_BOT_TOKEN_HERE" ]; then
        cat << EOF > "$CONF_FILE"
BOT_ENABLED=1
BOT_TOKEN="${old_tok}"
CHAT_ID="${old_cid}"
NOTIF_WIFI_JOIN=1
NOTIF_BLOCK_EXPIRE=1
NOTIF_DAILY_REPORT=1
DAILY_REPORT_HOUR=20
EOF
        echo ">> Tu dong di chuyen & bao luu Token va Chat ID cu thanh cong!"
    fi
fi

# 3. Huy bo va go bo triet de toan bo bot cu de tranh xung dot
echo ">> Dang kiem tra va go bo moi ban bot cu..."
/etc/init.d/telegram-bot stop 2>/dev/null || true
/etc/init.d/telegram-bot disable 2>/dev/null || true
rm -f /etc/init.d/telegram-bot /etc/rc.d/*telegram-bot* 2>/dev/null || true

/etc/init.d/vcrt_bot stop 2>/dev/null || true
killall -9 telegram_bot.sh vcrt_bot.sh 2>/dev/null || true
pgrep -f 'telegram_bot' | xargs kill -9 2>/dev/null || true
pgrep -f 'vcrt_bot' | xargs kill -9 2>/dev/null || true
rm -f /usr/bin/telegram_bot.sh 2>/dev/null || true
sed -i '/telegram_bot/d' /etc/rc.local 2>/dev/null || true

# 4. Chep Version file
if [ -f version ]; then
    cp -f version /etc/vcrt/version
    echo ">> Da cap nhat phien ban: $(cat /etc/vcrt/version)"
fi

# 5. Chep CGI Backend
if [ -f vcrt ]; then
    cp -f vcrt /www/cgi-bin/vcrt
    chmod +x /www/cgi-bin/vcrt
    echo ">> Da cap nhat CGI API: /www/cgi-bin/vcrt"
fi

# 6. Chep Telegram Bot Daemon & Init Service
if [ -f vcrt_bot.sh ]; then
    cp -f vcrt_bot.sh /usr/bin/vcrt_bot.sh
    chmod +x /usr/bin/vcrt_bot.sh
    echo ">> Da cap nhat Bot Daemon: /usr/bin/vcrt_bot.sh"
fi

if [ -f vcrt_bot ]; then
    cp -f vcrt_bot /etc/init.d/vcrt_bot
    chmod +x /etc/init.d/vcrt_bot
    /etc/init.d/vcrt_bot enable 2>/dev/null || true
    /etc/init.d/vcrt_bot restart 2>/dev/null || true
    echo ">> Da khoi dong lai dich vu vcrt_bot qua procd"
fi

# 7. Chep Web UI
if [ -d www/vcrt ]; then
    rm -rf /www/vcrt/* 2>/dev/null || true
    cp -rf www/vcrt/* /www/vcrt/
    echo ">> Da cap nhat giao dien Web Dashboard v1.0.0"
fi

# 8. Don dep tep tam
rm -rf /tmp/vcrt /tmp/vcrt_bot* /tmp/www /tmp/telegram.conf.example /tmp/deploy_vcrt.tar.gz /tmp/install.sh /tmp/version 2>/dev/null || true

echo "=================================================="
echo "🎉 VCRT OS v1.0.0 DEPLOY SUCCESSFUL!"
echo "=================================================="

# 9. Gui thong bao tuc thi len Telegram Bot (Tat ca Chat ID / Nhom)
KEYBOARD='{"keyboard":[[{"text":"/status"},{"text":"/clients"}],[{"text":"/traffic"},{"text":"/wifi"}],[{"text":"/ping"},{"text":"/help"}]],"resize_keyboard":true,"is_persistent":true}'

if [ -f "$CONF_FILE" ]; then
    . "$CONF_FILE" 2>/dev/null || true
    if [ "$BOT_ENABLED" = "1" ] && [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ]; then
        for cid in $(echo "$CHAT_ID" | tr ',;' ' '); do
            [ -z "$cid" ] && continue
            curl -s --max-time 8 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                -d "chat_id=${cid}" \
                -d "parse_mode=HTML" \
                -d "reply_markup=${KEYBOARD}" \
                --data-urlencode "text=🚀 <b>VCRT OS v1.0.0 - CẬP NHẬT THÀNH CÔNG!</b>
━━━━━━━━━━━━━━━━━━
⬡ <b>VCRT OS CYBER ROUTER ĐÃ SẴN SÀNG!</b>
🤖 Bot đã nạp bản mới, hỗ trợ nhóm và hiển thị ẩn danh IP/MAC độc lập.
📱 Bấm <b>/clients</b> để xem danh sách máy đang trực tuyến." >/dev/null 2>&1 || true
        done
        echo ">> Da gui thong bao 'Bot da san sang' den Telegram cua ban!"
    else
        echo ">> Luu y: Telegram Bot chua bat hoac chua co Token. Hay vao Web VCRT -> Cai dat de nhap Token."
    fi
fi
