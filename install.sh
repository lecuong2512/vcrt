#!/bin/sh
# ==============================================================================
# VCRT OS v1.0.0 - AUTOMATED INSTALLER & MIGRATION SCRIPT
# ==============================================================================

echo "=================================================="
echo "⚡ DANG CAI DAT VCRT OS v1.0.0 & TELEGRAM DAEMON"
echo "=================================================="

# 1. Tao thu muc can thiet
mkdir -p /etc/vcrt /www/cgi-bin /www/vcrt /tmp 2>/dev/null

# 2. Tu dong di chuyen Token tu telegram_bot.sh cu neu co
CONF_FILE="/etc/vcrt/telegram.conf"
if [ ! -f "$CONF_FILE" ] || ! grep -q 'BOT_TOKEN="[0-9]' "$CONF_FILE" 2>/dev/null; then
    [ -f telegram.conf.example ] && cp -f telegram.conf.example "$CONF_FILE"
    if [ -f /usr/bin/telegram_bot.sh ]; then
        echo ">> Phat hien cau hinh Telegram Bot cu, dang tu dong dong bo..."
        old_tok=$(grep -E 'TOKEN=' /usr/bin/telegram_bot.sh 2>/dev/null | head -n1 | cut -d= -f2- | tr -d ' "\r\n;' | sed -e 's/.*:-//' -e 's/}//')
        old_cid=$(grep -E '(ADMIN_ID|CHAT_ID)=' /usr/bin/telegram_bot.sh 2>/dev/null | head -n1 | cut -d= -f2- | tr -d ' "\r\n;' | sed -e 's/.*:-//' -e 's/}//')
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
            echo ">> Dong bo Token va Chat ID thanh cong!"
        fi
    fi
fi

# 3. Huy bo toan bo bot cu de tranh xung dot
killall -9 telegram_bot.sh vcrt_bot.sh 2>/dev/null || true
rm -f /usr/bin/telegram_bot.sh 2>/dev/null || true
sed -i '/telegram_bot\.sh/d' /etc/rc.local 2>/dev/null || true

# 4. Chep CGI Backend
if [ -f vcrt ]; then
    cp -f vcrt /www/cgi-bin/vcrt
    chmod +x /www/cgi-bin/vcrt
    echo ">> Da cap nhat CGI API: /www/cgi-bin/vcrt"
fi

# 5. Chep Telegram Bot Daemon & Init Service
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

# 6. Chep Web UI
if [ -d www/vcrt ]; then
    rm -rf /www/vcrt/* 2>/dev/null || true
    cp -rf www/vcrt/* /www/vcrt/
    echo ">> Da cap nhat giao dien Web Dashboard v1.0.0"
fi

# 7. Don dep tep tam
rm -rf /tmp/vcrt /tmp/vcrt_bot* /tmp/www /tmp/telegram.conf.example /tmp/deploy_vcrt.tar.gz /tmp/install.sh 2>/dev/null || true

echo "=================================================="
echo "🎉 VCRT OS v1.0.0 DEPLOY SUCCESSFUL!"
echo "=================================================="

# 8. Gui thong bao tuc thi len Telegram Bot
KEYBOARD='{"keyboard":[[{"text":"/status"},{"text":"/clients"}],[{"text":"/traffic"},{"text":"/wifi"}],[{"text":"/ping"},{"text":"/help"}]],"resize_keyboard":true,"persistent":true}'

if [ -f "$CONF_FILE" ]; then
    . "$CONF_FILE" 2>/dev/null || true
    if [ "$BOT_ENABLED" = "1" ] && [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ]; then
        curl -s --max-time 8 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            -d "chat_id=${CHAT_ID}" \
            -d "parse_mode=HTML" \
            -d "reply_markup=${KEYBOARD}" \
            --data-urlencode "text=🚀 <b>VCRT OS v1.0.0 - CẬP NHẬT THÀNH CÔNG!</b>
━━━━━━━━━━━━━━━━━━
🤖 <b>Telegram Bot đã sẵn sàng nhận lệnh!</b>
⏱ Hệ thống giám sát 24/7 đang hoạt động.
Bấm <b>/clients</b> hoặc nút bên dưới để xem danh sách máy online kèm băng tần và thời gian bắt sóng." >/dev/null 2>&1 || true
        echo ">> Da gui thong bao 'Bot da san sang' den Telegram cua ban!"
    else
        echo ">> Luu y: Telegram Bot chua bat hoac chua co Token. Hay vao Web VCRT -> Cai dat de nhap Token."
    fi
fi
