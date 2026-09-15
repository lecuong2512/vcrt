#!/bin/sh
# ==============================================================================
# VCRT OS v2.0 - CYBERPUNK TELEGRAM BOT DAEMON (24/7)
# Modular Architecture - BusyBox POSIX Shell Standard for OpenWrt
# ==============================================================================

export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# ─── ĐẢM BẢO DUY NHẤT 1 TIẾN TRÌNH BOT CHẠY NGẦM ────────────────────────────
MY_PID="$$"
for old_pid in $(pgrep -f "vcrt_bot.sh" 2>/dev/null); do
    if [ "$old_pid" != "$MY_PID" ]; then
        kill -9 "$old_pid" 2>/dev/null || true
    fi
done

# ─── NẠP CÁC THƯ VIỆN CHUNG & MODULE BOT ──────────────────────────────────────
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. Source Shared Constants (đồng bộ với CGI Backend)
if [ -f "$BASE_DIR/../backend/lib/constants.sh" ]; then
    . "$BASE_DIR/../backend/lib/constants.sh"
elif [ -f "/www/cgi-bin/lib/constants.sh" ]; then
    . "/www/cgi-bin/lib/constants.sh"
elif [ -f "/etc/vcrt/lib/constants.sh" ]; then
    . "/etc/vcrt/lib/constants.sh"
elif [ -f "$BASE_DIR/lib/constants.sh" ]; then
    . "$BASE_DIR/lib/constants.sh"
fi

# Fallback constants nếu chưa được set
: "${BLOCKS_TIMED_FILE:=/tmp/vcrt_blocks_timed.db}"
: "${BLOCKED_SOFT_FILE:=/tmp/vcrt_blocked_soft.db}"
: "${BLOCKED_HARD_FILE:=/tmp/vcrt_blocked_hard.db}"
: "${TELEGRAM_CONF:=/etc/vcrt/telegram.conf}"
: "${TRAFFIC_DAILY_DB:=/etc/vcrt/traffic_daily.db}"
: "${TRAFFIC_HOURLY_DB:=/etc/vcrt/traffic_hourly.db}"
: "${DEVICE_NAMES_FILE:=/etc/vcrt/device_names}"
: "${VERSION_FILE:=/etc/vcrt/version}"
: "${PREV_WAN_BYTES:=/tmp/vcrt_prev_wan_bytes.tmp}"
: "${NEXTDNS_CONF_FILE:=/etc/vcrt_nextdns_profile}"
: "${NEXTDNS_LINKED_IP_TMP:=/tmp/vcrt_nextdns_linked_ip.tmp}"

# 2. Source Platform Detection
if [ -f "$BASE_DIR/../backend/lib/platform.sh" ]; then
    . "$BASE_DIR/../backend/lib/platform.sh"
elif [ -f "/www/cgi-bin/lib/platform.sh" ]; then
    . "/www/cgi-bin/lib/platform.sh"
fi
command -v detect_platform >/dev/null 2>&1 && detect_platform 2>/dev/null || true

# 3. Source JSON Helper
if [ -f "$BASE_DIR/../backend/lib/json_helper.sh" ]; then
    . "$BASE_DIR/../backend/lib/json_helper.sh"
elif [ -f "/www/cgi-bin/lib/json_helper.sh" ]; then
    . "/www/cgi-bin/lib/json_helper.sh"
fi

# 4. Source Bot Specific Libraries
BOT_LIB_DIR="$BASE_DIR/lib"
[ ! -d "$BOT_LIB_DIR" ] && [ -d "/usr/lib/vcrt_bot" ] && BOT_LIB_DIR="/usr/lib/vcrt_bot"
[ ! -d "$BOT_LIB_DIR" ] && [ -d "/etc/vcrt/bot/lib" ] && BOT_LIB_DIR="/etc/vcrt/bot/lib"

if [ -f "$BOT_LIB_DIR/helpers.sh" ]; then
    . "$BOT_LIB_DIR/helpers.sh"
else
    echo "[!] Khong tim thay bot/lib/helpers.sh" >&2
fi

if [ -f "$BOT_LIB_DIR/watchers.sh" ]; then
    . "$BOT_LIB_DIR/watchers.sh"
else
    echo "[!] Khong tim thay bot/lib/watchers.sh" >&2
fi

if [ -f "$BOT_LIB_DIR/commands.sh" ]; then
    . "$BOT_LIB_DIR/commands.sh"
else
    echo "[!] Khong tim thay bot/lib/commands.sh" >&2
fi

mkdir -p /etc/vcrt /tmp 2>/dev/null || true

# ─── TỐI ƯU HÓA MẠNG: MTU 1420 & TCP MSS CLAMPING (TRÁNH RƠI GÓI TIN TLS/CURL) ──
iptables -t mangle -C OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
iptables -t mangle -A OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
for ifc in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E 'sta|wan|eth'); do
    c_mtu=$(cat "/sys/class/net/$ifc/mtu" 2>/dev/null || echo 1500)
    [ "$c_mtu" -gt 1420 ] 2>/dev/null && ip link set dev "$ifc" mtu 1420 2>/dev/null || true
done

# ─── BÀN PHÍM ĐIỀU KHIỂN TELEGRAM DƯỚI ĐÁY ───────────────────────────────────
KEYBOARD='{"keyboard":[[{"text":"/status"},{"text":"/clients"}],[{"text":"/traffic"},{"text":"/wifi"}],[{"text":"/ping"},{"text":"/speed"}],[{"text":"/nextdns"},{"text":"/help"}]],"resize_keyboard":true,"is_persistent":true}'

# ─── HÀM ĐỌC CẤU HÌNH BOT TỪ TELEGRAM.CONF ───────────────────────────────────
load_config() {
    BOT_ENABLED=0
    BOT_TOKEN=""
    CHAT_ID=""
    AUTO_UPDATE=0
    NOTIF_WIFI_JOIN=1
    NOTIF_BLOCK_EXPIRE=1
    NOTIF_DAILY_REPORT=1
    DAILY_REPORT_HOUR=20

    local conf_file="${TELEGRAM_CONF:-/etc/vcrt/telegram.conf}"

    # Di chuyển token cũ nếu chưa có cấu hình
    if [ ! -f "$conf_file" ] || ! grep -q 'BOT_TOKEN="[0-9]' "$conf_file" 2>/dev/null; then
        if [ -f /usr/bin/telegram_bot.sh ]; then
            local old_tok old_cid
            old_tok=$(grep -E 'TOKEN=' /usr/bin/telegram_bot.sh 2>/dev/null | head -n1 | cut -d= -f2- | tr -d ' "\r\n;' | sed -e 's/.*:-//' -e 's/}//')
            old_cid=$(grep -E '(ADMIN_ID|CHAT_ID)=' /usr/bin/telegram_bot.sh 2>/dev/null | head -n1 | cut -d= -f2- | tr -d ' "\r\n;' | sed -e 's/.*:-//' -e 's/}//')
            if [ -n "$old_tok" ] && [ -n "$old_cid" ]; then
                cat << EOF > "$conf_file"
BOT_ENABLED=1
BOT_TOKEN="${old_tok}"
CHAT_ID="${old_cid}"
AUTO_UPDATE=0
NOTIF_WIFI_JOIN=1
NOTIF_BLOCK_EXPIRE=1
NOTIF_DAILY_REPORT=1
DAILY_REPORT_HOUR=20
EOF
                chmod 600 "$conf_file" 2>/dev/null || true
            fi
        fi
    fi

    if [ -f "$conf_file" ]; then
        while IFS='=' read -r key val; do
            case "$key" in
                BOT_ENABLED|bot_enabled) BOT_ENABLED=$(printf '%s' "$val" | tr -d ' \r\n"') ;;
                BOT_TOKEN|bot_token) BOT_TOKEN=$(printf '%s' "$val" | tr -d ' \r\n"') ;;
                CHAT_ID|chat_id) CHAT_ID=$(printf '%s' "$val" | tr -d '\r\n"') ;;
                AUTO_UPDATE|auto_update) AUTO_UPDATE=$(printf '%s' "$val" | tr -d ' \r\n"') ;;
                NOTIF_WIFI_JOIN|notif_wifi) NOTIF_WIFI_JOIN=$(printf '%s' "$val" | tr -d ' \r\n"') ;;
                NOTIF_BLOCK_EXPIRE|notif_expire) NOTIF_BLOCK_EXPIRE=$(printf '%s' "$val" | tr -d ' \r\n"') ;;
                NOTIF_DAILY_REPORT|notif_daily) NOTIF_DAILY_REPORT=$(printf '%s' "$val" | tr -d ' \r\n"') ;;
                DAILY_REPORT_HOUR|daily_hour) DAILY_REPORT_HOUR=$(printf '%s' "$val" | tr -d ' \r\n"') ;;
            esac
        done < "$conf_file"
    fi
    BOT_TOKEN=$(printf '%s' "$BOT_TOKEN" | sed 's/%3A/:/g; s/%3a/:/g')
}

# ─── ĐĂNG KÝ BẢNG MENU LỆNH VỚI TELEGRAM (SETMYCOMMANDS) ─────────────────────
register_telegram_commands() {
    [ -z "$BOT_TOKEN" ] && return 0
    local cmd_json='{"commands":[{"command":"status","description":"⚡ Trạng thái CPU, RAM, WAN & ZeroTier"},{"command":"clients","description":"📱 Danh sách thiết bị ĐANG ONLINE"},{"command":"traffic","description":"📊 Thống kê lưu lượng mạng đã dùng"},{"command":"wifi","description":"📶 Thông số phát sóng Wi-Fi 2.4G & 5G"},{"command":"ping","description":"🏓 Kiểm tra độ trễ mạng Internet"},{"command":"speed","description":"🚀 Đo tốc độ tải về Internet"},{"command":"nextdns","description":"🛡 Trạng thái NextDNS Security"},{"command":"backup","description":"📦 Sao lưu cấu hình gửi file"},{"command":"block","description":"⛔ Chặn mạng: /block <mac> [phút]"},{"command":"unblock","description":"🔓 Mở mạng: /unblock <mac>"},{"command":"update","description":"🔄 Kiểm tra & cập nhật VCRT OS"},{"command":"reboot","description":"🔄 Khởi động lại router từ xa"},{"command":"help","description":"❓ Hướng dẫn sử dụng bot"}]}'
    curl -4 --tlsv1.2 --tls-max 1.2 -s --max-time 10 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/setMyCommands" \
        -H "Content-Type: application/json" \
        -d "$cmd_json" >/dev/null 2>&1 || true
}

# ─── KHỞI CHẠY TIẾN TRÌNH BOT ────────────────────────────────────────────────
load_config

if [ "$BOT_ENABLED" != "1" ] || [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "[!] Telegram Bot chua duoc cau hinh hoac bi tat trong $TELEGRAM_CONF"
    record_traffic_periodically &
    watch_block_timers &
    wait
    exit 0
fi

# Khởi chạy 4 Background Watchers
watch_wifi_devices &
PID_WIFI=$!
watch_block_timers &
PID_BLOCK=$!
record_traffic_periodically &
PID_TRAFFIC=$!
watch_system_updates &
PID_UPDATE=$!

cleanup() {
    kill -9 $PID_WIFI $PID_BLOCK $PID_TRAFFIC $PID_UPDATE 2>/dev/null || true
    exit 0
}
trap cleanup INT TERM EXIT

# Thông báo khởi động thành công & kèm ZeroTier IP nếu có
zt_startup_ip=$(get_zerotier_ip)
zt_intro=""
if [ -n "$zt_startup_ip" ]; then
    zt_intro="
🌐 <b>ZeroTier IP:</b> <code>${zt_startup_ip}</code> — <i>Truy cập: http://${zt_startup_ip}/vcrt/</i>"
fi

send_msg "🟢 <b>VCRT OS v2.0 - TELEGRAM BOT ĐÃ SẴN SÀNG!</b>
━━━━━━━━━━━━━━━━━━
⚡ Hệ thống giám sát thiết bị & lưu lượng 24/7 đang hoạt động.
📡 Quản lý Wi-Fi 2.4G & 5G · NextDNS Cloud · ZeroTier VPN${zt_intro}
📱 Gõ <b>/clients</b> để xem danh sách máy đang online."

register_telegram_commands

OFFSET=0

# ─── VÒNG LẶP LONG POLLING NHẬN LỆNH TELEGRAM ───────────────────────────────
while true; do
    load_config
    if [ "$BOT_ENABLED" != "1" ]; then
        echo "[*] Bot bi tat tu Web Dashboard. Dung tien trinh."
        cleanup
    fi
    API_URL="https://api.telegram.org/bot${BOT_TOKEN}"

    UPDATES=$(curl -4 --tlsv1.2 --tls-max 1.2 -s --max-time 30 "${API_URL}/getUpdates?offset=${OFFSET}&limit=1&timeout=20" 2>/dev/null || true)

    if [ -n "$UPDATES" ]; then
        UPDATE_ID=$(printf '%s' "$UPDATES" | grep -o '"update_id":[0-9]*' | head -n 1 | cut -d: -f2 | tr -d ' \r\n')
        SENDER_ID=$(printf '%s' "$UPDATES" | grep -o '"chat":{[^}]*"id":-*[0-9]*' | head -n 1 | grep -o -- '-*[0-9]*$' | tr -d ' \r\n')
        CMD_TEXT=$(printf '%s' "$UPDATES" | grep -o '"text":"[^"]*"' | head -n 1 | cut -d'"' -f4)

        if [ -n "$UPDATE_ID" ]; then
            OFFSET=$(( UPDATE_ID + 1 ))

            # Phân quyền: Kiểm tra SENDER_ID có nằm trong danh sách CHAT_ID không
            clean_sender=$(printf '%s' "$SENDER_ID" | tr -d ' \r\n')
            is_authorized=0
            for allowed_id in $(printf '%s' "$CHAT_ID" | tr ',;' ' '); do
                clean_allowed=$(printf '%s' "$allowed_id" | tr -d ' \r\n')
                if [ "$clean_sender" = "$clean_allowed" ] && [ -n "$clean_allowed" ]; then
                    is_authorized=1
                    break
                fi
            done

            if [ "$is_authorized" -eq 1 ]; then
                printf '[%s] Received cmd: %s from %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$CMD_TEXT" "$clean_sender" >> /tmp/vcrt_bot.log 2>/dev/null || true

                # 1. Làm sạch khoảng trắng và tách các từ
                clean_line=$(printf '%s' "$CMD_TEXT" | awk '{$1=$1};1')
                first_word=$(printf '%s' "$clean_line" | awk '{print $1}')
                arg1=""
                arg2=""

                case "$first_word" in
                    /*|[a-zA-Z0-9]*)
                        arg1=$(printf '%s' "$clean_line" | awk '{print $2}')
                        arg2=$(printf '%s' "$clean_line" | awk '{print $3}')
                        ;;
                    *)
                        # Bỏ qua emoji nếu người dùng bấm nút menu có kèm icon
                        first_word=$(printf '%s' "$clean_line" | awk '{print $2}')
                        arg1=$(printf '%s' "$clean_line" | awk '{print $3}')
                        arg2=$(printf '%s' "$clean_line" | awk '{print $4}')
                        ;;
                esac

                # 2. Chuẩn hóa tên lệnh: chuyển chữ thường, bỏ dấu / ở đầu, bỏ đuôi @bot_name
                cmd_name=$(printf '%s' "$first_word" | tr 'A-Z' 'a-z' | sed 's/^\///' | sed 's/@.*//')

                case "$cmd_name" in
                    status*|info*|router*|trang*|*trạng*|tt)
                        cmd_status "$SENDER_ID"
                        ;;
                    client*|device*|thiet*|*thiết*|may*|*máy*|danhsach*)
                        cmd_clients "$SENDER_ID"
                        ;;
                    traffic*|dung*|data*|luu*|*lưu*|dl)
                        cmd_traffic "$SENDER_ID"
                        ;;
                    wifi*|wi-fi*|song*|*sóng*|phat*|*phát*|wisp*)
                        cmd_wifi "$SENDER_ID"
                        ;;
                    ping*|latency*|do*|*độ*)
                        cmd_ping "$SENDER_ID"
                        ;;
                    speed*|tocdo*|*tốc*|test*)
                        cmd_speed "$SENDER_ID"
                        ;;
                    nextdns*|dns*)
                        cmd_nextdns "$SENDER_ID"
                        ;;
                    backup*|saoluu*|*sao*|luutru*)
                        cmd_backup "$SENDER_ID"
                        ;;
                    block*|chan*|*chặn*|khoa*|*khóa*)
                        cmd_block "$arg1" "$arg2" "$SENDER_ID"
                        ;;
                    unblock*|mo*|*mở*|bokhoa*)
                        cmd_unblock "$arg1" "$SENDER_ID"
                        ;;
                    update*|capnhat*|*cập*nhật*)
                        cmd_update "$arg1" "$SENDER_ID"
                        ;;
                    reboot*|restart*|reset*|khoi*|*khởi*)
                        cmd_reboot "$SENDER_ID"
                        ;;
                    logo*|bieutuong*)
                        cmd_logo "$SENDER_ID"
                        ;;
                    help*|start*|menu*|tro*|*trợ*|huong*|*hướng*|\?)
                        cmd_help "$SENDER_ID"
                        ;;
                    *)
                        cmd_unknown "$first_word" "$SENDER_ID"
                        ;;
                esac
            elif [ -n "$clean_sender" ]; then
                printf '[%s] Unauthorized message from %s (Allowed: %s)\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$clean_sender" "$CHAT_ID" >> /tmp/vcrt_bot.log 2>/dev/null || true
            fi
        fi
    fi
    sleep 1
done
