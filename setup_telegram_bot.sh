#!/bin/sh
# ==============================================================================
# CAP NHAT TELEGRAM BOT HOAN CHINH CHO XIAOMI MIWIFI MINI
# ==============================================================================

killall -9 telegram_bot.sh 2>/dev/null || true

cat << 'EOF' > /usr/bin/telegram_bot.sh
#!/bin/sh

TOKEN="${TELEGRAM_BOT_TOKEN:-YOUR_TELEGRAM_BOT_TOKEN_HERE}"
ADMIN_ID="${TELEGRAM_CHAT_ID:-YOUR_CHAT_ID_HERE}"
API_URL="https://api.telegram.org/bot${TOKEN}"

send_msg() {
    local text="$1"
    curl -s -X POST "${API_URL}/sendMessage"         -d "chat_id=${ADMIN_ID}"         -d "parse_mode=HTML"         --data-urlencode "text=${text}" >/dev/null 2>&1
}

cmd_status() {
    local host=$(cat /proc/sys/kernel/hostname 2>/dev/null || echo "MiWiFi-Mini")
    local up_sec=$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)
    local days=$((up_sec / 86400))
    local hours=$(( (up_sec % 86400) / 3600 ))
    local mins=$(( (up_sec % 3600) / 60 ))
    local up_str="${days}d ${hours}h ${mins}m"

    local load=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo "N/A")

    local mem_total=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 117)
    local mem_avail=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 80)
    local mem_used=$((mem_total - mem_avail))
    local mem_pct=$((mem_used * 100 / mem_total))

    local rom_used=$(df -h /overlay 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
    [ -z "$rom_used" ] && rom_used=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')

    local lan_ip=$(uci -q get network.lan.ipaddr 2>/dev/null || echo "192.168.10.1")
    local ext_ip=$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null || echo "Chua co Internet")

    local client_count=0
    [ -f /tmp/dhcp.leases ] && client_count=$(wc -l < /tmp/dhcp.leases 2>/dev/null || echo 0)

    local msg="📡 <b>TRẠNG THÁI ROUTER ${host}</b>
━━━━━━━━━━━━━━━━━
⏱ <b>Uptime:</b> <code>${up_str}</code>
⚙️ <b>CPU Load:</b> <code>${load}</code>
💾 <b>RAM:</b> <code>${mem_used}MB / ${mem_total}MB (${mem_pct}%)</code>
💿 <b>ROM (Flash):</b> <code>${rom_used}</code>
🏠 <b>LAN IP:</b> <code>${lan_ip}</code>
🌐 <b>Internet IP:</b> <code>${ext_ip}</code>
📱 <b>Thiết bị online:</b> <code>${client_count} máy</code>
━━━━━━━━━━━━━━━━━
<i>Gõ /clients để xem chi tiết thiết bị</i>"

    send_msg "$msg"
}

cmd_clients() {
    local msg="📱 <b>DANH SÁCH THIẾT BỊ ĐANG KẾT NỐI:</b>
━━━━━━━━━━━━━━━━━
"
    local count=0
    if [ -f /tmp/dhcp.leases ] && [ -s /tmp/dhcp.leases ]; then
        while read -r ltime mac ip name clid; do
            [ "$name" = "*" ] && name="Thiết bị không tên"
            count=$((count + 1))
            msg="${msg}${count}. <b>${name}</b>
   ├ IP: <code>${ip}</code>
   └ MAC: <code>${mac}</code>
"
        done < /tmp/dhcp.leases
    fi

    if [ "$count" -eq 0 ]; then
        msg="${msg}<i>Hiện chưa có thiết bị nào trong danh sách cấp phát DHCP.</i>"
    fi

    send_msg "$msg"
}

cmd_wifi() {
    local wifi_info="📶 <b>THÔNG TIN SÓNG WI-FI:</b>
━━━━━━━━━━━━━━━━━
"
    local ssid_2g=$(uci -q get wireless.default_radio1.ssid || echo "Xiaomi_2.4G")
    local ch_2g=$(uci -q get wireless.radio1.channel || echo "6")
    local ssid_5g=$(uci -q get wireless.default_radio0.ssid || echo "Xiaomi_5G")
    local ch_5g=$(uci -q get wireless.radio0.channel || echo "149")

    wifi_info="${wifi_info}🔹 <b>Băng tần 2.4GHz:</b>
   ├ SSID: <code>${ssid_2g}</code>
   └ Kênh: <code>${ch_2g}</code> (HT20)

"
    wifi_info="${wifi_info}🔹 <b>Băng tần 5GHz:</b>
   ├ SSID: <code>${ssid_5g}</code>
   └ Kênh: <code>${ch_5g}</code> (VHT80)
"

    send_msg "$wifi_info"
}

cmd_help() {
    local help_msg="🤖 <b>BẢNG LỆNH ĐIỀU KHIỂN ROUTER:</b>
━━━━━━━━━━━━━━━━━
/status - Xem CPU, RAM, ROM, IP, Uptime
/clients - Danh sách thiết bị đang kết nối
/wifi - Xem thông tin sóng Wi-Fi 2.4G & 5G
/ping - Kiểm tra router còn kết nối không
/reboot - Khởi động lại router từ xa
/help - Xem hướng dẫn các lệnh
━━━━━━━━━━━━━━━━━"
    send_msg "$help_msg"
}

send_msg "🚀 <b>Router MiWiFi-Mini đã sẵn sàng nhận lệnh!</b>
Hãy gõ /status hoặc /help để kiểm tra."

OFFSET=0

while true; do
    UPDATES=$(curl -s --max-time 35 "${API_URL}/getUpdates?offset=${OFFSET}&limit=1&timeout=25" 2>/dev/null || true)

    if [ -n "$UPDATES" ]; then
        # Parse update_id, chat_id, text bang Lua/jsonc
        RES=$(echo "$UPDATES" | lua -e 'local j=require("luci.jsonc"); local d=j.parse(io.read("*a")); if d and d.result and d.result[1] then local r=d.result[1]; if r.message and r.message.text then print(r.update_id); print(r.message.chat.id); print(r.message.text); end; end' 2>/dev/null || true)

        if [ -n "$RES" ]; then
            UPDATE_ID=$(echo "$RES" | sed -n '1p')
            SENDER_ID=$(echo "$RES" | sed -n '2p')
            CMD_TEXT=$(echo "$RES" | sed -n '3p')
        else
            UPDATE_ID=$(echo "$UPDATES" | grep -o '"update_id":[0-9]*' | head -n 1 | cut -d: -f2)
            SENDER_ID=$(echo "$UPDATES" | grep -o '"chat":{[^}]*"id":[0-9]*' | head -n 1 | grep -o '[0-9]*$')
            CMD_TEXT=$(echo "$UPDATES" | grep -o '"text":"[^"]*"' | head -n 1 | cut -d'"' -f4)
        fi

        if [ -n "$UPDATE_ID" ]; then
            OFFSET=$((UPDATE_ID + 1))

            if [ "$SENDER_ID" = "$ADMIN_ID" ]; then
                case "$CMD_TEXT" in
                    /status*|/info*)
                        cmd_status
                        ;;
                    /clients*|/devices*)
                        cmd_clients
                        ;;
                    /wifi*)
                        cmd_wifi
                        ;;
                    /ping*)
                        send_msg "🏓 <b>Pong!</b> Router đang phản hồi bình thường."
                        ;;
                    /reboot*)
                        send_msg "⚠️ <b>Đang khởi động lại router trong 3 giây...</b>"
                        sleep 3
                        /sbin/reboot
                        ;;
                    /help*|/start*)
                        cmd_help
                        ;;
                esac
            fi
        fi
    fi
    sleep 1
done
EOF

chmod +x /usr/bin/telegram_bot.sh

# Chay ngam truc tiep
nohup /usr/bin/telegram_bot.sh >/dev/null 2>&1 &

echo "DA CAP NHAT VA KHOI CHAY THANH CONG!"
