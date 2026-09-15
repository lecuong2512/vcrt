#!/bin/sh
# ==============================================================================
# VCRT OS v2.0 - AUTOMATED INSTALLER & MULTI-ROUTER DEPLOYMENT SCRIPT
# Tương thích BusyBox POSIX OpenWrt 21.02 / 22.03 / 23.05 / 24.10 / 25.12 (KWrt)
# ==============================================================================

set -e

echo "=================================================================="
echo "⚡ DANG CAI DAT VCRT OS v2.0 (MULTI-PLATFORM CYBER ROUTER OS)"
echo "=================================================================="

# 1. Tu dong xac dinh thu muc nguon (Source Directory)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$SCRIPT_DIR/../backend" ]; then
    ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
elif [ -d "$SCRIPT_DIR/backend" ]; then
    ROOT_DIR="$SCRIPT_DIR"
elif [ -d "/tmp/backend" ]; then
    ROOT_DIR="/tmp"
else
    ROOT_DIR="."
fi

# 2. Tao cay thu muc chuan tren router
mkdir -p /etc/vcrt \
         /www/cgi-bin/modules \
         /www/cgi-bin/lib \
         /www/cgi-bin/platforms \
         /www/vcrt \
         /tmp/vcrt_sessions \
         /etc/hotplug.d/iface 2>/dev/null || true

# 3. Nhan dien phan cung router (Auto-detect platform)
echo ">> [1/9] Tu dong nhan dien phan cung router..."
PLATFORM_DIR=""
if [ -d "$ROOT_DIR/backend/platforms" ]; then
    PLATFORM_DIR="$ROOT_DIR/backend/platforms"
elif [ -d "$ROOT_DIR/platforms" ]; then
    PLATFORM_DIR="$ROOT_DIR/platforms"
fi

if [ -f "$ROOT_DIR/backend/lib/platform.sh" ]; then
    export PLATFORM_DIR
    . "$ROOT_DIR/backend/lib/platform.sh"
    detect_platform
elif [ -f "$ROOT_DIR/lib/platform.sh" ]; then
    export PLATFORM_DIR
    . "$ROOT_DIR/lib/platform.sh"
    detect_platform
fi

board_id=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "generic")
model_id=$(cat /tmp/sysinfo/model 2>/dev/null || awk -F: '/machine/ {print $2; exit}' /proc/cpuinfo 2>/dev/null || echo "OpenWrt Router")
echo "   -> Phat hien thiet bi : ${DEVICE_NAME_DEFAULT:-$model_id}"
echo "   -> Nen tang phan cung : ${PLATFORM_ID:-generic} (${board_id})"
echo "   -> Bo nho RAM mac dinh: ${RAM_DEFAULT_TOTAL:-128} MB"
echo "   -> Chip nho Flash ROM : ${FLASH_CHIP_MB:-16} MB"
echo "   -> MediaTek HWNAT/PPE : ${HAS_HWNAT:-false}"

# 4. Xoa sach cac goi rac LuCI tieng Trung & file lmo tranh xung dot giao dien
echo ">> [2/9] Xoa bo goi ngon ngu tieng Trung va don dep LuCI..."
if command -v opkg >/dev/null 2>&1; then
    for pkg in $(opkg list-installed 2>/dev/null | grep -E 'luci-i18n-.*-zh-cn' | awk '{print $1}'); do
        opkg remove --force-depends "$pkg" >/dev/null 2>&1 || true
    done
fi
rm -rf /usr/lib/lua/luci/i18n/*zh-cn* \
       /www/luci-static/resources/i18n/*zh-cn* \
       /tmp/luci-indexcache \
       /tmp/luci-modulecache \
       /tmp/luci-* 2>/dev/null || true

uci -q set luci.main.lang='en' && uci -q commit luci 2>/dev/null || true
sed -i 's/后台地址/Router_Admin/g' /etc/config/dhcp 2>/dev/null || true

# 5. Tu dong bao luu Token Telegram Bot cu neu co
echo ">> [3/9] Kiem tra va dong bo cau hinh Telegram Bot..."
CONF_FILE="/etc/vcrt/telegram.conf"
if [ ! -f "$CONF_FILE" ] || ! grep -q 'BOT_TOKEN="[0-9]' "$CONF_FILE" 2>/dev/null; then
    old_tok=""
    old_cid=""
    for f_cand in "$ROOT_DIR/telegram.conf.example" /tmp/telegram.conf.example; do
        [ -f "$f_cand" ] && cp -f "$f_cand" "$CONF_FILE" 2>/dev/null || true
    done
    for f_cand in /usr/bin/telegram_bot.sh /etc/init.d/telegram-bot /etc/telegram_bot.conf /etc/config/telegram /etc/rc.local; do
        [ ! -f "$f_cand" ] && continue
        [ -z "$old_tok" ] && old_tok=$(grep -E 'TOKEN=' "$f_cand" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d ' "\r\n;' | sed -e 's/.*:-//' -e 's/}//')
        [ -z "$old_cid" ] && old_cid=$(grep -E '(ADMIN_ID|CHAT_ID)=' "$f_cand" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d ' "\r\n;' | sed -e 's/.*:-//' -e 's/}//')
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
        echo "   -> Da bao luu Token va Chat ID Telegram cu thanh cong."
    fi
fi

# Dung moi service bot cu de tranh xung dot tien trinh
/etc/init.d/telegram-bot stop 2>/dev/null || true
/etc/init.d/telegram-bot disable 2>/dev/null || true
rm -f /etc/init.d/telegram-bot /etc/rc.d/*telegram-bot* /usr/bin/telegram_bot.sh 2>/dev/null || true
killall -9 telegram_bot.sh 2>/dev/null || true
sed -i '/telegram_bot/d' /etc/rc.local 2>/dev/null || true

# 6. Deploy Backend API, Modules, Libraries va Platform Adapters
echo ">> [4/9] Cai dat Backend VCRT CGI, Modules & Platform Adapters..."

# 6.1 Version
if [ -f "$ROOT_DIR/version" ]; then
    cp -f "$ROOT_DIR/version" /etc/vcrt/version
else
    echo "2.0.0" > /etc/vcrt/version
fi

# 6.2 Main CGI Script
if [ -f "$ROOT_DIR/backend/vcrt_cgi.sh" ]; then
    cp -f "$ROOT_DIR/backend/vcrt_cgi.sh" /www/cgi-bin/vcrt
elif [ -f "$ROOT_DIR/vcrt_cgi.sh" ]; then
    cp -f "$ROOT_DIR/vcrt_cgi.sh" /www/cgi-bin/vcrt
elif [ -f "$ROOT_DIR/vcrt" ]; then
    cp -f "$ROOT_DIR/vcrt" /www/cgi-bin/vcrt
fi

# 6.3 Libraries
if [ -d "$ROOT_DIR/backend/lib" ]; then
    cp -rf "$ROOT_DIR/backend/lib/"* /www/cgi-bin/lib/ 2>/dev/null || true
elif [ -d "$ROOT_DIR/lib" ]; then
    cp -rf "$ROOT_DIR/lib/"* /www/cgi-bin/lib/ 2>/dev/null || true
fi

# 6.4 Modules
if [ -d "$ROOT_DIR/backend/modules" ]; then
    cp -rf "$ROOT_DIR/backend/modules/"* /www/cgi-bin/modules/ 2>/dev/null || true
elif [ -d "$ROOT_DIR/modules" ]; then
    cp -rf "$ROOT_DIR/modules/"* /www/cgi-bin/modules/ 2>/dev/null || true
fi

# 6.5 Platforms
if [ -d "$ROOT_DIR/backend/platforms" ]; then
    cp -rf "$ROOT_DIR/backend/platforms/"* /www/cgi-bin/platforms/ 2>/dev/null || true
elif [ -d "$ROOT_DIR/platforms" ]; then
    cp -rf "$ROOT_DIR/platforms/"* /www/cgi-bin/platforms/ 2>/dev/null || true
fi

# 7. Deploy Frontend Web UI
echo ">> [5/9] Cai dat giao dien Web VCRT UI v2.0..."
web_src=""
if [ -d "$ROOT_DIR/web/dist" ]; then
    web_src="$ROOT_DIR/web/dist"
elif [ -d "$ROOT_DIR/Des/dist" ]; then
    web_src="$ROOT_DIR/Des/dist"
elif [ -d "$ROOT_DIR/www/vcrt" ]; then
    web_src="$ROOT_DIR/www/vcrt"
fi

if [ -n "$web_src" ]; then
    rm -rf /www/vcrt/* 2>/dev/null || true
    cp -rf "$web_src/"* /www/vcrt/
    echo "   -> Da cap nhat Web UI tai /www/vcrt/ tu $web_src"
fi

# 8. Deploy Telegram Bot Daemon & procd init
# 8. Deploy Telegram Bot Daemon & procd init
echo ">> [6/9] Cai dat VCRT Telegram Bot Daemon & procd service..."
mkdir -p /usr/lib/vcrt_bot 2>/dev/null || true
if [ -d "$ROOT_DIR/bot/lib" ]; then
    cp -rf "$ROOT_DIR/bot/lib/"* /usr/lib/vcrt_bot/ 2>/dev/null || true
fi

if [ -f "$ROOT_DIR/bot/vcrt_bot.sh" ]; then
    cp -f "$ROOT_DIR/bot/vcrt_bot.sh" /usr/bin/vcrt_bot.sh
    chmod +x /usr/bin/vcrt_bot.sh
elif [ -f "$ROOT_DIR/vcrt_bot.sh" ]; then
    cp -f "$ROOT_DIR/vcrt_bot.sh" /usr/bin/vcrt_bot.sh
    chmod +x /usr/bin/vcrt_bot.sh
fi

if [ -f "$ROOT_DIR/bot/vcrt_bot_init" ]; then
    cp -f "$ROOT_DIR/bot/vcrt_bot_init" /etc/init.d/vcrt_bot
elif [ -f "$ROOT_DIR/vcrt_bot_init" ]; then
    cp -f "$ROOT_DIR/vcrt_bot_init" /etc/init.d/vcrt_bot
elif [ -f "$ROOT_DIR/vcrt_bot" ]; then
    cp -f "$ROOT_DIR/vcrt_bot" /etc/init.d/vcrt_bot
fi

if [ -f /etc/init.d/vcrt_bot ]; then
    chmod +x /etc/init.d/vcrt_bot
    /etc/init.d/vcrt_bot enable 2>/dev/null || true
    /etc/init.d/vcrt_bot restart 2>/dev/null || true
fi

# 9. Cau hinh Ten mien Cuc bo (DNS Local: vcrt.lan)
echo ">> [7/9] Cau hinh ten mien noi bo vcrt.lan..."
lan_ip=$(uci -q get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1")
uci -q del_list dhcp.@dnsmasq[0].address="/vcrt.lan/$lan_ip" 2>/dev/null || true
# Kiem tra tranh ghi trung lap
if ! uci -q get dhcp.@dnsmasq[0].address 2>/dev/null | grep -q "/vcrt.lan/"; then
    uci add_list dhcp.@dnsmasq[0].address="/vcrt.lan/$lan_ip"
    uci commit dhcp 2>/dev/null || true
fi

# 10. Cai dat & Khoi chay ZeroTier VPN (neu chua co)
echo ">> [8/9] Thiet lap dich vu ZeroTier ket noi tu xa..."
if ! command -v zerotier-cli >/dev/null 2>&1; then
    echo "   -> Dang cai dat zerotier package..."
    opkg update >/dev/null 2>&1 || true
    opkg install zerotier 2>/dev/null || echo "   -> Luu y: Khong the tai zerotier tu opkg (co the bo qua neu chi dung cuc bo)."
fi
if [ -f /etc/init.d/zerotier ]; then
    /etc/init.d/zerotier enable 2>/dev/null || true
    /etc/init.d/zerotier start 2>/dev/null || true
fi

# 11. MTU Fix Hotplug Script (TCP MSS Clamping chong nghen WISP / 4G)
cat << 'EOF' > /etc/hotplug.d/iface/99-mtu-fix
#!/bin/sh
iptables -t mangle -C OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
iptables -t mangle -A OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
for ifc in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E 'sta|wan|eth|usb'); do
    c_mtu=$(cat /sys/class/net/$ifc/mtu 2>/dev/null || echo 1500)
    [ "$c_mtu" -gt 1420 ] 2>/dev/null && ip link set dev "$ifc" mtu 1420 2>/dev/null || true
done
EOF
chmod +x /etc/hotplug.d/iface/99-mtu-fix 2>/dev/null || true
sh /etc/hotplug.d/iface/99-mtu-fix 2>/dev/null || true

# 12. Phan quyen thuc thi toan dien
echo ">> [9/9] Hoan tat phan quyen va khoi dong lai dich vu..."
chmod +x /www/cgi-bin/vcrt \
         /www/cgi-bin/lib/*.sh \
         /www/cgi-bin/modules/*.sh \
         /www/cgi-bin/platforms/*.sh \
         /usr/bin/vcrt_bot.sh 2>/dev/null || true

# Don dep tap tin tam sau cai dat
rm -rf /tmp/vcrt /tmp/vcrt_bot /tmp/vcrt_bot.sh /tmp/www /tmp/deploy_vcrt.tar.gz 2>/dev/null || true

# Restart network services
/etc/init.d/dnsmasq restart 2>/dev/null || true
/etc/init.d/firewall restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true

echo "=================================================================="
echo "🎉 VCRT OS v2.0 DA DUOC CAI DAT VA KHOI CHAY THANH CONG!"
echo "   - Web Dashboard: http://${lan_ip}/vcrt/ hoac http://vcrt.lan/vcrt/"
echo "   - API Endpoint : http://${lan_ip}/cgi-bin/vcrt"
echo "=================================================================="

# 13. Gui thong bao Telegram neu da cau hinh
KEYBOARD='{"keyboard":[[{"text":"/status"},{"text":"/clients"}],[{"text":"/traffic"},{"text":"/wifi"}],[{"text":"/ping"},{"text":"/help"}]],"resize_keyboard":true,"is_persistent":true}'
if [ -f "$CONF_FILE" ]; then
    . "$CONF_FILE" 2>/dev/null || true
    BOT_TOKEN=$(echo "$BOT_TOKEN" | sed 's/%3A/:/g; s/%3a/:/g')
    if [ "$BOT_ENABLED" = "1" ] && [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ]; then
        for cid in $(echo "$CHAT_ID" | tr ',;' ' '); do
            clean_cid=$(echo "$cid" | tr -d ' \r\n')
            [ -z "$clean_cid" ] && continue
            curl -4 --tlsv1.2 --tls-max 1.2 -s --max-time 8 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                --data-urlencode "chat_id=${clean_cid}" \
                --data-urlencode "parse_mode=HTML" \
                --data-urlencode "reply_markup=${KEYBOARD}" \
                --data-urlencode "text=🚀 <b>VCRT OS v2.0 - TRIỂN KHAI HOÀN TẤT!</b>
━━━━━━━━━━━━━━━━━━
⬡ <b>Thiết bị:</b> ${DEVICE_NAME_DEFAULT:-$model_id}
⬡ <b>Nền tảng:</b> ${PLATFORM_ID:-generic}
⬡ <b>IP Quản trị:</b> http://${lan_ip} (hoặc http://vcrt.lan)
📱 <i>Bot Telegram v2.0 sẵn sàng phục vụ! Gõ /help để bắt đầu.</i>" >/dev/null 2>&1 || true
        done
        echo ">> Da gui thong bao he thong den Telegram cua ban!"
    fi
fi

exit 0
