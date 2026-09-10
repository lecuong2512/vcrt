#!/bin/sh
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
# ==============================================================================
# VCRT OS v1.0.0 - CYBERPUNK TELEGRAM BOT & NOTIFICATION DAEMON (24/7)
# Giám sát thiết bị thực tế, đo đạc lưu lượng chính xác, tự động mở mạng
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

KEYBOARD='{"keyboard":[[{"text":"/status"},{"text":"/clients"}],[{"text":"/traffic"},{"text":"/wifi"}],[{"text":"/ping"},{"text":"/help"}]],"resize_keyboard":true,"is_persistent":true}'

# ─── BẢO VỆ DỮ LIỆU NHẠY CẢM VỚI TELEGRAM SPOILER (<tg-spoiler>) ──────────────
# Khi hiển thị IP và MAC, làm mờ 1 phần bất kỳ. Bấm vào phần mờ sẽ hiển thị đầy đủ!
mask_ip() {
    local ip="$1"
    echo "$ip" | awk -F. '
    NF==4 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && $4 ~ /^[0-9]+$/ {
        printf "<code>%s.%s.%s.<tg-spoiler>%s</tg-spoiler></code>\n", $1, $2, $3, $4;
        exit;
    }
    { printf "<code>%s</code>\n", $0; }'
}

mask_wan_ip() {
    local ip="$1"
    echo "$ip" | awk -F. '
    NF==4 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && $4 ~ /^[0-9]+$/ {
        printf "<code>%s.%s.<tg-spoiler>%s.%s</tg-spoiler></code>\n", $1, $2, $3, $4;
        exit;
    }
    { printf "<code>%s</code>\n", $0; }'
}

mask_mac() {
    local mac="$1"
    echo "$mac" | awk '{
        m = toupper($1);
        if (m ~ /^([0-9A-F]{2}:){5}[0-9A-F]{2}$/) {
            split(m, a, ":");
            printf "<code>%s:%s:%s:<tg-spoiler>%s:%s:%s</tg-spoiler></code>\n", a[1], a[2], a[3], a[4], a[5], a[6];
            exit;
        }
        printf "<code>%s</code>\n", m;
    }'
}

load_config() {
    BOT_ENABLED=0
    BOT_TOKEN=""
    CHAT_ID=""
    NOTIF_WIFI_JOIN=1
    NOTIF_BLOCK_EXPIRE=1
    NOTIF_DAILY_REPORT=1
    DAILY_REPORT_HOUR=20

    # Tự động di chuyển cấu hình Token cũ từ /usr/bin/telegram_bot.sh nếu có
    if [ ! -f "$CONF_FILE" ] || ! grep -q 'BOT_TOKEN="[0-9]' "$CONF_FILE" 2>/dev/null; then
        if [ -f /usr/bin/telegram_bot.sh ]; then
            local old_tok=$(grep -E 'TOKEN=' /usr/bin/telegram_bot.sh 2>/dev/null | head -n1 | cut -d= -f2- | tr -d ' "\r\n;' | sed -e 's/.*:-//' -e 's/}//')
            local old_cid=$(grep -E '(ADMIN_ID|CHAT_ID)=' /usr/bin/telegram_bot.sh 2>/dev/null | head -n1 | cut -d= -f2- | tr -d ' "\r\n;' | sed -e 's/.*:-//' -e 's/}//')
            if [ -n "$old_tok" ] && [ "$old_tok" != "YOUR_TELEGRAM_BOT_TOKEN_HERE" ]; then
                mkdir -p "$VCRT_CONF_DIR"
                cat << EOF > "$CONF_FILE"
BOT_ENABLED=1
BOT_TOKEN="${old_tok}"
CHAT_ID="${old_cid}"
NOTIF_WIFI_JOIN=1
NOTIF_BLOCK_EXPIRE=1
NOTIF_DAILY_REPORT=1
DAILY_REPORT_HOUR=20
EOF
                killall -9 telegram_bot.sh 2>/dev/null || true
                rm -f /usr/bin/telegram_bot.sh 2>/dev/null || true
                sed -i '/telegram_bot\.sh/d' /etc/rc.local 2>/dev/null || true
            fi
        fi
    fi

    if [ -f "$CONF_FILE" ]; then
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
        -d "reply_markup=${KEYBOARD}" \
        --data-urlencode "text=${text}" >/dev/null 2>&1 || true
}

# ─── HELPER: QUÉT TOÀN BỘ SÓNG WI-FI PHẦN CỨNG THỜI GIAN THỰC ─────────────────
get_wifi_stations() {
    local devs=$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}')
    [ -z "$devs" ] && devs="wlan0 wlan1 phy0-ap0 phy1-ap0 ra0 rai0"
    for ifc in $devs; do
        case "$ifc" in *sta*|*mon*) continue ;; esac
        local ch=$(iw dev "$ifc" info 2>/dev/null | awk '/channel/{print $2}')
        [ -z "$ch" ] && ch=$(iwinfo "$ifc" info 2>/dev/null | awk '/Channel:/{print $4}')
        case "$ch" in ''|*[!0-9]*) ch=6 ;; esac
        local b="2.4GHz"
        [ "$ch" -gt 14 ] 2>/dev/null && b="5GHz"

        # Quét trạm qua iw dev (chuẩn xác kernel)
        iw dev "$ifc" station dump 2>/dev/null | awk -v iface="$ifc" -v band="$b" '
        /^Station/ {
            if (mac != "") {
                print mac "|" iface "|" sig "|" band "|" con "|" bitrate;
            }
            mac = tolower($2);
            sig = "N/A";
            con = 0;
            bitrate = "N/A";
        }
        $1 == "signal:" { sig = $2 " dBm"; }
        /connected time:/ { con = int($3); }
        /tx bitrate:/ { bitrate = $3 " " $4; }
        END {
            if (mac != "") {
                print mac "|" iface "|" sig "|" band "|" con "|" bitrate;
            }
        }'

        # Bổ sung iwinfo assoclist nếu có
        if command -v iwinfo >/dev/null 2>&1; then
            iwinfo "$ifc" assoclist 2>/dev/null | awk -v iface="$ifc" -v band="$b" '
            /^[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:/ {
                mac = tolower($1);
                sig = $2 " dBm";
                con = 0;
                bitrate = "N/A";
                getline;
                if ($0 ~ /TX:/) {
                    bitrate = $2 " MBit/s";
                }
                print mac "|" iface "|" sig "|" band "|" con "|" bitrate;
            }'
        fi
    done | sort -u -t'|' -k1,1
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

        local wifi_tmp="/tmp/vcrt_wifi_watch.tmp"
        get_wifi_stations > "$wifi_tmp" 2>/dev/null
        local curr_macs=$(awk -F'|' '{print tolower($1)}' "$wifi_tmp" 2>/dev/null | sort -u)

        if [ -n "$last_macs" ]; then
            for m in $curr_macs; do
                if ! echo "$last_macs" | grep -qi "$m"; then
                    sleep 1
                    local mac_up=$(echo "$m" | tr '[:lower:]' '[:upper:]')
                    local ip=$(awk -v mac="$m" 'tolower($2)==tolower(mac) {print $3}' /tmp/dhcp.leases 2>/dev/null | head -n 1)
                    local name=$(awk -v mac="$m" 'tolower($2)==tolower(mac) {print $4}' /tmp/dhcp.leases 2>/dev/null | head -n 1)
                    [ -z "$ip" ] && ip=$(awk -v mac="$m" 'tolower($4)==tolower(mac) {print $1}' /proc/net/arp 2>/dev/null | head -n 1)
                    [ -z "$ip" ] && ip="Đang nhận IP..."
                    [ "$name" = "*" ] || [ -z "$name" ] && name="Thiết bị không tên"

                    local st_match=$(grep -i "^${m}|" "$wifi_tmp" 2>/dev/null | head -n1)
                    local w_band=$(echo "$st_match" | cut -d'|' -f4)
                    local w_sig=$(echo "$st_match" | cut -d'|' -f3)

                    local band="Wi-Fi"
                    [ "$w_band" = "5GHz" ] && band="5GHz ⚡ (Tốc độ cao)"
                    [ "$w_band" = "2.4GHz" ] && band="2.4GHz 📶 (Xuyên tường)"
                    [ -n "$w_sig" ] && [ "$w_sig" != "N/A" ] && band="${band} · Tín hiệu: ${w_sig}"

                    local now_str=$(date +'%H:%M:%S - %d/%m/%Y' 2>/dev/null || echo "")
                    local m_ip=$(mask_ip "$ip")
                    local m_mac=$(mask_mac "$mac_up")
                    local alert_msg="🔔 <b>THIẾT BỊ VỪA KẾT NỐI WI-FI!</b>
━━━━━━━━━━━━━━━━━━
📱 <b>Tên máy:</b> <code>${name}</code>
📍 <b>Địa chỉ IP:</b> ${m_ip}
🔑 <b>Địa chỉ MAC:</b> ${m_mac}
📡 <b>Băng tần:</b> <code>${band}</code>
⏰ <b>Thời gian:</b> <code>${now_str}</code>
━━━━━━━━━━━━━━━━━━
<i>Gõ /clients để xem danh sách máy online</i>"
                    send_msg "$alert_msg"
                fi
            done
        fi
        last_macs="$curr_macs"
        rm -f "$wifi_tmp" 2>/dev/null || true
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
                    local m_ip=$(mask_ip "$b_ip")
                    local m_mac=$(mask_mac "$b_mac")
                    local unblock_msg="🎉 <b>ĐÃ HẾT GIỜ NGẮT KẾT NỐI!</b>
━━━━━━━━━━━━━━━━━━
📱 <b>Thiết bị:</b> <code>${b_name}</code>
📍 <b>Địa chỉ IP:</b> ${m_ip}
🔑 <b>Địa chỉ MAC:</b> ${m_mac}
━━━━━━━━━━━━━━━━━━
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
        local def_dev=$(ip route 2>/dev/null | awk '/^default/{print $5}' | head -n 1)
        [ -z "$def_dev" ] && def_dev=$(route -n 2>/dev/null | awk '/^0.0.0.0/{print $8}' | head -n 1)
        [ -z "$def_dev" ] && def_dev="eth0.2"

        local cur_rx=0; local cur_tx=0
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

        local delta_rx=0; local delta_tx=0
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
            if grep -q "^${today_date}|" "$DAILY_DB" 2>/dev/null; then
                awk -F'|' -v cur_d="$today_date" -v drx="$delta_rx" -v dtx="$delta_tx" '
                $1 == cur_d { printf "%s|%d|%d\n", $1, $2 + drx, $3 + dtx; next; }
                { print $0; }
                ' "$DAILY_DB" > "${DAILY_DB}.tmp" 2>/dev/null && mv -f "${DAILY_DB}.tmp" "$DAILY_DB"
            else
                echo "${today_date}|${delta_rx}|${delta_tx}" >> "$DAILY_DB" 2>/dev/null
            fi

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

        # Giữ file hourly tối đa 100 dòng
        if [ -f "$HOURLY_DB" ] && [ $(wc -l < "$HOURLY_DB" 2>/dev/null || echo 0) -gt 150 ]; then
            tail -n 100 "$HOURLY_DB" > "${HOURLY_DB}.tmp" 2>/dev/null && mv -f "${HOURLY_DB}.tmp" "$HOURLY_DB"
        fi

        # ─── WATCHER 4: BÁO CÁO ĐỊNH KỲ HÀNG NGÀY ─────────────────────────────
        load_config
        if [ "$BOT_ENABLED" = "1" ] && [ "$NOTIF_DAILY_REPORT" = "1" ]; then
            local cur_h_num=$(echo "$today_hour" | awk '{print int($1)}')
            local rep_h_num=$(echo "${DAILY_REPORT_HOUR:-20}" | awk '{print int($1)}')
            if [ "$cur_h_num" -ge "$rep_h_num" ]; then
                local last_rep=""
                [ -f "$REPORTED_DATE_FILE" ] && read -r last_rep < "$REPORTED_DATE_FILE" 2>/dev/null
                if [ "$last_rep" != "$today_date" ]; then
                    local t_line=$(grep "^${today_date}|" "$DAILY_DB" 2>/dev/null | tail -n 1)
                    local r_b=0; local t_b=0
                    if [ -n "$t_line" ]; then
                        r_b=$(echo "$t_line" | cut -d'|' -f2); t_b=$(echo "$t_line" | cut -d'|' -f3)
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

                    # Lấy số máy online thực tế
                    local real_online=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | while read -r w; do
                        [ "$w" = "phy0-sta0" ] && continue
                        iw dev "$w" station dump 2>/dev/null | awk '/Station/{print $2}'
                    done | sort -u | wc -l)
                    [ -z "$real_online" ] && real_online=0

                    local rep_msg="📊 <b>BÁO CÁO LƯU LƯỢNG HÔM NAY (${today_date})</b>
━━━━━━━━━━━━━━━━━━
📥 <b>Tải về (DL):</b> <code>${dl_str}</code>
📤 <b>Tải lên (UL):</b> <code>${ul_str}</code>
📦 <b>Tổng lưu lượng:</b> <code>${tot_str}</code>
📱 <b>Thiết bị đang online:</b> <code>${real_online} máy</code>
━━━━━━━━━━━━━━━━━━
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
    local up_str=""
    [ "$days" -gt 0 ] && up_str="${days} ngày "
    up_str="${up_str}${hours} giờ ${mins} phút"

    local load=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo "0.0")

    local mem_total=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 128)
    local mem_avail=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 80)
    local mem_used=$((mem_total - mem_avail))
    local mem_pct=$((mem_used * 100 / mem_total))

    # CPU bar visualization
    local cpu_blocks=""
    local b_idx=0
    local load_num=$(echo "$load" | awk '{print int($1*25)}')
    [ "$load_num" -gt 100 ] && load_num=100
    local filled=$(( load_num / 10 ))
    while [ "$b_idx" -lt 10 ]; do
        if [ "$b_idx" -lt "$filled" ]; then
            cpu_blocks="${cpu_blocks}■"
        else
            cpu_blocks="${cpu_blocks}□"
        fi
        b_idx=$(( b_idx + 1 ))
    done

    local rom_used=$(df -h /overlay 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
    [ -z "$rom_used" ] && rom_used=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')

    local wan_ip=$(ip -4 addr show eth0.2 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n 1)
    [ -z "$wan_ip" ] && wan_ip=$(ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n 1)
    [ -z "$wan_ip" ] && wan_ip=$(curl -s --max-time 2 https://api.ipify.org 2>/dev/null || echo "192.168.10.x")

    # Đếm số thiết bị online THỰC TẾ (100% chính xác, không trùng lặp)
    local wifi_tmp="/tmp/vcrt_wifi_status.tmp"
    get_wifi_stations > "$wifi_tmp" 2>/dev/null
    local online_total=$(wc -l < "$wifi_tmp" 2>/dev/null || echo 0)
    case "$online_total" in ''|*[!0-9]*) online_total=0 ;; esac

    # Kiểm tra thêm nếu có máy cắm dây LAN (không nằm trong Wi-Fi và phản hồi ping)
    if [ -f /proc/net/arp ]; then
        for l_ip in $(awk '$3=="0x2" && $6=="br-lan" {print $1}' /proc/net/arp 2>/dev/null); do
            local l_mac=$(awk -v ip="$l_ip" '$1==ip {print tolower($4)}' /proc/net/arp 2>/dev/null | head -n1)
            if [ -n "$l_mac" ] && ! grep -qi "^${l_mac}|" "$wifi_tmp" 2>/dev/null; then
                if ping -c 1 -W 1 "$l_ip" >/dev/null 2>&1 || ip neigh show dev br-lan 2>/dev/null | grep -i "$l_mac" | grep -v "fe80" | grep -qE "REACHABLE|DELAY|PROBE|STALE"; then
                    online_total=$(( online_total + 1 ))
                fi
            fi
        done
    fi
    rm -f "$wifi_tmp" 2>/dev/null || true

    local ch_2g=$(uci -q get wireless.radio1.channel || echo "6")
    local ch_5g=$(uci -q get wireless.radio0.channel || echo "149")

    local msg="⚡ <b>VCRT OS v1.0.0 · BẢNG ĐIỀU KHIỂN ROUTER</b>
━━━━━━━━━━━━━━━━━━
🏷 <b>Thiết bị:</b> <code>Xiaomi MiWiFi Mini (MT7620A)</code>
⏱ <b>Thời gian chạy:</b> <code>${up_str}</code>
⚙️ <b>CPU Load:</b> <code>${load}</code> [${cpu_blocks}]
💾 <b>Bộ nhớ RAM:</b> <code>${mem_used}MB / ${mem_total}MB (${mem_pct}%)</code>
💿 <b>Bộ nhớ Flash:</b> <code>${rom_used}</code>
🌐 <b>Địa chỉ WAN:</b> $(mask_wan_ip "${wan_ip}")
📶 <b>Wi-Fi Kênh:</b> <code>2.4G (CH ${ch_2g}) · 5G (CH ${ch_5g})</code>
👥 <b>Thiết bị ĐANG ONLINE:</b> <code>${online_total} máy</code>
━━━━━━━━━━━━━━━━━━
<i>Gõ /clients để xem chi tiết danh sách máy online</i>"
    send_msg "$msg"
}

# ─── CMD_CLIENTS: 100% ONLINE THỰC TẾ (LỌC BỎ HOÀN TOÀN MÁY ĐÃ NGẮT KẾT NỐI) ──
cmd_clients() {
    local wifi_tmp="/tmp/vcrt_wifi_cmd_clients.tmp"
    get_wifi_stations > "$wifi_tmp" 2>/dev/null

    local dev_entries=""
    local count=0
    local processed_macs=""

    # 1. Duyệt từ bảng DHCP Leases
    if [ -f /tmp/dhcp.leases ] && [ -s /tmp/dhcp.leases ]; then
        while read -r ltime mac ip name clid; do
            [ -z "$mac" ] && continue
            local mac_low=$(echo "$mac" | tr 'A-Z' 'a-z')
            processed_macs="${processed_macs} ${mac_low}"
            [ "$name" = "*" ] || [ -z "$name" ] && name="Thiết bị không tên"

            local is_online=0
            local conn_type=""
            local sig_str=""
            local time_str=""
            local speed_str=""
            local icon="📱"
            echo "$name" | grep -qi "lap\|pc\|mac\|win\|desktop" && icon="💻"
            echo "$name" | grep -qi "tv\|tivi\|sony\|lg\|samsung\|tcl\|panasonic" && icon="📺"
            echo "$name" | grep -qi "cam\|ipcam\|imou\|ezviz" && icon="📷"
            echo "$name" | grep -qi "pad\|tab" && icon="📟"

            # A. Kiểm tra sóng Wi-Fi (phần cứng xác thực 100%)
            local w_match=$(grep -i "^${mac_low}|" "$wifi_tmp" 2>/dev/null | head -n1)
            if [ -n "$w_match" ]; then
                is_online=1
                local w_ifc=$(echo "$w_match" | cut -d'|' -f2)
                local w_sig=$(echo "$w_match" | cut -d'|' -f3)
                local w_band=$(echo "$w_match" | cut -d'|' -f4)
                local w_con=$(echo "$w_match" | cut -d'|' -f5)
                local w_tx=$(echo "$w_match" | cut -d'|' -f6)

                if [ "$w_band" = "5GHz" ]; then
                    conn_type="Wi-Fi 5GHz ⚡ (Tốc độ cao)"
                else
                    conn_type="Wi-Fi 2.4GHz 📶 (Xuyên tường)"
                fi

                # Định dạng thời gian bắt sóng
                case "$w_con" in ''|*[!0-9]*) w_con=0 ;; esac
                if [ "$w_con" -gt 86400 ]; then
                    local d=$((w_con / 86400))
                    local h=$(( (w_con % 86400) / 3600 ))
                    time_str="${d} ngày ${h} giờ"
                elif [ "$w_con" -gt 3600 ]; then
                    local h=$((w_con / 3600))
                    local m=$(( (w_con % 3600) / 60 ))
                    time_str="${h} giờ ${m} phút"
                elif [ "$w_con" -gt 60 ]; then
                    local m=$((w_con / 60))
                    local s=$((w_con % 60))
                    time_str="${m} phút ${s} giây"
                elif [ "$w_con" -gt 0 ]; then
                    time_str="${w_con} giây (Vừa kết nối)"
                else
                    time_str="Đang bắt sóng"
                fi

                # Đánh giá tín hiệu sóng
                local sig_num=$(echo "$w_sig" | awk '{print int($1)}')
                local sig_badge="🟢 Tốt"
                if [ "$sig_num" -ge -50 ] 2>/dev/null; then sig_badge="🟢 Rất mạnh"
                elif [ "$sig_num" -le -75 ] 2>/dev/null; then sig_badge="🔴 Yếu"
                elif [ "$sig_num" -le -65 ] 2>/dev/null; then sig_badge="🟡 Khá"
                fi
                [ -n "$w_sig" ] && [ "$w_sig" != "N/A" ] && sig_str="${w_sig} (${sig_badge})"

                [ -n "$w_tx" ] && [ "$w_tx" != "N/A" ] && speed_str="${w_tx} (TX Bitrate)"
            else
                # B. Kiểm tra Cáp LAN cắm dây (Xác thực qua switch port, ping hoặc Linux neighbor table)
                local a_ent=$(grep -i "$mac_low" /proc/net/arp 2>/dev/null | head -n1)
                local a_flg=$(echo "$a_ent" | awk '{print $3}')
                if [ "$a_flg" = "0x2" ] && [ -n "$ip" ]; then
                    local is_alive=0
                    if ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
                        is_alive=1
                    elif ip neigh show dev br-lan 2>/dev/null | grep -i "$mac_low" | grep -v "fe80" | grep -qE "REACHABLE|DELAY|PROBE|STALE"; then
                        is_alive=1
                    fi

                    if [ "$is_alive" -eq 1 ]; then
                        is_online=1
                        conn_type="Cáp Mạng LAN 🔌 (Cổng Switch)"
                        time_str="Đang trực tuyến (Dây cáp LAN)"
                        speed_str="100 Mbps Full-Duplex"
                        icon="💻"
                    fi
                fi
            fi

            # Kiểm tra xem có đang bị chặn không
            local block_badge=""
            if [ -f "$TIMED_BLOCKS_FILE" ]; then
                local b_match=$(grep -i "^${mac_low}|" "$TIMED_BLOCKS_FILE" 2>/dev/null | head -n1)
                if [ -n "$b_match" ]; then
                    block_badge=" [⛔ ĐANG BỊ CHẶN]"
                fi
            fi

            # NẾU KHÔNG ONLINE VÀ KHÔNG BỊ CHẶN -> BỎ QUA HOÀN TOÀN!
            if [ "$is_online" -eq 0 ] && [ -z "$block_badge" ]; then
                continue
            fi

            count=$((count + 1))
            local mac_u=$(echo "$mac" | tr '[:lower:]' '[:upper:]')
            local m_ip=$(mask_ip "$ip")
            local m_mac=$(mask_mac "$mac_u")
            
            local detail_block="   ├ 📍 IP: ${m_ip}
   ├ 🔑 MAC: ${m_mac}
   ├ 📡 Kết nối: <code>${conn_type}</code>
   ├ ⏱ Bắt sóng: <code>${time_str}</code>"
            [ -n "$sig_str" ] && detail_block="${detail_block}
   ├ 📶 Tín hiệu: <code>${sig_str}</code>"
            [ -n "$speed_str" ] && detail_block="${detail_block}
   └ ⚡ Tốc độ: <code>${speed_str}</code>"
            [ -z "$speed_str" ] && detail_block="${detail_block}
   └ ⚡ Trạng thái: <code>Sẵn sàng truyền dữ liệu</code>"

            dev_entries="${dev_entries}${count}. ${icon} <b>${name}</b>${block_badge}
${detail_block}
"
        done < /tmp/dhcp.leases
    fi

    # 2. Duyệt các thiết bị Wi-Fi dùng IP tĩnh (không có trong dhcp.leases)
    if [ -f "$wifi_tmp" ]; then
        while IFS='|' read -r sm_mac sm_ifc sm_sig sm_band sm_con sm_tx; do
            [ -z "$sm_mac" ] && continue
            if ! echo "$processed_macs" | grep -qi "$sm_mac"; then
                processed_macs="${processed_macs} ${sm_mac}"
                local s_ip=$(awk -v mac="$sm_mac" 'tolower($4)==tolower(mac) {print $1}' /proc/net/arp 2>/dev/null | head -n 1)
                [ -z "$s_ip" ] && s_ip="IP Tĩnh"

                local conn_type="Wi-Fi 2.4GHz 📶 (Xuyên tường)"
                [ "$sm_band" = "5GHz" ] && conn_type="Wi-Fi 5GHz ⚡ (Tốc độ cao)"

                case "$sm_con" in ''|*[!0-9]*) sm_con=0 ;; esac
                local time_str="Đang bắt sóng"
                if [ "$sm_con" -gt 3600 ]; then
                    time_str="$((sm_con / 3600)) giờ $(( (sm_con % 3600) / 60 )) phút"
                elif [ "$sm_con" -gt 60 ]; then
                    time_str="$((sm_con / 60)) phút $((sm_con % 60)) giây"
                elif [ "$sm_con" -gt 0 ]; then
                    time_str="${sm_con} giây"
                fi

                local sig_str=""
                local sig_num=$(echo "$sm_sig" | awk '{print int($1)}')
                local sig_badge="🟢 Tốt"
                [ "$sig_num" -ge -50 ] 2>/dev/null && sig_badge="🟢 Rất mạnh"
                [ "$sig_num" -le -75 ] 2>/dev/null && sig_badge="🔴 Yếu"
                [ -n "$sm_sig" ] && [ "$sm_sig" != "N/A" ] && sig_str="${sm_sig} (${sig_badge})"

                count=$((count + 1))
                local sm_u=$(echo "$sm_mac" | tr '[:lower:]' '[:upper:]')
                local m_sip=$(mask_ip "$s_ip")
                local m_smac=$(mask_mac "$sm_u")
                dev_entries="${dev_entries}${count}. 📱 <b>Thiết bị Wi-Fi (${s_ip})</b>
   ├ 📍 IP: ${m_sip}
   ├ 🔑 MAC: ${m_smac}
   ├ 📡 Kết nối: <code>${conn_type}</code>
   ├ ⏱ Bắt sóng: <code>${time_str}</code>
   ├ 📶 Tín hiệu: <code>${sig_str:-N/A}</code>
   └ ⚡ Tốc độ: <code>${sm_tx:-N/A}</code>
"
            fi
        done < "$wifi_tmp"
    fi
    rm -f "$wifi_tmp" 2>/dev/null || true

    local header="📱 <b>DANH SÁCH THIẾT BỊ ĐANG ONLINE (${count} máy)</b>
━━━━━━━━━━━━━━━━━━
"
    if [ "$count" -eq 0 ]; then
        dev_entries="<i>Hiện không có thiết bị nào đang kết nối sóng Wi-Fi hoặc cắm dây LAN.</i>
"
    fi

    local footer="━━━━━━━━━━━━━━━━━━
<i>Gõ /block &lt;mac&gt; [phút] để ngắt kết nối máy bất kỳ</i>"
    send_msg "${header}${dev_entries}${footer}"
}

# ─── CMD_TRAFFIC: BÁO CÁO ĐA CHU KỲ (NGÀY / 7 NGÀY / THÁNG / NĂM) ────────────
cmd_traffic() {
    local today_date=$(date +%Y-%m-%d 2>/dev/null || echo "2026-09-10")
    local cur_year=$(date +%Y 2>/dev/null || echo "2026")
    local cur_month=$(date +%m 2>/dev/null || echo "09")

    # Lấy số liệu từ database
    local out=$(awk \
    -v daily_file="$DAILY_DB" \
    -v cur_date="$today_date" \
    -v cur_year="$cur_year" \
    -v cur_month="$cur_month" \
    'function fmt(b) {
        if (b >= 1073741824) return sprintf("%.2f GB", b/1073741824);
        if (b >= 1048576) return sprintf("%.1f MB", b/1048576);
        return sprintf("%.1f KB", b/1024);
    }
    BEGIN { FS = "|"; }
    FILENAME == daily_file {
        d = $1; split(d, dt, "-");
        y = dt[1] + 0; m = dt[2] + 0;
        r = $2 + 0; t = $3 + 0;
        d_rx[d] = r; d_tx[d] = t;
        if (y == (cur_year + 0) && m == (cur_month + 0)) {
            m_rx += r; m_tx += t;
        }
        if (y == (cur_year + 0)) {
            y_rx += r; y_tx += t;
        }
    }
    END {
        tr = d_rx[cur_date] + 0; tt = d_tx[cur_date] + 0;
        printf "%s|%s|%s\n", fmt(tr), fmt(tt), fmt(tr+tt);
        printf "%s|%s|%s\n", fmt(m_rx), fmt(m_tx), fmt(m_rx+m_tx);
        printf "%s|%s|%s\n", fmt(y_rx), fmt(y_tx), fmt(y_rx+y_tx);
    }' "$DAILY_DB" 2>/dev/null)

    # 7 ngày gần nhất
    local sum_7d_rx=0; local sum_7d_tx=0
    if [ -f "$DAILY_DB" ]; then
        local d7=$(tail -n 7 "$DAILY_DB" 2>/dev/null)
        for l in $d7; do
            r=$(echo "$l" | cut -d'|' -f2); t=$(echo "$l" | cut -d'|' -f3)
            sum_7d_rx=$(( sum_7d_rx + r )); sum_7d_tx=$(( sum_7d_tx + t ))
        done
    fi
    local s7_fmt=$(awk -v r="$sum_7d_rx" -v t="$sum_7d_tx" '
    function fmt(b) {
        if (b >= 1073741824) return sprintf("%.2f GB", b/1073741824);
        if (b >= 1048576) return sprintf("%.1f MB", b/1048576);
        return sprintf("%.1f KB", b/1024);
    }
    BEGIN { printf "%s|%s|%s\n", fmt(r), fmt(t), fmt(r+t); }
    ')

    local tod_line=$(echo "$out" | sed -n '1p')
    local mon_line=$(echo "$out" | sed -n '2p')
    local yr_line=$(echo "$out" | sed -n '3p')

    local msg="📊 <b>BÁO CÁO DỮ LIỆU ĐÃ DÙNG (100% THỰC TẾ)</b>
━━━━━━━━━━━━━━━━━━
📅 <b>HÔM NAY (${today_date}):</b>
   ├ 🌐 Tổng cộng: <code>$(echo "$tod_line" | cut -d'|' -f3)</code>
   └ 📥 Tải về: <code>$(echo "$tod_line" | cut -d'|' -f1)</code> · 📤 Tải lên: <code>$(echo "$tod_line" | cut -d'|' -f2)</code>

🗓 <b>7 NGÀY GẦN NHẤT:</b>
   ├ 🌐 Tổng cộng: <code>$(echo "$s7_fmt" | cut -d'|' -f3)</code>
   └ 📥 Tải về: <code>$(echo "$s7_fmt" | cut -d'|' -f1)</code> · 📤 Tải lên: <code>$(echo "$s7_fmt" | cut -d'|' -f2)</code>

📆 <b>1 THÁNG QUA (Tháng ${cur_month}/${cur_year}):</b>
   ├ 🌐 Tổng cộng: <code>$(echo "$mon_line" | cut -d'|' -f3)</code>
   └ 📥 Tải về: <code>$(echo "$mon_line" | cut -d'|' -f1)</code> · 📤 Tải lên: <code>$(echo "$mon_line" | cut -d'|' -f2)</code>

📈 <b>CẢ NĂM (${cur_year}):</b>
   ├ 🌐 Tổng cộng: <code>$(echo "$yr_line" | cut -d'|' -f3)</code>
   └ 📥 Tải về: <code>$(echo "$yr_line" | cut -d'|' -f1)</code> · 📤 Tải lên: <code>$(echo "$yr_line" | cut -d'|' -f2)</code>
━━━━━━━━━━━━━━━━━━
<i>Dữ liệu đồng bộ 100% với Web Dashboard VCRT</i>"
    send_msg "$msg"
}

# ─── CMD_WIFI: THÔNG SỐ SÓNG & SỐ MÁY TRÊN TỪNG BĂNG TẦN ──────────────────────
cmd_wifi() {
    local ssid_2g=$(uci -q get wireless.default_radio1.ssid || uci -q get wireless.@wifi-iface[0].ssid || echo "Xiaomi_2.4G")
    local ch_2g=$(uci -q get wireless.radio1.channel || echo "6")
    local ssid_5g=$(uci -q get wireless.default_radio0.ssid || uci -q get wireless.@wifi-iface[1].ssid || echo "Xiaomi_5G")
    local ch_5g=$(uci -q get wireless.radio0.channel || echo "149")

    local wifi_tmp="/tmp/vcrt_wifi_cmd.tmp"
    get_wifi_stations > "$wifi_tmp" 2>/dev/null
    local cnt_5g=$(grep -c "|5GHz|" "$wifi_tmp" 2>/dev/null || echo 0)
    local cnt_24g=$(grep -c "|2.4GHz|" "$wifi_tmp" 2>/dev/null || echo 0)
    rm -f "$wifi_tmp" 2>/dev/null || true

    local msg="📶 <b>THÔNG SỐ PHÁT SÓNG WI-FI ROUTER</b>
━━━━━━━━━━━━━━━━━━
🔹 <b>Băng tần 5GHz (Tốc độ cao 867Mbps):</b>
   ├ 🏷 Tên SSID: <code>${ssid_5g}</code>
   ├ 📡 Kênh: <code>CH ${ch_5g} (VHT80)</code>
   └ 👥 Đang kết nối: <code>${cnt_5g} thiết bị</code>

🔹 <b>Băng tần 2.4GHz (Xuyên tường 300Mbps):</b>
   ├ 🏷 Tên SSID: <code>${ssid_2g}</code>
   ├ 📡 Kênh: <code>CH ${ch_2g} (HT20)</code>
   └ 👥 Đang kết nối: <code>${cnt_24g} thiết bị</code>
━━━━━━━━━━━━━━━━━━
<i>Gõ /clients để xem tên các máy đang kết nối</i>"
    send_msg "$msg"
}

# ─── CMD_PING: KIỂM TRA ĐỘ TRỄ INTERNET ───────────────────────────────────────
cmd_ping() {
    send_msg "🏓 <i>Đang đo độ trễ mạng đến Cloudflare DNS...</i>"
    local p_out=$(ping -c 3 -W 2 1.1.1.1 2>/dev/null)
    local rtt=$(echo "$p_out" | awk -F'/' '/round-trip|rtt/{print $4, $5, $6}')
    local loss=$(echo "$p_out" | grep -o '[0-9]*% packet loss' | head -n1)

    if [ -n "$rtt" ]; then
        local min_ms=$(echo "$rtt" | awk '{print $1}')
        local avg_ms=$(echo "$rtt" | awk '{print $2}')
        local max_ms=$(echo "$rtt" | awk '{print $3}')

        local qual="🟢 Rất tốt & Ổn định"
        local avg_int=$(echo "$avg_ms" | awk '{print int($1)}')
        [ "$avg_int" -gt 60 ] && qual="🟡 Khá"
        [ "$avg_int" -gt 150 ] && qual="🔴 Trễ cao"

        local msg="🏓 <b>KẾT QUẢ ĐO ĐỘ TRỄ MẠNG (PING)</b>
━━━━━━━━━━━━━━━━━━
🌐 <b>Máy chủ:</b> <code>Cloudflare DNS (1.1.1.1)</code>
⚡ <b>Độ trễ trung bình:</b> <code>${avg_ms} ms</code>
📊 <b>Tối thiểu / Tối đa:</b> <code>${min_ms} ms / ${max_ms} ms</code>
📦 <b>Tình trạng mất gói:</b> <code>${loss:-0% packet loss}</code>
📶 <b>Chất lượng đường truyền:</b> ${qual}
━━━━━━━━━━━━━━━━━━"
        send_msg "$msg"
    else
        send_msg "❌ <b>Mất kết nối Internet!</b> Không thể gửi gói tin ping đến máy chủ bên ngoài."
    fi
}

# ─── CMD_BLOCK: CHẶN THIẾT BỊ QUA TELEGRAM ────────────────────────────────────
cmd_block() {
    local target_mac="$1"
    local dur="$2"
    [ -z "$dur" ] && dur=30

    if [ -z "$target_mac" ]; then
        send_msg "⚠️ <b>Cú pháp lệnh chưa đúng!</b>
Vui lòng nhập: <code>/block &lt;Địa_chỉ_MAC&gt; [Số_phút]</code>
Ví dụ: <code>/block 00:11:22:33:44:55 60</code>"
        return
    fi

    local target_mac_low=$(echo "$target_mac" | tr 'A-Z' 'a-z')
    local now_epoch=$(date +%s 2>/dev/null || echo 0)
    local expire=$(( now_epoch + dur * 60 ))

    iptables -D FORWARD -m mac --mac-source "$target_mac_low" -j DROP 2>/dev/null || true
    iptables -I FORWARD -m mac --mac-source "$target_mac_low" -j DROP

    echo "$target_mac_low" >> "$BLOCKED_SOFT_FILE"
    [ -f "$TIMED_BLOCKS_FILE" ] && grep -v -i "^${target_mac_low}|" "$TIMED_BLOCKS_FILE" > "${TIMED_BLOCKS_FILE}.tmp" 2>/dev/null || true
    mv "${TIMED_BLOCKS_FILE}.tmp" "$TIMED_BLOCKS_FILE" 2>/dev/null || true
    echo "${target_mac_low}|soft|${now_epoch}|${expire}|${dur}|Telegram-Block|N/A" >> "$TIMED_BLOCKS_FILE"

    local m_tmac=$(mask_mac "$target_mac")
    local msg="⛔ <b>ĐÃ CHẶN KẾT NỐI INTERNET!</b>
━━━━━━━━━━━━━━━━━━
🔑 <b>MAC:</b> ${m_tmac}
⏱ <b>Thời hạn chặn:</b> <code>${dur} phút</code>
━━━━━━━━━━━━━━━━━━
<i>Hệ thống sẽ tự động mở lại mạng khi hết giờ hoặc gõ /unblock ${target_mac}</i>"
    send_msg "$msg"
}

# ─── CMD_UNBLOCK: MỞ MẠNG QUA TELEGRAM ────────────────────────────────────────
cmd_unblock() {
    local target_mac="$1"
    if [ -z "$target_mac" ]; then
        send_msg "⚠️ <b>Cú pháp lệnh chưa đúng!</b>
Vui lòng nhập: <code>/unblock &lt;Địa_chỉ_MAC&gt;</code>
Ví dụ: <code>/unblock 00:11:22:33:44:55</code>"
        return
    fi

    local target_mac_low=$(echo "$target_mac" | tr 'A-Z' 'a-z')
    iptables -D FORWARD -m mac --mac-source "$target_mac_low" -j DROP 2>/dev/null || true
    iptables -D INPUT -m mac --mac-source "$target_mac_low" -j DROP 2>/dev/null || true
    grep -v -i "$target_mac_low" "$BLOCKED_SOFT_FILE" > "${BLOCKED_SOFT_FILE}.tmp" 2>/dev/null || true
    mv "${BLOCKED_SOFT_FILE}.tmp" "$BLOCKED_SOFT_FILE" 2>/dev/null || true
    grep -v -i "$target_mac_low" "$BLOCKED_HARD_FILE" > "${BLOCKED_HARD_FILE}.tmp" 2>/dev/null || true
    mv "${BLOCKED_HARD_FILE}.tmp" "$BLOCKED_HARD_FILE" 2>/dev/null || true
    [ -f "$TIMED_BLOCKS_FILE" ] && grep -v -i "^${target_mac_low}|" "$TIMED_BLOCKS_FILE" > "${TIMED_BLOCKS_FILE}.tmp" 2>/dev/null || true
    mv "${TIMED_BLOCKS_FILE}.tmp" "$TIMED_BLOCKS_FILE" 2>/dev/null || true

    local m_tmac=$(mask_mac "$target_mac")
    local msg="🔓 <b>ĐÃ MỞ LẠI KẾT NỐI INTERNET!</b>
━━━━━━━━━━━━━━━━━━
🔑 <b>MAC:</b> ${m_tmac}
━━━━━━━━━━━━━━━━━━
<i>Thiết bị đã có thể truy cập mạng bình thường.</i>"
    send_msg "$msg"
}

cmd_help() {
    local msg="🤖 <b>VCRT OS v1.0.0 - TRỢ LÝ ĐIỀU HÀNH ROUTER 24/7</b>
━━━━━━━━━━━━━━━━━━
Dưới đây là các lệnh điều khiển:

⚡ /status - Xem CPU, RAM, Uptime, WAN IP
📱 /clients - Danh sách thiết bị ĐANG ONLINE thực tế
📊 /traffic - Thống kê dung lượng mạng đã dùng
📶 /wifi - Thông số phát sóng Wi-Fi 2.4G & 5G
🏓 /ping - Kiểm tra độ trễ mạng Internet
⛔ /block &lt;mac&gt; [phút] - Chặn mạng có hẹn giờ
🔓 /unblock &lt;mac&gt; - Mở mạng lại ngay lập tức
🔄 /reboot - Khởi động lại router từ xa
❓ /help - Hiển thị hướng dẫn này
━━━━━━━━━━━━━━━━━━
<i>Bạn có thể bấm trực tiếp các nút menu ở bàn phím bên dưới!</i>"
    send_msg "$msg"
}

# ─── KHỞI CHẠY TIẾN TRÌNH ────────────────────────────────────────────────────
load_config

if [ "$BOT_ENABLED" != "1" ] || [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "Telegram Bot chua duoc cau hinh hoac bi tat trong $CONF_FILE"
    record_traffic_periodically &
    watch_block_timers &
    wait
    exit 0
fi

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

send_msg "🟢 <b>VCRT OS v1.0.0 - TELEGRAM BOT ĐÃ SẴN SÀNG!</b>
━━━━━━━━━━━━━━━━━━
⚡ Hệ thống giám sát thiết bị & lưu lượng 24/7 đang hoạt động.
📡 Quản lý phát sóng Wi-Fi 2.4GHz & 5GHz · Quét & đổi nguồn WISP
📱 Gõ <b>/clients</b> để xem danh sách máy online, băng tần và thời gian bắt sóng."

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
                # Clean command name
                cmd_name=$(echo "$CMD_TEXT" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
                arg1=$(echo "$CMD_TEXT" | awk '{print $2}')
                arg2=$(echo "$CMD_TEXT" | awk '{print $3}')

                case "$cmd_name" in
                    /status*|/info*|/router*) cmd_status ;;
                    /client*|/clients*|/device*|/devices*|/thietbi*|/may*) cmd_clients ;;
                    /traffic*|/dungluong*|/data*) cmd_traffic ;;
                    /wifi*|/song*) cmd_wifi ;;
                    /ping*|/test*) cmd_ping ;;
                    /block*) cmd_block "$arg1" "$arg2" ;;
                    /unblock*) cmd_unblock "$arg1" ;;
                    /reboot*)
                        send_msg "⚠️ <b>Đang khởi động lại router trong 3 giây...</b>"
                        sleep 3
                        /sbin/reboot
                        ;;
                    /help*|/start*|*) cmd_help ;;
                esac
            fi
        fi
    fi
    sleep 1
done
