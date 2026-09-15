#!/bin/sh
# ==============================================================================
# VCRT OS v2.0 - Telegram Bot Background Watchers Daemon
# 4 Core Watchers: Wi-Fi live join, Timed block expire, Traffic DB, System update
# BusyBox POSIX Shell Standard - Ultra-lightweight & Optimized
# ==============================================================================

# ─── WATCHER 1: THEO DÕI THIẾT BỊ WI-FI MỚI (LIVE JOIN MONITOR) ──────────────
watch_wifi_devices() {
    local last_macs=""
    local wifi_tmp="/tmp/vcrt_wifi_watch.tmp"

    while true; do
        sleep 3
        load_config
        [ "$BOT_ENABLED" != "1" ] && continue
        [ "$NOTIF_WIFI_JOIN" != "1" ] && continue
        [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ] && continue

        get_wifi_stations > "$wifi_tmp" 2>/dev/null
        local curr_macs
        curr_macs=$(awk -F'|' '{print tolower($1)}' "$wifi_tmp" 2>/dev/null | sort -u)

        if [ -n "$last_macs" ]; then
            for m in $curr_macs; do
                if ! printf '%s\n' "$last_macs" | grep -qi "^${m}$"; then
                    sleep 1
                    local mac_up
                    mac_up=$(printf '%s' "$m" | tr 'a-z' 'A-Z')

                    local ip
                    ip=$(awk -v mac="$m" 'tolower($2)==tolower(mac) {print $3; exit}' /tmp/dhcp.leases 2>/dev/null)
                    [ -z "$ip" ] && ip=$(awk -v mac="$m" 'tolower($4)==tolower(mac) {print $1; exit}' /proc/net/arp 2>/dev/null)
                    [ -z "$ip" ] && ip="Đang nhận IP..."

                    local name
                    name=$(get_device_name "$m")

                    local st_match
                    st_match=$(grep -i "^${m}|" "$wifi_tmp" 2>/dev/null | head -n1)
                    local w_band
                    w_band=$(printf '%s' "$st_match" | cut -d'|' -f4)
                    local w_sig
                    w_sig=$(printf '%s' "$st_match" | cut -d'|' -f3)

                    local band="Wi-Fi"
                    [ "$w_band" = "5GHz" ] && band="5GHz ⚡ (Tốc độ cao)"
                    [ "$w_band" = "2.4GHz" ] && band="2.4GHz 📶 (Xuyên tường)"
                    [ -n "$w_sig" ] && [ "$w_sig" != "N/A" ] && band="${band} · Tín hiệu: ${w_sig}"

                    local now_str
                    now_str=$(date +'%H:%M:%S - %d/%m/%Y' 2>/dev/null || echo "")
                    local m_ip
                    m_ip=$(mask_ip "$ip")
                    local m_mac
                    m_mac=$(mask_mac "$mac_up")

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
    local timed_file="${BLOCKS_TIMED_FILE:-/tmp/vcrt_blocks_timed.db}"
    local soft_file="${BLOCKED_SOFT_FILE:-/tmp/vcrt_blocked_soft.db}"
    local hard_file="${BLOCKED_HARD_FILE:-/tmp/vcrt_blocked_hard.db}"

    while true; do
        sleep 2
        [ ! -f "$timed_file" ] && continue

        local now_epoch
        now_epoch=$(date +%s 2>/dev/null || echo 0)
        [ "$now_epoch" -eq 0 ] && continue

        local need_update=0
        local temp_file="/tmp/vcrt_blocks_timed.tmp"
        : > "$temp_file"

        while IFS='|' read -r b_mac b_type b_start b_expire b_dur b_name b_ip; do
            [ -z "$b_mac" ] && continue
            if [ "$b_expire" -gt 0 ] && [ "$now_epoch" -ge "$b_expire" ] 2>/dev/null; then
                iptables -D FORWARD -m mac --mac-source "$b_mac" -j DROP 2>/dev/null || true
                iptables -D INPUT -m mac --mac-source "$b_mac" -j DROP 2>/dev/null || true

                if [ -f "$soft_file" ]; then
                    grep -v -i "$b_mac" "$soft_file" > "${soft_file}.tmp" 2>/dev/null || true
                    mv "${soft_file}.tmp" "$soft_file" 2>/dev/null || true
                fi
                if [ -f "$hard_file" ]; then
                    grep -v -i "$b_mac" "$hard_file" > "${hard_file}.tmp" 2>/dev/null || true
                    mv "${hard_file}.tmp" "$hard_file" 2>/dev/null || true
                fi
                need_update=1

                load_config
                if [ "$BOT_ENABLED" = "1" ] && [ "$NOTIF_BLOCK_EXPIRE" = "1" ]; then
                    [ -z "$b_name" ] && b_name=$(get_device_name "$b_mac")
                    local m_ip
                    m_ip=$(mask_ip "$b_ip")
                    local m_mac
                    m_mac=$(mask_mac "$b_mac")
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
                printf '%s|%s|%s|%s|%s|%s|%s\n' "$b_mac" "$b_type" "$b_start" "$b_expire" "$b_dur" "$b_name" "$b_ip" >> "$temp_file"
            fi
        done < "$timed_file"

        if [ "$need_update" -eq 1 ]; then
            mv -f "$temp_file" "$timed_file" 2>/dev/null || true
        else
            rm -f "$temp_file" 2>/dev/null || true
        fi
    done
}

# ─── WATCHER 3: TÍCH LŨY LƯU LƯỢNG NGẦM (24/7 TRAFFIC RECORDER & REPORT) ─────
record_traffic_periodically() {
    local daily_db="${TRAFFIC_DAILY_DB:-/etc/vcrt/traffic_daily.db}"
    local hourly_db="${TRAFFIC_HOURLY_DB:-/etc/vcrt/traffic_hourly.db}"
    local prev_file="${PREV_WAN_BYTES:-/tmp/vcrt_prev_wan_bytes.tmp}"
    local rep_date_file="/tmp/vcrt_reported_date.tmp"

    while true; do
        sleep 60
        local def_dev
        def_dev=$(ip route 2>/dev/null | awk '/^default/{print $5; exit}')
        [ -z "$def_dev" ] && def_dev=$(route -n 2>/dev/null | awk '/^0.0.0.0/{print $8; exit}')
        [ -z "$def_dev" ] && def_dev="eth0.2"

        local cur_rx=0
        local cur_tx=0
        if [ -n "$def_dev" ] && grep -q "${def_dev}:" /proc/net/dev 2>/dev/null; then
            cur_rx=$(awk -v ifn="${def_dev}:" '$1==ifn {print $2}' /proc/net/dev 2>/dev/null || echo 0)
            cur_tx=$(awk -v ifn="${def_dev}:" '$1==ifn {print $10}' /proc/net/dev 2>/dev/null || echo 0)
        fi
        [ "$cur_rx" -eq 0 ] 2>/dev/null && [ -f /sys/class/net/eth0/statistics/rx_bytes ] && cur_rx=$(cat /sys/class/net/eth0/statistics/rx_bytes 2>/dev/null || echo 0)
        [ "$cur_tx" -eq 0 ] 2>/dev/null && [ -f /sys/class/net/eth0/statistics/tx_bytes ] && cur_tx=$(cat /sys/class/net/eth0/statistics/tx_bytes 2>/dev/null || echo 0)

        case "$cur_rx" in ''|*[!0-9]*) cur_rx=0 ;; esac
        case "$cur_tx" in ''|*[!0-9]*) cur_tx=0 ;; esac

        local today_date
        today_date=$(date +%Y-%m-%d 2>/dev/null || echo "2026-09-15")
        local today_hour
        today_hour=$(date +%H 2>/dev/null || echo "12")

        local delta_rx=0
        local delta_tx=0
        if [ -f "$prev_file" ]; then
            local p_rx=0 p_tx=0
            read -r p_rx p_tx < "$prev_file" 2>/dev/null
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
            if ! grep -q "^${today_date}|" "$daily_db" 2>/dev/null; then
                delta_rx="$cur_rx"
                delta_tx="$cur_tx"
            fi
        fi
        printf '%s %s\n' "$cur_rx" "$cur_tx" > "$prev_file" 2>/dev/null

        if [ "$delta_rx" -gt 0 ] 2>/dev/null || [ "$delta_tx" -gt 0 ] 2>/dev/null; then
            # Cập nhật Daily DB
            if [ -f "$daily_db" ] && grep -q "^${today_date}|" "$daily_db" 2>/dev/null; then
                awk -F'|' -v cur_d="$today_date" -v drx="$delta_rx" -v dtx="$delta_tx" '
                $1 == cur_d { printf "%s|%d|%d\n", $1, $2 + drx, $3 + dtx; next; }
                { print $0; }
                ' "$daily_db" > "${daily_db}.tmp" 2>/dev/null && mv -f "${daily_db}.tmp" "$daily_db"
            else
                printf '%s|%s|%s\n' "$today_date" "$delta_rx" "$delta_tx" >> "$daily_db" 2>/dev/null
            fi

            # Cập nhật Hourly DB
            local cur_h_key="${today_date} ${today_hour}"
            if [ -f "$hourly_db" ] && grep -q "^${cur_h_key}|" "$hourly_db" 2>/dev/null; then
                awk -F'[ |]' -v cur_k="$cur_h_key" -v drx="$delta_rx" -v dtx="$delta_tx" '
                ($1 " " $2) == cur_k { printf "%s %s|%d|%d\n", $1, $2, $3 + drx, $4 + dtx; next; }
                { print $0; }
                ' "$hourly_db" > "${hourly_db}.tmp" 2>/dev/null && mv -f "${hourly_db}.tmp" "$hourly_db"
            else
                printf '%s|%s|%s\n' "$cur_h_key" "$delta_rx" "$delta_tx" >> "$hourly_db" 2>/dev/null
            fi
        fi

        # Giữ database hourly tối đa 100 dòng tiết kiệm bộ nhớ flash
        if [ -f "$hourly_db" ] && [ "$(wc -l < "$hourly_db" 2>/dev/null || echo 0)" -gt 150 ]; then
            tail -n 100 "$hourly_db" > "${hourly_db}.tmp" 2>/dev/null && mv -f "${hourly_db}.tmp" "$hourly_db"
        fi

        # ─── BÁO CÁO ĐỊNH KỲ HÀNG NGÀY (DAILY NOTIFICATION) ──────────────────
        load_config
        if [ "$BOT_ENABLED" = "1" ] && [ "$NOTIF_DAILY_REPORT" = "1" ]; then
            local cur_h_num
            cur_h_num=$(printf '%s' "$today_hour" | awk '{print int($1)}')
            local rep_h_num
            rep_h_num=$(printf '%s' "${DAILY_REPORT_HOUR:-20}" | awk '{print int($1)}')

            if [ "$cur_h_num" -ge "$rep_h_num" ]; then
                local last_rep=""
                [ -f "$rep_date_file" ] && read -r last_rep < "$rep_date_file" 2>/dev/null
                if [ "$last_rep" != "$today_date" ]; then
                    local t_line
                    t_line=$(grep "^${today_date}|" "$daily_db" 2>/dev/null | tail -n 1)
                    local r_b=0 t_b=0
                    if [ -n "$t_line" ]; then
                        r_b=$(printf '%s' "$t_line" | cut -d'|' -f2)
                        t_b=$(printf '%s' "$t_line" | cut -d'|' -f3)
                    fi

                    local dl_str
                    dl_str=$(format_bytes "$r_b")
                    local ul_str
                    ul_str=$(format_bytes "$t_b")
                    local tot_str
                    tot_str=$(format_bytes "$(( r_b + t_b ))")

                    # Lấy số máy online thực tế
                    local real_online
                    real_online=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | while read -r w; do
                        [ "$w" = "phy0-sta0" ] && continue
                        iw dev "$w" station dump 2>/dev/null | awk '/Station/{print $2}'
                    done | sort -u | wc -l)
                    case "$real_online" in ''|*[!0-9]*) real_online=0 ;; esac

                    local rep_msg="📊 <b>BÁO CÁO LƯU LƯỢNG HÔM NAY (${today_date})</b>
━━━━━━━━━━━━━━━━━━
📥 <b>Tải về (DL):</b> <code>${dl_str}</code>
📤 <b>Tải lên (UL):</b> <code>${ul_str}</code>
📦 <b>Tổng lưu lượng:</b> <code>${tot_str}</code>
📱 <b>Thiết bị đang online:</b> <code>${real_online} máy</code>
━━━━━━━━━━━━━━━━━━
<i>Báo cáo định kỳ lúc ${DAILY_REPORT_HOUR}:00 từ router VCRT OS</i>"
                    send_msg "$rep_msg"
                    printf '%s' "$today_date" > "$rep_date_file" 2>/dev/null
                fi
            fi
        fi
    done
}

# ─── WATCHER 4: THEO DÕI BẢN CẬP NHẬT HỆ THỐNG & ZEROTIER VPN ───────────────
watch_system_updates() {
    local ver_file="${VERSION_FILE:-/etc/vcrt/version}"
    local zt_prev_file="/tmp/vcrt_zt_last_ip.tmp"

    while true; do
        sleep 21600
        load_config

        # 1. Kiểm tra cập nhật VCRT OS trên GitHub
        local cur_ver
        cur_ver=$(cat "$ver_file" 2>/dev/null || echo "2.0.0")
        local remote_ver
        remote_ver=$(curl -s --max-time 5 "https://raw.githubusercontent.com/lecuong2512/vcrt/main/version" 2>/dev/null | tr -d ' \r\n"')

        if [ -n "$remote_ver" ] && [ "$cur_ver" != "$remote_ver" ] && printf '%s' "$remote_ver" | grep -qE '^[0-9]+(\.[0-9]+)+$'; then
            if [ "$AUTO_UPDATE" = "1" ]; then
                send_msg "🚀 <b>TỰ ĐỘNG CẬP NHẬT VCRT OS: v${remote_ver}</b>
━━━━━━━━━━━━━━━━━━
⚙️ Đang tải và cài đặt bản cập nhật mới nhất theo cài đặt của bạn..."
                (
                    curl -s -L -k -o /tmp/deploy_vcrt.tar.gz "https://raw.githubusercontent.com/lecuong2512/vcrt/main/deploy_vcrt.tar.gz" && \
                    cd /tmp && tar -xzf deploy_vcrt.tar.gz && sh install.sh
                ) >/dev/null 2>&1 &
            else
                send_msg "🔔 <b>THÔNG BÁO BẢN CẬP NHẬT MỚI: v${remote_ver}</b>
━━━━━━━━━━━━━━━━━━
🏷 Phiên bản hiện tại: <code>v${cur_ver}</code>
✨ Phiên bản mới: <code>v${remote_ver}</code>
━━━━━━━━━━━━━━━━━━
Gõ hoặc bấm <code>/update now</code> để cập nhật ngay lập tức!"
            fi
        fi

        # 2. Kiểm tra trạng thái ZeroTier IP
        local cur_zt_ip
        cur_zt_ip=$(get_zerotier_ip)
        if [ -n "$cur_zt_ip" ]; then
            local prev_zt_ip=""
            [ -f "$zt_prev_file" ] && read -r prev_zt_ip < "$zt_prev_file" 2>/dev/null
            if [ "$cur_zt_ip" != "$prev_zt_ip" ]; then
                printf '%s' "$cur_zt_ip" > "$zt_prev_file" 2>/dev/null
                send_msg "🌐 <b>KẾT NỐI ZEROTIER VPN HOẠT ĐỘNG!</b>
━━━━━━━━━━━━━━━━━━
🔑 <b>Địa chỉ IP:</b> <code>${cur_zt_ip}</code>
🌍 <b>Truy cập từ xa:</b> http://${cur_zt_ip}/vcrt/
━━━━━━━━━━━━━━━━━━
<i>Hệ thống quản lý từ xa VCRT OS đã sẵn sàng.</i>"
            fi
        fi
    done
}
