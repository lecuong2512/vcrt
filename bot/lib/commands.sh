#!/bin/sh
# ==============================================================================
# VCRT OS v2.0 - Telegram Bot Command Handlers
# 14 Commands: status, clients, traffic, wifi, ping, speed, nextdns, backup,
#              block, unblock, update, reboot, logo, help
# BusyBox POSIX Shell Standard - Ultra-lightweight & Optimized
# ==============================================================================

# ─── CMD 1: /status — TRẠNG THÁI ROUTER TOÀN DIỆN ────────────────────────────
cmd_status() {
    local target_chat="$1"
    local dev_name="${DEVICE_NAME_DEFAULT:-Xiaomi MiWiFi Mini (MT7620A)}"
    local host
    host=$(cat /proc/sys/kernel/hostname 2>/dev/null || echo "VCRT-Router")

    local up_sec
    up_sec=$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)
    local up_str
    up_str=$(format_duration "$up_sec")

    local load
    load=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo "0.00 0.00 0.00")
    local load_1
    load_1=$(printf '%s' "$load" | awk '{print int($1 * 100)}')
    local cpu_ui
    cpu_ui=$(cpu_bar "$load_1")

    local mem_total
    mem_total=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 128)
    local mem_avail
    mem_avail=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 80)
    local mem_used=$(( mem_total - mem_avail ))
    local mem_pct=0
    [ "$mem_total" -gt 0 ] && mem_pct=$(( mem_used * 100 / mem_total ))

    local rom_used
    rom_used=$(df -h /overlay 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
    [ -z "$rom_used" ] && rom_used=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')

    local wan_dev
    wan_dev=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
    local wan_ip=""
    [ -n "$wan_dev" ] && wan_ip=$(ip -4 addr show "$wan_dev" 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)
    [ -z "$wan_ip" ] && wan_ip=$(ip -4 addr show eth0.2 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)
    [ -z "$wan_ip" ] && wan_ip=$(ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)
    [ -z "$wan_ip" ] && wan_ip="N/A"

    # Lấy ZeroTier IP nếu có
    local zt_ip
    zt_ip=$(get_zerotier_ip)
    local zt_line=""
    if [ -n "$zt_ip" ]; then
        zt_line="
🌐 <b>ZeroTier IP:</b> $(mask_ip "$zt_ip") <code>(Active)</code>"
    fi

    # Đếm số máy online thực tế
    local wifi_tmp="/tmp/vcrt_wifi_status.tmp"
    get_wifi_stations > "$wifi_tmp" 2>/dev/null
    local online_total
    online_total=$(wc -l < "$wifi_tmp" 2>/dev/null || echo 0)
    case "$online_total" in ''|*[!0-9]*) online_total=0 ;; esac

    # Bổ sung thiết bị cắm dây LAN (ARP phản hồi)
    if [ -f /proc/net/arp ]; then
        for l_ip in $(awk '$3=="0x2" && $6=="br-lan" {print $1}' /proc/net/arp 2>/dev/null); do
            local l_mac
            l_mac=$(awk -v ip="$l_ip" '$1==ip {print tolower($4); exit}' /proc/net/arp 2>/dev/null)
            if [ -n "$l_mac" ] && ! grep -qi "^${l_mac}|" "$wifi_tmp" 2>/dev/null; then
                if ping -c 1 -W 1 "$l_ip" >/dev/null 2>&1 || ip neigh show dev br-lan 2>/dev/null | grep -i "$l_mac" | grep -v "fe80" | grep -qE "REACHABLE|DELAY|PROBE|STALE"; then
                    online_total=$(( online_total + 1 ))
                fi
            fi
        done
    fi
    rm -f "$wifi_tmp" 2>/dev/null || true

    local ch_2g
    ch_2g=$(uci -q get wireless.radio1.channel || echo "6")
    local ch_5g
    ch_5g=$(uci -q get wireless.radio0.channel || echo "149")

    local msg="⬡ <b>VCRT OS · THÔNG TIN HỆ THỐNG ROUTER</b> ⬡
━━━━━━━━━━━━━━━━━━
🏷 <b>Thiết bị:</b> <code>${dev_name}</code>
🏷 <b>Hostname:</b> <code>${host}</code>
⏱ <b>Thời gian chạy:</b> <code>${up_str}</code>
⚙️ <b>CPU Load:</b> <code>${load}</code> ${cpu_ui}
💾 <b>Bộ nhớ RAM:</b> <code>${mem_used}MB / ${mem_total}MB (${mem_pct}%)</code>
💿 <b>Bộ nhớ Flash:</b> <code>${rom_used}</code>
🌐 <b>Địa chỉ WAN:</b> $(mask_wan_ip "${wan_ip}")${zt_line}
📶 <b>Wi-Fi Kênh:</b> <code>2.4G (CH ${ch_2g}) · 5G (CH ${ch_5g})</code>
👥 <b>Thiết bị ĐANG ONLINE:</b> <code>${online_total} máy</code>
━━━━━━━━━━━━━━━━━━
<i>Gõ /clients để xem danh sách máy (chạm từng máy để xem IP/MAC)</i>"
    send_msg "$msg" "$target_chat"
}

# ─── CMD 2: /clients — DANH SÁCH THIẾT BỊ ONLINE THỜI GIAN THỰC ─────────────
cmd_clients() {
    local target_chat="$1"
    local wifi_tmp="/tmp/vcrt_bot_wifi.tmp"
    local card_dir="/tmp/vcrt_cards_$$"
    rm -f "$wifi_tmp" 2>/dev/null || true
    rm -rf "$card_dir" 2>/dev/null || true
    mkdir -p "$card_dir" 2>/dev/null

    get_wifi_stations > "$wifi_tmp" 2>/dev/null

    local count=0
    local processed_macs=""

    # 1. Quét DHCP leases
    if [ -f /tmp/dhcp.leases ] && [ -s /tmp/dhcp.leases ]; then
        while read -r ltime mac ip name clid; do
            [ -z "$mac" ] && continue
            local mac_low
            mac_low=$(printf '%s' "$mac" | tr 'A-Z' 'a-z')
            processed_macs="${processed_macs} ${mac_low}"

            local disp_name
            disp_name=$(get_device_name "$mac_low")

            local icon="📱"
            printf '%s' "$disp_name" | grep -qi "lap\|pc\|mac\|win\|desktop" && icon="💻"
            printf '%s' "$disp_name" | grep -qi "tv\|tivi\|sony\|lg\|samsung\|tcl" && icon="📺"
            printf '%s' "$disp_name" | grep -qi "cam\|ipcam\|imou\|ezviz" && icon="📷"
            printf '%s' "$disp_name" | grep -qi "pad\|tab" && icon="📟"
            printf '%s' "$disp_name" | grep -qi "print\|epson\|canon\|hp" && icon="🖨"

            local is_online=0
            local conn_type="Cáp Mạng LAN 🔌 (Cổng Switch)"
            local time_str="Đang trực tuyến (Dây cáp LAN)"
            local sig_str=""
            local speed_str=""

            # Kiểm tra Wi-Fi thực tế
            local w_match
            w_match=$(grep -i "^${mac_low}|" "$wifi_tmp" 2>/dev/null | head -n1)
            if [ -n "$w_match" ]; then
                is_online=1
                local w_sig w_band w_con w_tx
                w_sig=$(printf '%s' "$w_match" | cut -d'|' -f3)
                w_band=$(printf '%s' "$w_match" | cut -d'|' -f4)
                w_con=$(printf '%s' "$w_match" | cut -d'|' -f5)
                w_tx=$(printf '%s' "$w_match" | cut -d'|' -f6)

                conn_type="Wi-Fi 2.4GHz 📶 (Xuyên tường)"
                [ "$w_band" = "5GHz" ] && conn_type="Wi-Fi 5GHz ⚡ (Tốc độ cao)"

                case "$w_con" in ''|*[!0-9]*) w_con=0 ;; esac
                time_str="Đang bắt sóng"
                if [ "$w_con" -gt 3600 ]; then
                    time_str="$(( w_con / 3600 )) giờ $(( (w_con % 3600) / 60 )) phút"
                elif [ "$w_con" -gt 60 ]; then
                    time_str="$(( w_con / 60 )) phút $(( w_con % 60 )) giây"
                elif [ "$w_con" -gt 0 ]; then
                    time_str="${w_con} giây"
                fi

                local sig_num
                sig_num=$(printf '%s' "$w_sig" | awk '{print int($1)}')
                local sig_badge="🟢 Tốt"
                [ "$sig_num" -ge -50 ] 2>/dev/null && sig_badge="🟢 Rất mạnh"
                [ "$sig_num" -le -75 ] 2>/dev/null && sig_badge="🔴 Yếu"
                [ -n "$w_sig" ] && [ "$w_sig" != "N/A" ] && sig_str="${w_sig} (${sig_badge})"
                [ -n "$w_tx" ] && [ "$w_tx" != "N/A" ] && speed_str="${w_tx}"
            fi

            # Kiểm tra cáp LAN thực tế
            if [ "$is_online" -eq 0 ]; then
                local a_match
                a_match=$(awk -v mac="$mac_low" 'tolower($4)==mac {print $0; exit}' /proc/net/arp 2>/dev/null)
                if [ -n "$a_match" ]; then
                    local a_flg
                    a_flg=$(printf '%s' "$a_match" | awk '{print $3}')
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
            fi

            # Kiểm tra tình trạng chặn mạng
            local block_badge=""
            local timed_file="${BLOCKS_TIMED_FILE:-/tmp/vcrt_blocks_timed.db}"
            local soft_file="${BLOCKED_SOFT_FILE:-/tmp/vcrt_blocked_soft.db}"
            if [ -f "$timed_file" ] && grep -qi "^${mac_low}|" "$timed_file" 2>/dev/null; then
                block_badge=" [⛔ ĐANG BỊ CHẶN]"
            elif [ -f "$soft_file" ] && grep -qi "^${mac_low}" "$soft_file" 2>/dev/null; then
                block_badge=" [⛔ ĐANG BỊ CHẶN]"
            fi

            # Bỏ qua nếu không online và không bị chặn
            if [ "$is_online" -eq 0 ] && [ -z "$block_badge" ]; then
                continue
            fi

            count=$(( count + 1 ))
            local mac_u
            mac_u=$(printf '%s' "$mac" | tr 'a-z' 'A-Z')

            cat << EOF > "$card_dir/card_${count}.txt"
${count}. ${icon} <b>${disp_name}</b>${block_badge}
━━━━━━━━━━━━━━━━━━
📍 <b>IP:</b> <tg-spoiler>${ip}</tg-spoiler>
🔑 <b>MAC:</b> <tg-spoiler>${mac_u}</tg-spoiler>
📡 <b>Kết nối:</b> <code>${conn_type}</code>
⏱ <b>Bắt sóng:</b> <code>${time_str}</code>
EOF
            [ -n "$sig_str" ] && printf "📶 <b>Tín hiệu:</b> <code>%s</code>\n" "$sig_str" >> "$card_dir/card_${count}.txt"
            [ -n "$speed_str" ] && printf "⚡ <b>Tốc độ:</b> <code>%s</code>\n" "$speed_str" >> "$card_dir/card_${count}.txt"
            [ -z "$speed_str" ] && printf "⚡ <b>Trạng thái:</b> <code>Sẵn sàng truyền dữ liệu</code>\n" >> "$card_dir/card_${count}.txt"
        done < /tmp/dhcp.leases
    fi

    # 2. Duyệt thiết bị Wi-Fi IP tĩnh không nằm trong DHCP Leases
    if [ -f "$wifi_tmp" ]; then
        while IFS='|' read -r sm_mac sm_ifc sm_sig sm_band sm_con sm_tx; do
            [ -z "$sm_mac" ] && continue
            if ! printf '%s\n' "$processed_macs" | grep -qi "$sm_mac"; then
                processed_macs="${processed_macs} ${sm_mac}"
                local s_ip
                s_ip=$(awk -v mac="$sm_mac" 'tolower($4)==mac {print $1; exit}' /proc/net/arp 2>/dev/null)
                [ -z "$s_ip" ] && s_ip="IP Tĩnh"

                local conn_type="Wi-Fi 2.4GHz 📶 (Xuyên tường)"
                [ "$sm_band" = "5GHz" ] && conn_type="Wi-Fi 5GHz ⚡ (Tốc độ cao)"

                case "$sm_con" in ''|*[!0-9]*) sm_con=0 ;; esac
                local time_str="Đang bắt sóng"
                if [ "$sm_con" -gt 3600 ]; then
                    time_str="$(( sm_con / 3600 )) giờ $(( (sm_con % 3600) / 60 )) phút"
                elif [ "$sm_con" -gt 60 ]; then
                    time_str="$(( sm_con / 60 )) phút $(( sm_con % 60 )) giây"
                elif [ "$sm_con" -gt 0 ]; then
                    time_str="${sm_con} giây"
                fi

                local sig_str=""
                local sig_num
                sig_num=$(printf '%s' "$sm_sig" | awk '{print int($1)}')
                local sig_badge="🟢 Tốt"
                [ "$sig_num" -ge -50 ] 2>/dev/null && sig_badge="🟢 Rất mạnh"
                [ "$sig_num" -le -75 ] 2>/dev/null && sig_badge="🔴 Yếu"
                [ -n "$sm_sig" ] && [ "$sm_sig" != "N/A" ] && sig_str="${sm_sig} (${sig_badge})"

                count=$(( count + 1 ))
                local sm_u
                sm_u=$(printf '%s' "$sm_mac" | tr 'a-z' 'A-Z')
                local s_name
                s_name=$(get_device_name "$sm_mac")

                cat << EOF > "$card_dir/card_${count}.txt"
${count}. 📱 <b>${s_name}</b>
━━━━━━━━━━━━━━━━━━
📍 <b>IP:</b> <tg-spoiler>${s_ip}</tg-spoiler>
🔑 <b>MAC:</b> <tg-spoiler>${sm_u}</tg-spoiler>
📡 <b>Kết nối:</b> <code>${conn_type}</code>
⏱ <b>Bắt sóng:</b> <code>${time_str}</code>
EOF
                [ -n "$sig_str" ] && printf "📶 <b>Tín hiệu:</b> <code>%s</code>\n" "$sig_str" >> "$card_dir/card_${count}.txt"
                [ -n "$sm_tx" ] && printf "⚡ <b>Tốc độ:</b> <code>%s</code>\n" "$sm_tx" >> "$card_dir/card_${count}.txt"
            fi
        done < "$wifi_tmp"
    fi
    rm -f "$wifi_tmp" 2>/dev/null || true

    if [ "$count" -eq 0 ]; then
        send_msg "📱 <b>DANH SÁCH THIẾT BỊ ĐANG ONLINE (0 máy)</b>
━━━━━━━━━━━━━━━━━━
<i>Hiện không có thiết bị nào đang kết nối sóng Wi-Fi hoặc cắm dây LAN.</i>" "$target_chat"
        rm -rf "$card_dir" 2>/dev/null || true
        return 0
    fi

    # Gửi Header thông báo tổng quan trước
    send_msg "📱 <b>DANH SÁCH THIẾT BỊ ĐANG ONLINE (${count} máy)</b>
━━━━━━━━━━━━━━━━━━
💡 <i>Chạm vào phần làm mờ để xem địa chỉ IP & MAC của từng thiết bị:</i>" "$target_chat"
    sleep 1

    local i=1
    while [ "$i" -le "$count" ]; do
        local cf="$card_dir/card_${i}.txt"
        if [ -f "$cf" ]; then
            local card_body
            card_body=$(cat "$cf")
            send_msg "$card_body" "$target_chat"
            sleep 1
        fi
        i=$(( i + 1 ))
    done
    rm -rf "$card_dir" 2>/dev/null || true
}

# ─── CMD 3: /traffic — BÁO CÁO LƯU LƯỢNG ĐA CHU KỲ ───────────────────────────
cmd_traffic() {
    local target_chat="$1"
    local daily_db="${TRAFFIC_DAILY_DB:-/etc/vcrt/traffic_daily.db}"
    local today_date
    today_date=$(date +%Y-%m-%d 2>/dev/null || echo "2026-09-15")
    local cur_year
    cur_year=$(date +%Y 2>/dev/null || echo "2026")
    local cur_month
    cur_month=$(date +%m 2>/dev/null || echo "09")

    local out
    out=$(awk \
    -v daily_file="$daily_db" \
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
    }' "$daily_db" 2>/dev/null)

    local sum_7d_rx=0 sum_7d_tx=0
    if [ -f "$daily_db" ]; then
        local d7
        d7=$(tail -n 7 "$daily_db" 2>/dev/null)
        for l in $d7; do
            r=$(printf '%s' "$l" | cut -d'|' -f2)
            t=$(printf '%s' "$l" | cut -d'|' -f3)
            sum_7d_rx=$(( sum_7d_rx + r ))
            sum_7d_tx=$(( sum_7d_tx + t ))
        done
    fi

    local s7_fmt
    s7_fmt=$(awk -v r="$sum_7d_rx" -v t="$sum_7d_tx" '
    function fmt(b) {
        if (b >= 1073741824) return sprintf("%.2f GB", b/1073741824);
        if (b >= 1048576) return sprintf("%.1f MB", b/1048576);
        return sprintf("%.1f KB", b/1024);
    }
    BEGIN { printf "%s|%s|%s\n", fmt(r), fmt(t), fmt(r+t); }
    ')

    local tod_line mon_line yr_line
    tod_line=$(printf '%s' "$out" | sed -n '1p')
    mon_line=$(printf '%s' "$out" | sed -n '2p')
    yr_line=$(printf '%s' "$out" | sed -n '3p')

    local msg="📊 <b>BÁO CÁO LƯU LƯỢNG SỬ DỤNG INTERNET</b>
━━━━━━━━━━━━━━━━━━
📅 <b>HÔM NAY (${today_date}):</b>
   ├ 🌐 Tổng cộng: <code>$(printf '%s' "$tod_line" | cut -d'|' -f3)</code>
   └ 📥 Tải về: <code>$(printf '%s' "$tod_line" | cut -d'|' -f1)</code> · 📤 Tải lên: <code>$(printf '%s' "$tod_line" | cut -d'|' -f2)</code>

🗓 <b>7 NGÀY GẦN NHẤT:</b>
   ├ 🌐 Tổng cộng: <code>$(printf '%s' "$s7_fmt" | cut -d'|' -f3)</code>
   └ 📥 Tải về: <code>$(printf '%s' "$s7_fmt" | cut -d'|' -f1)</code> · 📤 Tải lên: <code>$(printf '%s' "$s7_fmt" | cut -d'|' -f2)</code>

📆 <b>THÁNG NÀY (Tháng ${cur_month}/${cur_year}):</b>
   ├ 🌐 Tổng cộng: <code>$(printf '%s' "$mon_line" | cut -d'|' -f3)</code>
   └ 📥 Tải về: <code>$(printf '%s' "$mon_line" | cut -d'|' -f1)</code> · 📤 Tải lên: <code>$(printf '%s' "$mon_line" | cut -d'|' -f2)</code>

📈 <b>CẢ NĂM (${cur_year}):</b>
   ├ 🌐 Tổng cộng: <code>$(printf '%s' "$yr_line" | cut -d'|' -f3)</code>
   └ 📥 Tải về: <code>$(printf '%s' "$yr_line" | cut -d'|' -f1)</code> · 📤 Tải lên: <code>$(printf '%s' "$yr_line" | cut -d'|' -f2)</code>
━━━━━━━━━━━━━━━━━━
<i>Dữ liệu được đồng bộ 100% với Web Dashboard VCRT OS</i>"
    send_msg "$msg" "$target_chat"
}

# ─── CMD 4: /wifi — THÔNG SỐ PHÁT SÓNG & KẾT NỐI ─────────────────────────────
cmd_wifi() {
    local target_chat="$1"
    local ssid_2g
    ssid_2g=$(uci -q get wireless.default_radio1.ssid || uci -q get wireless.@wifi-iface[0].ssid || echo "Xiaomi_2.4G")
    local ch_2g
    ch_2g=$(uci -q get wireless.radio1.channel || echo "6")
    local ssid_5g
    ssid_5g=$(uci -q get wireless.default_radio0.ssid || uci -q get wireless.@wifi-iface[1].ssid || echo "Xiaomi_5G")
    local ch_5g
    ch_5g=$(uci -q get wireless.radio0.channel || echo "149")

    local wifi_tmp="/tmp/vcrt_wifi_cmd.tmp"
    get_wifi_stations > "$wifi_tmp" 2>/dev/null
    local cnt_5g
    cnt_5g=$(grep -c "|5GHz|" "$wifi_tmp" 2>/dev/null || echo 0)
    local cnt_24g
    cnt_24g=$(grep -c "|2.4GHz|" "$wifi_tmp" 2>/dev/null || echo 0)
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
<i>Gõ /clients để xem danh sách máy đang kết nối</i>"
    send_msg "$msg" "$target_chat"
}

# ─── CMD 5: /ping — ĐO ĐỘ TRỄ MẠNG INTERNET ──────────────────────────────────
cmd_ping() {
    local target_chat="$1"
    local p_out
    p_out=$(ping -c 3 -W 2 1.1.1.1 2>/dev/null)
    local rtt
    rtt=$(printf '%s' "$p_out" | awk -F'/' '/round-trip|rtt/{print $4, $5, $6}')
    local loss
    loss=$(printf '%s' "$p_out" | grep -o '[0-9]*% packet loss' | head -n1)

    if [ -n "$rtt" ]; then
        local min_ms avg_ms max_ms
        min_ms=$(printf '%s' "$rtt" | awk '{print $1}')
        avg_ms=$(printf '%s' "$rtt" | awk '{print $2}')
        max_ms=$(printf '%s' "$rtt" | awk '{print $3}')

        local qual="🟢 Rất tốt & Ổn định"
        local avg_int
        avg_int=$(printf '%s' "$avg_ms" | awk '{print int($1)}')
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
        send_msg "$msg" "$target_chat"
    else
        send_msg "❌ <b>Mất kết nối Internet!</b> Không thể gửi gói tin ping đến Cloudflare DNS." "$target_chat"
    fi
}

# ─── CMD 6: /speed — ĐO TỐC ĐỘ TẢI XUỐNG INTERNET (MỚI) ──────────────────────
cmd_speed() {
    local target_chat="$1"
    send_msg "⚡ <i>Đang đo tốc độ tải xuống Internet qua Cloudflare CDN... Vui lòng đợi 5-10 giây...</i>" "$target_chat"

    # Tải 5MB dữ liệu từ Cloudflare CDN và đo tốc độ byte/s và thời gian
    local res
    res=$(curl -s -w "%{speed_download} %{time_total}" -o /dev/null -m 15 "https://speed.cloudflare.com/__down?bytes=5000000" 2>/dev/null)

    local bps dur
    bps=$(printf '%s' "$res" | awk '{print $1}')
    dur=$(printf '%s' "$res" | awk '{print $2}')

    case "$bps" in ''|*[!0-9.]*) bps=0 ;; esac
    case "$dur" in ''|*[!0-9.]*) dur=0 ;; esac

    if [ "$(printf '%s' "$bps" | awk '{print ($1 > 0)?1:0}')" = "1" ]; then
        local mbps
        mbps=$(awk -v b="$bps" 'BEGIN { printf "%.2f", (b * 8) / 1000000; }')
        local msg="🚀 <b>KẾT QUẢ ĐO TỐC ĐỘ INTERNET (DOWNLOAD)</b>
━━━━━━━━━━━━━━━━━━
📥 <b>Tốc độ tải về:</b> <code>${mbps} Mbps</code>
⏱ <b>Thời gian kiểm tra:</b> <code>${dur} giây</code>
📦 <b>Gói dữ liệu thử nghiệm:</b> <code>5.00 MB</code>
🌐 <b>Máy chủ kiểm tra:</b> <code>Cloudflare Global CDN</code>
━━━━━━━━━━━━━━━━━━
<i>Đo trực tiếp từ router VCRT OS ra đường truyền WAN</i>"
        send_msg "$msg" "$target_chat"
    else
        send_msg "⚠️ <b>Không thể đo tốc độ!</b> Đường truyền bận hoặc máy chủ thử nghiệm không phản hồi." "$target_chat"
    fi
}

# ─── CMD 7: /nextdns — TRẠNG THÁI NEXTDNS CLOUD (MỚI) ────────────────────────
cmd_nextdns() {
    local target_chat="$1"
    local conf_file="${NEXTDNS_CONF_FILE:-/etc/vcrt_nextdns_profile}"
    local linked_tmp="${NEXTDNS_LINKED_IP_TMP:-/tmp/vcrt_nextdns_linked_ip.tmp}"

    local prof=""
    [ -f "$conf_file" ] && prof=$(cat "$conf_file" 2>/dev/null | tr -d ' \r\n')
    [ -z "$prof" ] && [ -f /etc/dnsmasq.conf ] && prof=$(grep "add-cpe-id=" /etc/dnsmasq.conf 2>/dev/null | head -n1 | cut -d= -f2 | tr -d ' \r\n')
    [ -z "$prof" ] && prof="Chưa cấu hình"

    local linked_ip=""
    [ -f "$linked_tmp" ] && linked_ip=$(cat "$linked_tmp" 2>/dev/null | tr -d '\r\n')
    [ -z "$linked_ip" ] && linked_ip="Chưa kích hoạt"

    # Kiểm tra trực tiếp NextDNS
    local test_json
    test_json=$(curl -s --max-time 4 "https://test.nextdns.io" 2>/dev/null)
    local status_badge="🔴 Chưa kết nối"
    local protocol="N/A"
    local test_prof="N/A"

    if printf '%s' "$test_json" | grep -q '"status":"ok"'; then
        status_badge="🟢 Đang kích hoạt & Bảo vệ"
        protocol=$(printf '%s' "$test_json" | grep -o '"protocol":"[^"]*"' | cut -d'"' -f4)
        test_prof=$(printf '%s' "$test_json" | grep -o '"profile":"[^"]*"' | cut -d'"' -f4)
    fi

    local msg="🛡 <b>TRẠNG THÁI NEXTDNS SECURITY CLOUD</b>
━━━━━━━━━━━━━━━━━━
🏷 <b>Mã Profile:</b> <code>${prof}</code>
📶 <b>Tình trạng:</b> ${status_badge}
⚡ <b>Giao thức DNS:</b> <code>${protocol}</code>
🔗 <b>Linked IP:</b> <code>${linked_ip}</code>
━━━━━━━━━━━━━━━━━━
<i>Chặn quảng cáo, mã độc và quản lý trẻ em từ đám mây NextDNS</i>"
    send_msg "$msg" "$target_chat"
}

# ─── CMD 8: /backup — SAO LƯU CẤU HÌNH VÀ GỬI FILE QUA BOT (MỚI) ─────────────
cmd_backup() {
    local target_chat="$1"
    send_msg "📦 <i>Đang đóng gói dữ liệu cấu hình hệ thống VCRT OS... Vui lòng đợi trong giây lát...</i>" "$target_chat"

    local stamp
    stamp=$(date +%Y%m%d_%H%M%S 2>/dev/null || echo "backup")
    local tar_file="/tmp/vcrt_backup_${stamp}.tar.gz"

    tar -czf "$tar_file" /etc/config /etc/vcrt 2>/dev/null || true

    if [ -f "$tar_file" ] && [ -s "$tar_file" ]; then
        local f_size
        f_size=$(ls -lh "$tar_file" 2>/dev/null | awk '{print $5}')
        local caption="📦 <b>BẢN SAO LƯU CẤU HÌNH VCRT OS</b>
━━━━━━━━━━━━━━━━━━
⏰ Ngày tạo: <code>$(date '+%d/%m/%Y %H:%M:%S' 2>/dev/null)</code>
📁 Dung lượng: <code>${f_size}</code>
━━━━━━━━━━━━━━━━━━
<i>Bao gồm toàn bộ file cấu hình mạng (/etc/config) và dữ liệu VCRT (/etc/vcrt).</i>"
        send_document "$target_chat" "$tar_file" "$caption"
        rm -f "$tar_file" 2>/dev/null || true
    else
        send_msg "❌ <b>Lỗi!</b> Không thể tạo file sao lưu hệ thống." "$target_chat"
    fi
}

# ─── CMD 9: /block — CHẶN THIẾT BỊ CÓ HẸN GIỜ ─────────────────────────────────
cmd_block() {
    local target_mac="$1"
    local dur="$2"
    local target_chat="$3"
    [ -z "$dur" ] && dur=30

    if [ -z "$target_mac" ]; then
        send_msg "⚠️ <b>Cú pháp lệnh chưa đúng!</b>
Vui lòng nhập: <code>/block &lt;Địa_chỉ_MAC&gt; [Số_phút]</code>
Ví dụ: <code>/block 00:11:22:33:44:55 60</code>" "$target_chat"
        return 1
    fi

    local target_mac_low
    target_mac_low=$(printf '%s' "$target_mac" | tr 'A-Z' 'a-z')
    local now_epoch
    now_epoch=$(date +%s 2>/dev/null || echo 0)
    local expire=$(( now_epoch + dur * 60 ))

    local timed_file="${BLOCKS_TIMED_FILE:-/tmp/vcrt_blocks_timed.db}"
    local soft_file="${BLOCKED_SOFT_FILE:-/tmp/vcrt_blocked_soft.db}"

    iptables -D FORWARD -m mac --mac-source "$target_mac_low" -j DROP 2>/dev/null || true
    iptables -I FORWARD -m mac --mac-source "$target_mac_low" -j DROP

    printf '%s\n' "$target_mac_low" >> "$soft_file"
    [ -f "$timed_file" ] && grep -v -i "^${target_mac_low}|" "$timed_file" > "${timed_file}.tmp" 2>/dev/null || true
    mv "${timed_file}.tmp" "$timed_file" 2>/dev/null || true
    printf '%s|soft|%s|%s|%s|Telegram-Block|N/A\n' "$target_mac_low" "$now_epoch" "$expire" "$dur" >> "$timed_file"

    local m_tmac
    m_tmac=$(mask_mac "$target_mac")
    local msg="⛔ <b>ĐÃ CHẶN KẾT NỐI INTERNET!</b>
━━━━━━━━━━━━━━━━━━
🔑 <b>MAC:</b> ${m_tmac}
⏱ <b>Thời hạn chặn:</b> <code>${dur} phút</code>
━━━━━━━━━━━━━━━━━━
<i>Hệ thống sẽ tự động mở lại mạng khi hết giờ hoặc gõ /unblock ${target_mac}</i>"
    send_msg "$msg" "$target_chat"
}

# ─── CMD 10: /unblock — MỞ CHẶN MẠNG THIẾT BỊ ─────────────────────────────────
cmd_unblock() {
    local target_mac="$1"
    local target_chat="$2"
    if [ -z "$target_mac" ]; then
        send_msg "⚠️ <b>Cú pháp lệnh chưa đúng!</b>
Vui lòng nhập: <code>/unblock &lt;Địa_chỉ_MAC&gt;</code>
Ví dụ: <code>/unblock 00:11:22:33:44:55</code>" "$target_chat"
        return 1
    fi

    local target_mac_low
    target_mac_low=$(printf '%s' "$target_mac" | tr 'A-Z' 'a-z')
    local timed_file="${BLOCKS_TIMED_FILE:-/tmp/vcrt_blocks_timed.db}"
    local soft_file="${BLOCKED_SOFT_FILE:-/tmp/vcrt_blocked_soft.db}"
    local hard_file="${BLOCKED_HARD_FILE:-/tmp/vcrt_blocked_hard.db}"

    iptables -D FORWARD -m mac --mac-source "$target_mac_low" -j DROP 2>/dev/null || true
    iptables -D INPUT -m mac --mac-source "$target_mac_low" -j DROP 2>/dev/null || true

    if [ -f "$soft_file" ]; then
        grep -v -i "$target_mac_low" "$soft_file" > "${soft_file}.tmp" 2>/dev/null || true
        mv "${soft_file}.tmp" "$soft_file" 2>/dev/null || true
    fi
    if [ -f "$hard_file" ]; then
        grep -v -i "$target_mac_low" "$hard_file" > "${hard_file}.tmp" 2>/dev/null || true
        mv "${hard_file}.tmp" "$hard_file" 2>/dev/null || true
    fi
    if [ -f "$timed_file" ]; then
        grep -v -i "^${target_mac_low}|" "$timed_file" > "${timed_file}.tmp" 2>/dev/null || true
        mv "${timed_file}.tmp" "$timed_file" 2>/dev/null || true
    fi

    local m_tmac
    m_tmac=$(mask_mac "$target_mac")
    local msg="🔓 <b>ĐÃ MỞ LẠI KẾT NỐI INTERNET!</b>
━━━━━━━━━━━━━━━━━━
🔑 <b>MAC:</b> ${m_tmac}
━━━━━━━━━━━━━━━━━━
<i>Thiết bị đã có thể truy cập mạng bình thường.</i>"
    send_msg "$msg" "$target_chat"
}

# ─── CMD 11: /update — KIỂM TRA & NÂNG CẤP HỆ ĐIỀU HÀNH ───────────────────────
cmd_update() {
    local sub_arg="$1"
    local target_chat="$2"
    local ver_file="${VERSION_FILE:-/etc/vcrt/version}"
    local cur_ver
    cur_ver=$(cat "$ver_file" 2>/dev/null || echo "2.0.0")

    if [ "$sub_arg" = "now" ] || [ "$sub_arg" = "install" ] || [ "$sub_arg" = "yes" ]; then
        send_msg "🚀 <b>ĐANG CẬP NHẬT VCRT OS TỪ GITHUB...</b>
━━━━━━━━━━━━━━━━━━
<i>Hệ thống đang tải gói deploy_vcrt.tar.gz và tự động cài đặt. Dịch vụ sẽ tự khởi động lại sau giây lát...</i>" "$target_chat"
        (
            curl -s -L -k -o /tmp/deploy_vcrt.tar.gz "https://raw.githubusercontent.com/lecuong2512/vcrt/main/deploy_vcrt.tar.gz" && \
            cd /tmp && tar -xzf deploy_vcrt.tar.gz && sh install.sh
        ) >/dev/null 2>&1 &
        return 0
    fi

    local remote_ver
    remote_ver=$(curl -s --max-time 5 "https://raw.githubusercontent.com/lecuong2512/vcrt/main/version" 2>/dev/null | tr -d ' \r\n"')
    if [ -z "$remote_ver" ] || ! printf '%s' "$remote_ver" | grep -qE '^[0-9]+(\.[0-9]+)+$'; then
        send_msg "⚠️ <b>Không thể kiểm tra phiên bản mới trên GitHub!</b>
━━━━━━━━━━━━━━━━━━
<i>Phiên bản hiện tại của router: <code>v${cur_ver}</code>
Vui lòng kiểm tra lại kết nối Internet hoặc thử lại sau.</i>" "$target_chat"
        return 1
    fi

    if [ "$cur_ver" = "$remote_ver" ]; then
        send_msg "✅ <b>Hệ thống đang chạy phiên bản mới nhất!</b>
━━━━━━━━━━━━━━━━━━
🏷 <b>Phiên bản VCRT OS:</b> <code>v${cur_ver}</code>
🛡 Tất cả tính năng và bản vá bảo mật đã được cập nhật đầy đủ." "$target_chat"
    else
        send_msg "🚀 <b>PHÁT HIỆN BẢN CẬP NHẬT MỚI: v${remote_ver}</b>
━━━━━━━━━━━━━━━━━━
🏷 <b>Phiên bản hiện tại:</b> <code>v${cur_ver}</code>
✨ <b>Phiên bản mới nhất:</b> <code>v${remote_ver}</code>
━━━━━━━━━━━━━━━━━━
Gõ hoặc bấm <code>/update now</code> để tự động nâng cấp ngay lập tức!" "$target_chat"
    fi
}

# ─── CMD 12: /reboot — KHỞI ĐỘNG LẠI ROUTER ──────────────────────────────────
cmd_reboot() {
    local target_chat="$1"
    send_msg "⚠️ <b>Đang khởi động lại router trong 3 giây...</b>" "$target_chat"
    sleep 3
    /sbin/reboot
}

# ─── CMD 13: /logo — THÔNG TIN BIỂU TƯỢNG VCRT OS ────────────────────────────
cmd_logo() {
    local target_chat="$1"
    local msg="⬡ <b>VCRT OS v2.0 · CYBER ROUTER SYSTEM</b> ⬡
━━━━━━━━━━━━━━━━━━
🛡 <b>Hệ Điều Hành Router Thông Minh Đa Nhiệm</b>
⚡ Kiến trúc Micro-Daemon hiệu năng cao trên OpenWrt
🎨 Giao diện Cyberpunk Dark Neon thời gian thực
🌐 Tích hợp VPN ZeroTier & NextDNS Cloud Security
🤖 Trợ lý điều hành tự động hóa Telegram Bot 24/7"
    send_msg "$msg" "$target_chat"
}

# ─── CMD 14: /help — BẢNG HƯỚNG DẪN ĐIỀU KHIỂN ───────────────────────────────
cmd_help() {
    local target_chat="$1"
    local msg="🤖 <b>VCRT OS v2.0 · TRỢ LÝ ĐIỀU HÀNH ROUTER 24/7</b>
━━━━━━━━━━━━━━━━━━
Bấm trực tiếp vào các lệnh bên dưới để thực thi:

⚡ /status - Xem CPU, RAM, Uptime, WAN & ZeroTier IP
📱 /clients - Danh sách thiết bị ĐANG ONLINE thực tế
📊 /traffic - Thống kê dung lượng mạng đa chu kỳ
📶 /wifi - Thông số phát sóng Wi-Fi 2.4G & 5G
🏓 /ping - Đo độ trễ Internet Cloudflare DNS
🚀 /speed - Đo tốc độ tải về Internet WAN
🛡 /nextdns - Trạng thái bảo mật NextDNS Cloud
📦 /backup - Sao lưu cấu hình gửi file qua Telegram
⛔ /block &lt;mac&gt; [phút] - Chặn mạng có hẹn giờ
🔓 /unblock &lt;mac&gt; - Mở mạng lại ngay lập tức
🔄 /update - Kiểm tra & nâng cấp hệ điều hành
🔄 /reboot - Khởi động lại router từ xa
⬡ /logo - Giới thiệu hệ điều hành VCRT OS
❓ /help - Bảng hướng dẫn sử dụng
━━━━━━━━━━━━━━━━━━
<i>Hỗ trợ gõ trực tiếp chữ thường không dấu hoặc bấm nút bàn phím bên dưới!</i>"
    send_msg "$msg" "$target_chat"
}

cmd_unknown() {
    local entered="$1"
    local target_chat="$2"
    local msg="⚠️ <b>Lệnh không xác định:</b> <code>${entered}</code>
━━━━━━━━━━━━━━━━━━
Bấm <b>/help</b> để xem bảng lệnh hoặc bấm trực tiếp các nút menu ở bàn phím bên dưới."
    send_msg "$msg" "$target_chat"
}
