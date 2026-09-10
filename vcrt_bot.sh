#!/bin/sh
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
# ==============================================================================
# VCRT OS - BACKGROUND TELEGRAM BOT & NOTIFICATION DAEMON
# Tự động thông báo thiết bị mới, hết hạn chặn mạng, lưu lượng định kỳ
# Hoạt động 24/7 trên OpenWrt độc lập, không phụ thuộc vào Web Dashboard
# ==============================================================================

VCRT_CONF_DIR="${VCRT_CONF_DIR:-/etc/vcrt}"
CONF_FILE="${VCRT_CONF_DIR}/telegram.conf"
TIMED_BLOCKS_FILE="/tmp/vcrt_blocks_timed.db"
BLOCKED_SOFT_FILE="/tmp/vcrt_blocked_soft.txt"
BLOCKED_HARD_FILE="/tmp/vcrt_blocked_hard.txt"
DAILY_DB="${VCRT_CONF_DIR}/traffic_daily.db"
HOURLY_DB="${VCRT_CONF_DIR}/traffic_hourly.db"
PREV_BYTES_FILE="/tmp/vcrt_prev_wan_bytes.tmp"
REPORTED_DATE_FILE="/tmp/vcrt_reported_date.tmp"

mkdir -p "$VCRT_CONF_DIR" /tmp 2>/dev/null

load_config() {
    BOT_ENABLED=0
    BOT_TOKEN=""
    CHAT_ID=""
    NOTIF_WIFI_JOIN=1
    NOTIF_BLOCK_EXPIRE=1
    NOTIF_DAILY_REPORT=1
    DAILY_REPORT_HOUR=20

    if [ -f "$CONF_FILE" ]; then
        # POSIX safe key-value parsing
        while IFS='=' read -r key val; do
            case "$key" in
                BOT_ENABLED|bot_enabled) BOT_ENABLED=$(echo "$val" | tr -d ' \r\n"') ;;
                BOT_TOKEN|bot_token) BOT_TOKEN=$(echo "$val" | tr -d ' \r\n"') ;;
                CHAT_ID|chat_id) CHAT_ID=$(echo "$val" | tr -d ' \r\n"') ;;
                NOTIF_WIFI_JOIN|notif_wifi) NOTIF_WIFI_JOIN=$(echo "$val" | tr -d ' \r\n"') ;;
                NOTIF_BLOCK_EXPIRE|notif_expire) NOTIF_BLOCK_EXPIRE=$(echo "$val" | tr -d ' \r\n"') ;;
                NOTIF_DAILY_REPORT|notif_daily) NOTIF_DAILY_REPORT=$(echo "$val" | tr -d ' \r\n"') ;;
                DAILY_REPORT_HOUR|daily_hour) DAILY_REPORT_HOUR=$(echo "$val" | tr -d ' \r\n"') ;;
            esac
        done < "$CONF_FILE"
    fi
}

send_msg() {
    local text="$1"
    [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ] && return 1
    local api_url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
    curl -s --max-time 10 -X POST "$api_url" \
        -d "chat_id=${CHAT_ID}" \
        -d "parse_mode=HTML" \
        --data-urlencode "text=${text}" >/dev/null 2>&1 || true
}

# ─── WATCHER 1: THEO DÕI THIẾT BỊ WI-FI MỚI (LIVE) ───────────────────────────
watch_wifi_devices() {
    local last_macs=""
    while true; do
        sleep 3
        load_config
        [ "$BOT_ENABLED" != "1" ] && continue
        [ "$NOTIF_WIFI_JOIN" != "1" ] && continue
        [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ] && continue

        # Quét MAC các máy đang liên kết sóng Wi-Fi thực tế
        local curr_macs=""
        for wif in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do
            case "$wif" in *sta*) continue ;; esac
            local stas=$(iw dev "$wif" station dump 2>/dev/null | awk '/Station/{print tolower($2)}')
            [ -n "$stas" ] && curr_macs="${curr_macs} ${stas}"
        done
        curr_macs=$(echo "$curr_macs" | tr ' ' '\n' | grep -E '^[0-9a-f]{2}:' | sort -u)

        if [ -n "$last_macs" ]; then
            for m in $curr_macs; do
                if ! echo "$last_macs" | grep -qi "$m"; then
                    # Thiết bị mới xuất hiện! Đợi 1 giây để DHCP cấp IP
                    sleep 1
                    local mac_up=$(echo "$m" | tr '[:lower:]' '[:upper:]')
                    local ip=$(awk -v mac="$m" 'tolower($2)==tolower(mac) {print $3}' /tmp/dhcp.leases 2>/dev/null | head -n 1)
                    local name=$(awk -v mac="$m" 'tolower($2)==tolower(mac) {print $4}' /tmp/dhcp.leases 2>/dev/null | head -n 1)
                    [ -z "$ip" ] && ip=$(awk -v mac="$m" 'tolower($4)==tolower(mac) {print $1}' /proc/net/arp 2>/dev/null | head -n 1)
                    [ -z "$ip" ] && ip="Đang nhận IP..."
                    [ "$name" = "*" ] || [ -z "$name" ] && name="Thiết bị không tên"

                    local band="Wi-Fi"
                    if iw dev phy0-ap0 station dump 2>/dev/null | grep -qi "$m"; then
                        band="Wi-Fi 5GHz ⚡ (Tốc độ cao)"
                    elif iw dev phy1-ap0 station dump 2>/dev/null | grep -qi "$m"; then
                        band="Wi-Fi 2.4GHz 📶 (Xuyên tường)"
                    fi

                    local now_str=$(date +'%H:%M:%S - %d/%m/%Y' 2>/dev/null || echo "")
                    local alert_msg="🔔 <b>THIẾT BỊ MỚI KẾT NỐI WI-FI!</b>
━━━━━━━━━━━━━━━━━
📱 <b>Tên máy:</b> <code>${name}</code>
📍 <b>Địa chỉ IP:</b> <code>${ip}</code>
🔑 <b>Địa chỉ MAC:</b> <code>${mac_up}</code>
📡 <b>Băng tần:</b> <code>${band}</code>
⏰ <b>Thời gian:</b> <code>${now_str}</code>
━━━━━━━━━━━━━━━━━
<i>Thông báo tự động từ router VCRT OS</i>"
                    send_msg "$alert_msg"
                fi
            done
        fi
        last_macs="$curr_macs"
    done
}

# ─── WATCHER 2: THEO DÕI HẾT HẠN CHẶN MẠNG (ĐẾM NGƯỢC TỰ ĐỘNG) ──────────────
watch_block_timers() {
    while true; do
        sleep 2
        [ ! -f "$TIMED_BLOCKS_FILE" ] && continue

        local now_epoch=$(date +%s 2>/dev/null || echo 0)
        [ "$now_epoch" -eq 0 ] && continue

        local need_update=0
        local temp_file="/tmp/vcrt_blocks_timed.tmp"
        : > "$temp_file"

        while IFS='|' read -r b_mac b_type b_start b_expire b_dur b_name b_ip; do
            [ -z "$b_mac" ] && continue
            if [ "$b_expire" -gt 0 ] && [ "$now_epoch" -ge "$b_expire" ] 2>/dev/null; then
                # HẾT GIỜ: Tự động gỡ bỏ chặn trong Firewall iptables
                iptables -D FORWARD -m mac --mac-source "$b_mac" -j DROP 2>/dev/null || true
                iptables -D INPUT -m mac --mac-source "$b_mac" -j DROP 2>/dev/null || true
                grep -v -i "$b_mac" "$BLOCKED_SOFT_FILE" > "${BLOCKED_SOFT_FILE}.tmp" 2>/dev/null || true
                mv "${BLOCKED_SOFT_FILE}.tmp" "$BLOCKED_SOFT_FILE" 2>/dev/null || true
                grep -v -i "$b_mac" "$BLOCKED_HARD_FILE" > "${BLOCKED_HARD_FILE}.tmp" 2>/dev/null || true
                mv "${BLOCKED_HARD_FILE}.tmp" "$BLOCKED_HARD_FILE" 2>/dev/null || true
                need_update=1

                load_config
                if [ "$BOT_ENABLED" = "1" ] && [ "$NOTIF_BLOCK_EXPIRE" = "1" ]; then
                    [ -z "$b_name" ] && b_name="Thiết bị"
                    local unblock_msg="🎉 <b>ĐÃ HẾT GIỜ NGẮT KẾT NỐI!</b>
━━━━━━━━━━━━━━━━━
📱 <b>Thiết bị:</b> <code>${b_name}</code>
📍 <b>Địa chỉ IP:</b> <code>${b_ip}</code>
🔑 <b>Địa chỉ MAC:</b> <code>${b_mac}</code>
━━━━━━━━━━━━━━━━━
<i>Router đã tự động khôi phục toàn bộ quyền truy cập Internet!</i>"
                    send_msg "$unblock_msg"
                fi
            else
                echo "${b_mac}|${b_type}|${b_start}|${b_expire}|${b_dur}|${b_name}|${b_ip}" >> "$temp_file"
            fi
        done < "$TIMED_BLOCKS_FILE"

        if [ "$need_update" -eq 1 ]; then
            mv -f "$temp_file" "$TIMED_BLOCKS_FILE" 2>/dev/null || true
        else
            rm -f "$temp_file" 2>/dev/null || true
        fi
    done
}

# ─── WATCHER 3: TÍCH LŨY LƯU LƯỢNG NGẦM (24/7 BACKGROUND RECORDER) ───────────
record_traffic_periodically() {
    while true; do
        sleep 60
        # Tìm cổng mạng WAN chính
        local def_dev=$(ip route 2>/dev/null | awk '/^default/{print $5}' | head -n 1)
        [ -z "$def_dev" ] && def_dev=$(route -n 2>/dev/null | awk '/^0.0.0.0/{print $8}' | head -n 1)
        [ -z "$def_dev" ] && def_dev="eth0.2"

        local cur_rx=0
        local cur_tx=0
        if [ -n "$def_dev" ] && grep -q "${def_dev}:" /proc/net/dev 2>/dev/null; then
            cur_rx=$(awk -v ifn="${def_dev}:" '$1==ifn {print $2}' /proc/net/dev 2>/dev/null || echo 0)
            cur_tx=$(awk -v ifn="${def_dev}:" '$1==ifn {print $10}' /proc/net/dev 2>/dev/null || echo 0)
        fi
        [ "$cur_rx" -eq 0 ] 2>/dev/null && cur_rx=$(cat /sys/class/net/eth0/statistics/rx_bytes 2>/dev/null || echo 0)
        [ "$cur_tx" -eq 0 ] 2>/dev/null && cur_tx=$(cat /sys/class/net/eth0/statistics/tx_bytes 2>/dev/null || echo 0)

        case "$cur_rx" in ''|*[!0-9]*) cur_rx=0 ;; esac
        case "$cur_tx" in ''|*[!0-9]*) cur_tx=0 ;; esac

        local today_date=$(date +%Y-%m-%d 2>/dev/null || echo "2026-09-10")
        local today_hour=$(date +%H 2>/dev/null || echo "15")

        local delta_rx=0
        local delta_tx=0
        if [ -f "$PREV_BYTES_FILE" ]; then
            read -r p_rx p_tx < "$PREV_BYTES_FILE" 2>/dev/null
            case "$p_rx" in ''|*[!0-9]*) p_rx=0 ;; esac
            case "$p_tx" in ''|*[!0-9]*) p_tx=0 ;; esac
            if [ "$cur_rx" -ge "$p_rx" ] 2>/dev/null; then
                delta_rx=$(( cur_rx - p_rx ))
                delta_tx=$(( cur_tx - p_tx ))
            else
                delta_rx="$cur_rx"
                delta_tx="$cur_tx"
            fi
        else
            if ! grep -q "^${today_date}|" "$DAILY_DB" 2>/dev/null; then
                delta_rx="$cur_rx"
                delta_tx="$cur_tx"
            fi
        fi
        echo "$cur_rx $cur_tx" > "$PREV_BYTES_FILE" 2>/dev/null

        if [ "$delta_rx" -gt 0 ] 2>/dev/null || [ "$delta_tx" -gt 0 ] 2>/dev/null; then
            # 1. Cập nhật daily_db
            if grep -q "^${today_date}|" "$DAILY_DB" 2>/dev/null; then
                awk -F'|' -v cur_d="$today_date" -v drx="$delta_rx" -v dtx="$delta_tx" '
                $1 == cur_d { printf "%s|%d|%d\n", $1, $2 + drx, $3 + dtx; next; }
                { print $0; }
                ' "$DAILY_DB" > "${DAILY_DB}.tmp" 2>/dev/null && mv -f "${DAILY_DB}.tmp" "$DAILY_DB"
            else
                echo "${today_date}|${delta_rx}|${delta_tx}" >> "$DAILY_DB" 2>/dev/null
            fi

            # 2. Cập nhật hourly_db
            local cur_h_key="${today_date} ${today_hour}"
            if grep -q "^${cur_h_key}|" "$HOURLY_DB" 2>/dev/null; then
                awk -F'[ |]' -v cur_k="$cur_h_key" -v drx="$delta_rx" -v dtx="$delta_tx" '
                ($1 " " $2) == cur_k { printf "%s %s|%d|%d\n", $1, $2, $3 + drx, $4 + dtx; next; }
                { print $0; }
                ' "$HOURLY_DB" > "${HOURLY_DB}.tmp" 2>/dev/null && mv -f "${HOURLY_DB}.tmp" "$HOURLY_DB"
            else
                echo "${cur_h_key}|${delta_rx}|${delta_tx}" >> "$HOURLY_DB" 2>/dev/null
            fi
        fi

        # Giữ file hourly nhỏ gọn (tối đa 120 dòng gần nhất)
        if [ -f "$HOURLY_DB" ] && [ $(wc -l < "$HOURLY_DB" 2>/dev/null || echo 0) -gt 150 ]; then
            tail -n 100 "$HOURLY_DB" > "${HOURLY_DB}.tmp" 2>/dev/null && mv -f "${HOURLY_DB}.tmp" "$HOURLY_DB"
        fi

        # ─── WATCHER 4: BÁO CÁO LƯU LƯỢNG HÀNG NGÀY (DAILY REPORT) ───────────
        load_config
        if [ "$BOT_ENABLED" = "1" ] && [ "$NOTIF_DAILY_REPORT" = "1" ]; then
            local cur_h_num=$(echo "$today_hour" | awk '{print int($1)}')
            local rep_h_num=$(echo "${DAILY_REPORT_HOUR:-20}" | awk '{print int($1)}')
            if [ "$cur_h_num" -ge "$rep_h_num" ]; then
                local last_rep=""
                [ -f "$REPORTED_DATE_FILE" ] && read -r last_rep < "$REPORTED_DATE_FILE" 2>/dev/null
                if [ "$last_rep" != "$today_date" ]; then
                    local t_line=$(grep "^${today_date}|" "$DAILY_DB" 2>/dev/null | tail -n 1)
                    local r_b=0
                    local t_b=0
                    if [ -n "$t_line" ]; then
                        r_b=$(echo "$t_line" | cut -d'|' -f2)
                        t_b=$(echo "$t_line" | cut -d'|' -f3)
                    fi
                    local fmt_res=$(awk -v r="$r_b" -v t="$t_b" '
                    function fmt(b) {
                        if (b >= 1073741824) return sprintf("%.2f GB", b/1073741824);
                        if (b >= 1048576) return sprintf("%.1f MB", b/1048576);
                        return sprintf("%.1f KB", b/1024);
                    }
                    BEGIN { printf "%s|%s|%s\n", fmt(r), fmt(t), fmt(r+t); }
                    ')
                    local dl_str=$(echo "$fmt_res" | cut -d'|' -f1)
                    local ul_str=$(echo "$fmt_res" | cut -d'|' -f2)
                    local tot_str=$(echo "$fmt_res" | cut -d'|' -f3)
                    local dev_count=$(wc -l < /tmp/dhcp.leases 2>/dev/null || echo 0)

                    local rep_msg="📊 <b>BÁO CÁO LƯU LƯỢNG HÔM NAY (${today_date})</b>
━━━━━━━━━━━━━━━━━
📥 <b>Tải về (DL):</b> <code>${dl_str}</code>
📤 <b>Tải lên (UL):</b> <code>${ul_str}</code>
📦 <b>Tổng lưu lượng:</b> <code>${tot_str}</code>
📱 <b>Thiết bị DHCP:</b> <code>${dev_count} máy</code>
━━━━━━━━━━━━━━━━━
<i>Báo cáo định kỳ lúc ${DAILY_REPORT_HOUR}:00 từ router VCRT OS</i>"
                    send_msg "$rep_msg"
                    echo "$today_date" > "$REPORTED_DATE_FILE" 2>/dev/null
                fi
            fi
        fi
    done
}

# ─── TELEGRAM COMMAND HANDLERS ────────────────────────────────────────────────
cmd_status() {
    local host=$(cat /proc/sys/kernel/hostname 2>/dev/null || echo "Xiaomi-Mini")
    local up_sec=$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)
    local days=$((up_sec / 86400))
    local hours=$(( (up_sec % 86400) / 3600 ))
    local mins=$(( (up_sec % 3600) / 60 ))
    local up_str="${days}d ${hours}h ${mins}m"
    local load=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo "0.0")

    local mem_total=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 128)
    local mem_avail=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 80)
    local mem_used=$((mem_total - mem_avail))
    local mem_pct=$((mem_used * 100 / mem_total))

    local wan_ip=$(ip -4 addr show eth0.2 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n 1)
    [ -z "$wan_ip" ] && wan_ip=$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null || echo "N/A")

    local dev_cnt=$(wc -l < /tmp/dhcp.leases 2>/dev/null || echo 0)

    local msg="📡 <b>TRẠNG THÁI ROUTER ${host}</b>
━━━━━━━━━━━━━━━━━
⏱ <b>Uptime:</b> <code>${up_str}</code>
⚙️ <b>CPU Load:</b> <code>${load}</code>
💾 <b>RAM:</b> <code>${mem_used}MB / ${mem_total}MB (${mem_pct}%)</code>
🌐 <b>WAN IP:</b> <code>${wan_ip}</code>
📱 <b>Thiết bị kết nối:</b> <code>${dev_cnt} máy</code>
━━━━━━━━━━━━━━━━━
<i>Gõ /traffic để xem dung lượng hoặc /clients để xem danh sách máy</i>"
    send_msg "$msg"
}

cmd_traffic() {
    local today_date=$(date +%Y-%m-%d 2>/dev/null || echo "")
    local t_line=$(grep "^${today_date}|" "$DAILY_DB" 2>/dev/null | tail -n 1)
    local tod_rx=0; local tod_tx=0
    if [ -n "$t_line" ]; then
        tod_rx=$(echo "$t_line" | cut -d'|' -f2)
        tod_tx=$(echo "$t_line" | cut -d'|' -f3)
    fi

    local sum_7d_rx=0; local sum_7d_tx=0
    local sum_m_rx=0; local sum_m_tx=0
    local cur_ym=$(date +%Y-%m 2>/dev/null || echo "")

    if [ -f "$DAILY_DB" ]; then
        # 7 ngày gần nhất
        local d7=$(tail -n 7 "$DAILY_DB")
        for l in $d7; do
            r=$(echo "$l" | cut -d'|' -f2); t=$(echo "$l" | cut -d'|' -f3)
            sum_7d_rx=$(( sum_7d_rx + r )); sum_7d_tx=$(( sum_7d_tx + t ))
        done

        # Tháng này
        while IFS='|' read -r d r t; do
            case "$d" in
                ${cur_ym}*)
                    sum_m_rx=$(( sum_m_rx + r )); sum_m_tx=$(( sum_m_tx + t ))
                    ;;
            esac
        done < "$DAILY_DB"
    fi

    local out_str=$(awk -v tr="$tod_rx" -v tt="$tod_tx" -v sr7="$sum_7d_rx" -v st7="$sum_7d_tx" -v mr="$sum_m_rx" -v mt="$sum_m_tx" '
    function fmt(b) {
        if (b >= 1073741824) return sprintf("%.2f GB", b/1073741824);
        if (b >= 1048576) return sprintf("%.1f MB", b/1048576);
        return sprintf("%.1f KB", b/1024);
    }
    BEGIN {
        printf "%s|%s\n", fmt(tr), fmt(tr+tt);
        printf "%s|%s\n", fmt(sr7), fmt(sr7+st7);
        printf "%s|%s\n", fmt(mr), fmt(mr+mt);
    }')

    local tod_str=$(echo "$out_str" | sed -n '1p')
    local s7_str=$(echo "$out_str" | sed -n '2p')
    local sm_str=$(echo "$out_str" | sed -n '3p')

    local msg="📊 <b>THỐNG KÊ LƯU LƯỢNG MẠNG (100% THỰC TẾ)</b>
━━━━━━━━━━━━━━━━━
📅 <b>Hôm nay:</b> <code>$(echo "$tod_str" | cut -d'|' -f2)</code> (DL: $(echo "$tod_str" | cut -d'|' -f1))
🗓 <b>7 ngày qua:</b> <code>$(echo "$s7_str" | cut -d'|' -f2)</code> (DL: $(echo "$s7_str" | cut -d'|' -f1))
📆 <b>Tháng này (${cur_ym}):</b> <code>$(echo "$sm_str" | cut -d'|' -f2)</code> (DL: $(echo "$sm_str" | cut -d'|' -f1))
━━━━━━━━━━━━━━━━━
<i>Số liệu đồng bộ hoàn toàn với Web Dashboard</i>"
    send_msg "$msg"
}

cmd_clients() {
    local msg="📱 <b>DANH SÁCH THIẾT BỊ ONLINE:</b>
━━━━━━━━━━━━━━━━━
"
    local count=0
    if [ -f /tmp/dhcp.leases ] && [ -s /tmp/dhcp.leases ]; then
        while read -r ltime mac ip name clid; do
            [ "$name" = "*" ] && name="Không rõ tên"
            count=$((count + 1))
            local mac_u=$(echo "$mac" | tr '[:lower:]' '[:upper:]')
            msg="${msg}${count}. <b>${name}</b>
   ├ IP: <code>${ip}</code>
   └ MAC: <code>${mac_u}</code>
"
        done < /tmp/dhcp.leases
    fi
    [ "$count" -eq 0 ] && msg="${msg}<i>Hiện chưa có thiết bị trong bảng cấp phát DHCP.</i>"
    send_msg "$msg"
}

cmd_wifi() {
    local ssid_2g=$(uci -q get wireless.default_radio1.ssid || echo "Xiaomi_2.4G")
    local ch_2g=$(uci -q get wireless.radio1.channel || echo "6")
    local ssid_5g=$(uci -q get wireless.default_radio0.ssid || echo "Xiaomi_5G")
    local ch_5g=$(uci -q get wireless.radio0.channel || echo "149")

    local msg="📶 <b>THÔNG TIN SÓNG WI-FI ROUTER:</b>
━━━━━━━━━━━━━━━━━
🔹 <b>Băng tần 2.4GHz:</b>
   ├ SSID: <code>${ssid_2g}</code>
   └ Kênh: <code>${ch_2g}</code> (HT20)

🔹 <b>Băng tần 5GHz:</b>
   ├ SSID: <code>${ssid_5g}</code>
   └ Kênh: <code>${ch_5g}</code> (VHT80)
━━━━━━━━━━━━━━━━━"
    send_msg "$msg"
}

cmd_help() {
    local msg="🤖 <b>BẢNG LỆNH ĐIỀU KHIỂN TELEGRAM BOT:</b>
━━━━━━━━━━━━━━━━━
/status - Trạng thái router (CPU, RAM, Uptime, WAN IP)
/traffic - Thống kê dung lượng thực tế (Hôm nay, 7 ngày, Tháng)
/clients - Danh sách thiết bị đang kết nối
/wifi - Thông tin mạng Wi-Fi 2.4GHz & 5GHz
/ping - Kiểm tra kết nối router
/reboot - Khởi động lại router từ xa
/help - Hướng dẫn sử dụng
━━━━━━━━━━━━━━━━━"
    send_msg "$msg"
}

# ─── KHỞI CHẠY TIẾN TRÌNH ────────────────────────────────────────────────────
load_config

if [ "$BOT_ENABLED" != "1" ] || [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "Telegram Bot chua duoc cau hinh hoac bi tat trong $CONF_FILE"
    # Vẫn chạy tiến trình ghi nhận lưu lượng nền để tích lũy dữ liệu cho Web!
    record_traffic_periodically &
    watch_block_timers &
    wait
    exit 0
fi

# Khởi chạy 3 worker nền
watch_wifi_devices &
PID_WIFI=$!
watch_block_timers &
PID_BLOCK=$!
record_traffic_periodically &
PID_TRAFFIC=$!

cleanup() {
    kill -9 $PID_WIFI $PID_BLOCK $PID_TRAFFIC 2>/dev/null || true
    exit 0
}
trap cleanup INT TERM EXIT

send_msg "🚀 <b>VCRT Telegram Bot đã khởi động thành công!</b>
Hệ thống giám sát 24/7 đang hoạt động. Gõ /help để xem các lệnh."

OFFSET=0
API_URL="https://api.telegram.org/bot${BOT_TOKEN}"

while true; do
    load_config
    if [ "$BOT_ENABLED" != "1" ]; then
        echo "Bot bi tat tu web. Dung tien trinh."
        cleanup
    fi

    UPDATES=$(curl -s --max-time 30 "${API_URL}/getUpdates?offset=${OFFSET}&limit=1&timeout=20" 2>/dev/null || true)

    if [ -n "$UPDATES" ]; then
        UPDATE_ID=$(echo "$UPDATES" | grep -o '"update_id":[0-9]*' | head -n 1 | cut -d: -f2)
        SENDER_ID=$(echo "$UPDATES" | grep -o '"chat":{[^}]*"id":-*[0-9]*' | head -n 1 | grep -o -- '-*[0-9]*$')
        CMD_TEXT=$(echo "$UPDATES" | grep -o '"text":"[^"]*"' | head -n 1 | cut -d'"' -f4)

        if [ -n "$UPDATE_ID" ]; then
            OFFSET=$((UPDATE_ID + 1))

            if [ "$SENDER_ID" = "$CHAT_ID" ]; then
                case "$CMD_TEXT" in
                    /status*|/info*) cmd_status ;;
                    /traffic*|/dungluong*) cmd_traffic ;;
                    /clients*|/devices*) cmd_clients ;;
                    /wifi*) cmd_wifi ;;
                    /ping*) send_msg "🏓 <b>Pong!</b> Router phản hồi tốt." ;;
                    /reboot*)
                        send_msg "⚠️ <b>Đang khởi động lại router trong 3 giây...</b>"
                        sleep 3
                        /sbin/reboot
                        ;;
                    /help*|/start*) cmd_help ;;
                esac
            fi
        fi
    fi
    sleep 1
done
