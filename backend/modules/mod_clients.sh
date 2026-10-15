#!/bin/sh
# VCRT OS v2.0 - Clients Management Module (High Performance Edition)
# Endpoints: clients, soft_block, hard_block, unblock

: "${BLOCKS_TIMED_FILE:=/etc/vcrt/blocks_timed.db}"
: "${BLOCKED_SOFT_FILE:=/etc/vcrt/blocked_soft.db}"
: "${BLOCKED_HARD_FILE:=/etc/vcrt/blocked_hard.db}"
: "${DEVICE_NAMES_FILE:=/etc/vcrt/device_names}"
: "${TELEGRAM_CONF:=/etc/vcrt/telegram.conf}"

send_telegram_event() {
    local text="$1"
    [ ! -f "$TELEGRAM_CONF" ] && return 0
    local b_en
    b_en=$(awk -F= '/^(BOT_ENABLED|bot_enabled)/{gsub(/[ "\r\n]/,"",$2); print $2}' "$TELEGRAM_CONF" 2>/dev/null)
    [ "$b_en" != "1" ] && return 0
    local tok cid
    tok=$(awk -F= '/^(BOT_TOKEN|bot_token)/{gsub(/[ "\r\n]/,"",$2); print $2}' "$TELEGRAM_CONF" 2>/dev/null | sed 's/%3A/:/g; s/%3a/:/g')
    cid=$(awk -F= '/^(CHAT_ID|chat_id)/{gsub(/[ "\r\n]/,"",$2); print $2}' "$TELEGRAM_CONF" 2>/dev/null | sed 's/%20/ /g; s/%2C/,/g; s/%2c/,/g; s/+/ /g')
    [ -z "$tok" ] || [ -z "$cid" ] && return 0

    for one_cid in $(echo "$cid" | tr ',;' ' '); do
        [ -z "$one_cid" ] && continue
        curl -4 --tlsv1.2 -s --max-time 5 -X POST "https://api.telegram.org/bot${tok}/sendMessage" \
            -d "chat_id=${one_cid}" \
            -d "parse_mode=HTML" \
            --data-urlencode "text=${text}" >/dev/null 2>&1 &
    done
}

handle_clients() {
    printf '{"clients":['
    local first=1 now_epoch
    now_epoch=$(date +%s 2>/dev/null || echo 0)

    # Đảm bảo thư mục lưu trữ tồn tại
    mkdir -p /etc/vcrt /tmp/vcrt_sessions 2>/dev/null

    # A. Tự động kiểm tra và giải phóng các máy đã hết hạn chặn
    if [ -f "$BLOCKS_TIMED_FILE" ]; then
        local active_blocks=""
        while IFS='|' read -r b_mac b_type b_start b_expire b_dur b_name b_ip; do
            [ -z "$b_mac" ] && continue
            local b_mac_low=$(echo "$b_mac" | tr '[:upper:]' '[:lower:]')
            if [ "$b_expire" -gt 0 ] && [ "$now_epoch" -ge "$b_expire" ] 2>/dev/null; then
                # Đã hết hạn -> Gỡ bỏ luật chặn
                nft delete element inet fw4 scanwifi_block_wan "{ $b_mac_low }" 2>/dev/null || true
                nft delete element inet fw4 scanwifi_block_full "{ $b_mac_low }" 2>/dev/null || true
                iptables -D FORWARD -m mac --mac-source "$b_mac" -j DROP 2>/dev/null || true
                iptables -D INPUT -m mac --mac-source "$b_mac" -j DROP 2>/dev/null || true

                [ -f /var/run/hostapd-phy0-ap0.maclist ] && sed -i "/$b_mac_low/d" /var/run/hostapd-phy0-ap0.maclist 2>/dev/null && ubus call hostapd.phy0-ap0 reload 2>/dev/null || true
                [ -f /var/run/hostapd-phy1-ap0.maclist ] && sed -i "/$b_mac_low/d" /var/run/hostapd-phy1-ap0.maclist 2>/dev/null && ubus call hostapd.phy1-ap0 reload 2>/dev/null || true
                uci -q del_list wireless.default_radio0.maclist="$b_mac_low" 2>/dev/null || true
                uci -q del_list wireless.default_radio1.maclist="$b_mac_low" 2>/dev/null || true
                uci commit wireless 2>/dev/null || true

                grep -v -i "$b_mac" "$BLOCKED_SOFT_FILE" > "${BLOCKED_SOFT_FILE}.tmp" 2>/dev/null || true
                mv -f "${BLOCKED_SOFT_FILE}.tmp" "$BLOCKED_SOFT_FILE" 2>/dev/null || true
                grep -v -i "$b_mac" "$BLOCKED_HARD_FILE" > "${BLOCKED_HARD_FILE}.tmp" 2>/dev/null || true
                mv -f "${BLOCKED_HARD_FILE}.tmp" "$BLOCKED_HARD_FILE" 2>/dev/null || true
            else
                active_blocks="${active_blocks}${b_mac}|${b_type}|${b_start}|${b_expire}|${b_dur}|${b_name}|${b_ip}\n"
            fi
        done < "$BLOCKS_TIMED_FILE"
        printf "%b" "$active_blocks" > "$BLOCKS_TIMED_FILE"
    fi

    # B. Quét toàn bộ sóng Wi-Fi thực tế phần cứng
    local wifi_dump_file="/tmp/vcrt_cgi_wifi.tmp"
    rm -f "$wifi_dump_file" 2>/dev/null || true
    local devs
    devs=$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}')
    [ -z "$devs" ] && devs="wlan0 wlan1 phy0-ap0 phy1-ap0 ra0 rai0"
    for ifc in $devs; do
        case "$ifc" in *sta*|*mon*) continue ;; esac
        local ch b
        ch=$(iw dev "$ifc" info 2>/dev/null | awk '/channel/{print $2}')
        case "$ch" in ''|*[!0-9]*) ch=6 ;; esac
        b="2.4GHz"
        [ "$ch" -gt 14 ] 2>/dev/null && b="5GHz"

        iw dev "$ifc" station dump 2>/dev/null | awk -v iface="$ifc" -v band="$b" '
        /^Station/ {
            if (mac != "") {
                print mac "|" iface "|" sig "|" band "|" con;
            }
            mac = tolower($2); sig = "-55 dBm"; con = 0;
        }
        $1 == "signal:" { sig = $2 " " $3; }
        /connected time:/ { con = int($3); }
        END {
            if (mac != "") {
                print mac "|" iface "|" sig "|" band "|" con;
            }
        }' >> "$wifi_dump_file" 2>/dev/null
    done

    # C. Quét trước môi trường để tránh fork subshell trong vòng lặp (Tối ưu CPU MT7620)
    local arp_data lan_ports_up=0 ip_neigh_data
    arp_data=$(cat /proc/net/arp 2>/dev/null)
    ip_neigh_data=$(ip neigh show dev br-lan 2>/dev/null)
    if command -v swconfig >/dev/null 2>&1; then
        local p0 p1
        p0=$(swconfig dev switch0 port "${PORT_LAN1:-0}" get link 2>/dev/null)
        p1=$(swconfig dev switch0 port "${PORT_LAN2:-1}" get link 2>/dev/null)
        case "$p0 $p1" in *link:up*) lan_ports_up=1 ;; esac
    else
        [ -f /sys/class/net/eth0/carrier ] && [ "$(cat /sys/class/net/eth0/carrier 2>/dev/null)" = "1" ] && lan_ports_up=1
    fi

    # Đọc trước các bảng nftables & uci 1 lần duy nhất
    local nft_full_data nft_wan_data uci_deny_macs
    nft_full_data=$(nft list set inet fw4 scanwifi_block_full 2>/dev/null)
    nft_wan_data=$(nft list set inet fw4 scanwifi_block_wan 2>/dev/null)
    uci_deny_macs="$(uci -q get wireless.default_radio0.maclist 2>/dev/null) $(uci -q get wireless.default_radio1.maclist 2>/dev/null)"

    local seen_macs=" "

    # D. Đọc DHCP Leases
    if [ -f /tmp/dhcp.leases ] && [ -s /tmp/dhcp.leases ]; then
        while read -r ltime mac ip name clid; do
            [ -z "$mac" ] && continue
            local mac_low=$(echo "$mac" | tr '[:upper:]' '[:lower:]')
            seen_macs="${seen_macs}${mac_low} "

            # Tên tùy chỉnh
            if [ -f "$DEVICE_NAMES_FILE" ]; then
                local custom_name=$(grep -i "^${mac_low}=" "$DEVICE_NAMES_FILE" 2>/dev/null | head -n1 | cut -d= -f2)
                [ -n "$custom_name" ] && name="$custom_name"
            fi
            [ "$name" = "*" ] || [ -z "$name" ] && name="Thiết bị không tên"

            # Xác định icon bằng case (siêu nhanh, không fork process)
            local icon="📱"
            case "$name" in
                *[lL][aA][pP]*|*[pP][cC]*|*[mM][aA][cC]*|*[wW][iI][nN]*|*[dD][eE][sS][kK][tT][oO][pP]*) icon="💻" ;;
                *[tT][vV]*|*[tT][iI][vV][iI]*|*[sS][oO][nN][yY]*|*[lL][gG]*|*[sS][aA][mM][sS][uU][nN][gG]*|*[tT][cC][lL]*) icon="📺" ;;
                *[cC][aA][mM]*|*[iI][pP][cC][aA][mM]*|*[iI][mM][oO][uU]*|*[eE][zZ][vV][iI][zZ]*) icon="📷" ;;
                *[pP][aA][dD]*|*[tT][aA][bB]*) icon="📟" ;;
                *[pP][rR][iI][nN][tT]*|*[eE][pP][sS][oO][nN]*|*[cC][aA][nN][oO][nN]*|*[hH][pP]*) icon="🖨" ;;
            esac

            local blocked="false" softBlocked="false" block_expire=0 block_remain=0 block_dur=0
            if [ -f "$BLOCKS_TIMED_FILE" ]; then
                local b_info=$(grep -i "^${mac_low}|" "$BLOCKS_TIMED_FILE" 2>/dev/null | head -n1)
                if [ -n "$b_info" ]; then
                    local b_type=$(echo "$b_info" | cut -d'|' -f2)
                    block_expire=$(echo "$b_info" | cut -d'|' -f4)
                    block_dur=$(echo "$b_info" | cut -d'|' -f5)
                    case "$block_dur" in ''|*[!0-9]*) block_dur=0 ;; esac
                    case "$block_expire" in ''|*[!0-9]*) block_expire=0 ;; esac
                    if [ "$block_expire" -gt "$now_epoch" ] 2>/dev/null; then
                        block_remain=$((block_expire - now_epoch))
                    fi
                    if [ "$b_type" = "hard" ]; then
                        blocked="true"
                    else
                        softBlocked="true"
                    fi
                fi
            fi

            # Kiểm tra nhanh trong biến đã nạp sẵn
            if [ "$blocked" = "false" ] && [ "$softBlocked" = "false" ]; then
                case "$nft_full_data" in *"$mac_low"*) blocked="true" ;; esac
                case "$uci_deny_macs" in *"$mac_low"*) blocked="true" ;; esac
                if [ "$blocked" = "false" ]; then
                    case "$nft_wan_data" in *"$mac_low"*) softBlocked="true" ;; esac
                fi
            fi

            local is_wifi=0 is_lan=0 band="" rssi=-100 con_sec=0 con_str=""
            local st_info=$(grep -i "^${mac_low}|" "$wifi_dump_file" 2>/dev/null | head -n1)
            if [ -n "$st_info" ]; then
                is_wifi=1
                band=$(echo "$st_info" | cut -d'|' -f4)
                rssi=$(echo "$st_info" | cut -d'|' -f3 | awk '{print $1}')
                con_sec=$(echo "$st_info" | cut -d'|' -f5)
            elif [ "$lan_ports_up" -eq 1 ] && [ -n "$ip" ]; then
                local arp_entry=$(echo "$arp_data" | grep -i "$mac_low" | head -n1)
                local arp_flag=$(echo "$arp_entry" | awk '{print $3}')
                if [ "$arp_flag" = "0x2" ]; then
                    case "$ip_neigh_data" in
                        *"$mac_low"*REACHABLE*|*"$mac_low"*DELAY*|*"$mac_low"*STALE*)
                            is_lan=1
                            band="Dây LAN"
                            rssi=-50
                            con_str="Đang cắm cáp LAN"
                            case "$name" in *[lL][aA][pP]*|*[pP][cC]*|*[dD][eE][sS][kK][tT][oO][pP]*) icon="💻" ;; esac
                            ;;
                    esac
                fi
            fi

            local is_online=0
            [ "$is_wifi" -eq 1 ] || [ "$is_lan" -eq 1 ] && is_online=1

            # NẾU KHÔNG ONLINE VÀ KHÔNG BỊ CHẶN -> BỎ QUA
            # NHƯNG NẾU BỊ CHẶN HOẶC CẮT NET -> BẮT BUỘC HIỆN ĐỂ USER THẤY TRONG TAB CHẶN!
            if [ "$is_online" -eq 0 ] && [ "$blocked" = "false" ] && [ "$softBlocked" = "false" ]; then
                continue
            fi

            [ -z "$rssi" ] && rssi=-55
            [ -z "$band" ] && band="Wi-Fi"

            if [ "$is_wifi" -eq 1 ]; then
                if [ -n "$con_sec" ] && [ "$con_sec" -gt 0 ] 2>/dev/null; then
                    local c_d=$((con_sec / 86400))
                    local c_h=$(( (con_sec % 86400) / 3600 ))
                    local c_m=$(( (con_sec % 3600) / 60 ))
                    if [ "$c_d" -gt 0 ]; then con_str="${c_d} ngày ${c_h} giờ"
                    elif [ "$c_h" -gt 0 ]; then con_str="${c_h} giờ ${c_m} phút"
                    elif [ "$c_m" -gt 0 ]; then con_str="${c_m} phút"
                    else con_str="${con_sec} giây"
                    fi
                else
                    con_str="Vừa kết nối"
                fi
            elif [ "$blocked" = "true" ]; then
                con_str="Đã bị đá khỏi Wi-Fi"
            elif [ "$softBlocked" = "true" ]; then
                con_str="Đã cắt Internet"
            fi

            [ "$first" -eq 0 ] && printf ","
            first=0

            cat << EOF
{
  "id": "$(json_escape "$mac_low")",
  "name": "$(json_escape "$name")",
  "ip": "$(json_escape "$ip")",
  "mac": "$(json_escape "$mac")",
  "band": "$(json_escape "$band")",
  "rssi": ${rssi},
  "connectedTime": "$(json_escape "$con_str")",
  "online": $([ "$is_online" -eq 1 ] && echo "true" || echo "false"),
  "blocked": ${blocked},
  "softBlocked": ${softBlocked},
  "blockRemain": ${block_remain},
  "blockDuration": ${block_dur},
  "icon": "$(json_escape "$icon")"
}
EOF
        done < /tmp/dhcp.leases
    fi

    # E. Quét các thiết bị bị chặn trong BLOCKS_TIMED_FILE mà KHÔNG nằm trong dhcp.leases
    if [ -f "$BLOCKS_TIMED_FILE" ]; then
        while IFS='|' read -r b_mac b_type b_start b_expire b_dur b_name b_ip; do
            [ -z "$b_mac" ] && continue
            local b_mac_low=$(echo "$b_mac" | tr '[:upper:]' '[:lower:]')
            case "$seen_macs" in *" ${b_mac_low} "*) continue ;; esac
            seen_macs="${seen_macs}${b_mac_low} "

            local b_rem=0
            case "$b_dur" in ''|*[!0-9]*) b_dur=0 ;; esac
            case "$b_expire" in ''|*[!0-9]*) b_expire=0 ;; esac
            if [ "$b_expire" -gt "$now_epoch" ] 2>/dev/null; then
                b_rem=$((b_expire - now_epoch))
            fi

            [ -z "$b_name" ] && b_name="Thiết bị bị chặn"
            [ -z "$b_ip" ] && b_ip="N/A"

            local b_hard="false" b_soft="false"
            if [ "$b_type" = "hard" ]; then b_hard="true"; else b_soft="true"; fi

            [ "$first" -eq 0 ] && printf ","
            first=0

            cat << EOF
{
  "id": "$(json_escape "$b_mac_low")",
  "name": "$(json_escape "$b_name")",
  "ip": "$(json_escape "$b_ip")",
  "mac": "$(json_escape "$b_mac")",
  "band": "Wi-Fi (Đã đá)",
  "rssi": -100,
  "connectedTime": "Đã ngắt kết nối",
  "online": false,
  "blocked": ${b_hard},
  "softBlocked": ${b_soft},
  "blockRemain": ${b_rem},
  "blockDuration": ${b_dur},
  "icon": "📱"
}
EOF
        done < "$BLOCKS_TIMED_FILE"
    fi

    # F. Quét các MAC trong UCI maclist mà chưa được liệt kê
    for uci_mac in $uci_deny_macs; do
        [ -z "$uci_mac" ] && continue
        local u_low=$(echo "$uci_mac" | tr '[:upper:]' '[:lower:]')
        case "$seen_macs" in *" ${u_low} "*) continue ;; esac
        seen_macs="${seen_macs}${u_low} "

        [ "$first" -eq 0 ] && printf ","
        first=0

        cat << EOF
{
  "id": "$(json_escape "$u_low")",
  "name": "Thiết bị bị cấm Wi-Fi",
  "ip": "N/A",
  "mac": "$(json_escape "$uci_mac")",
  "band": "Wi-Fi (Đã cấm)",
  "rssi": -100,
  "connectedTime": "Đã cấm sóng",
  "online": false,
  "blocked": true,
  "softBlocked": false,
  "blockRemain": 0,
  "blockDuration": 0,
  "icon": "📱"
}
EOF
    done

    printf ']}
'
}

handle_soft_block() {
    local mac="$1" dur="${2:-30}" name="$3" ip="$4"
    [ -z "$mac" ] && { json_error "missing_mac"; return 1; }
    local mac_low=$(echo "$mac" | tr '[:upper:]' '[:lower:]')

    # NFTABLES (fw4) & iptables fallback
    nft add element inet fw4 scanwifi_block_wan "{ $mac_low }" 2>/dev/null || true
    iptables -D FORWARD -m mac --mac-source "$mac" -j DROP 2>/dev/null || true
    iptables -I FORWARD -m mac --mac-source "$mac" -j DROP 2>/dev/null || true
    [ -n "$ip" ] && ip neigh del "$ip" dev br-lan 2>/dev/null || true

    local now_epoch expire
    now_epoch=$(date +%s 2>/dev/null || echo 0)
    case "$dur" in ''|*[!0-9]*) dur=30 ;; esac
    if [ "$dur" -gt 0 ] 2>/dev/null; then
        expire=$((now_epoch + dur * 60))
    else
        expire=0
    fi

    mkdir -p /etc/vcrt 2>/dev/null
    [ -f "$BLOCKS_TIMED_FILE" ] && grep -v -i "^${mac_low}|" "$BLOCKS_TIMED_FILE" > "${BLOCKS_TIMED_FILE}.tmp" 2>/dev/null || true
    mv -f "${BLOCKS_TIMED_FILE}.tmp" "$BLOCKS_TIMED_FILE" 2>/dev/null || true
    echo "${mac_low}|soft|${now_epoch}|${expire}|${dur}|${name}|${ip}" >> "$BLOCKS_TIMED_FILE"

    echo "$mac_low" >> "$BLOCKED_SOFT_FILE"
    grep -v -i "$mac_low" "$BLOCKED_HARD_FILE" > "${BLOCKED_HARD_FILE}.tmp" 2>/dev/null || true
    mv -f "${BLOCKED_HARD_FILE}.tmp" "$BLOCKED_HARD_FILE" 2>/dev/null || true

    send_telegram_event "⛔ <b>THIẾT BỊ BỊ CHẶN INTERNET!</b>\n━━━━━━━━━━━━━━━━━\n📱 <b>Tên máy:</b> <code>${name:-Thiết bị}</code>\n📍 <b>IP:</b> <code>${ip}</code>\n🔑 <b>MAC:</b> <code>${mac}</code>\n⏱ <b>Thời hạn:</b> <code>${dur} phút</code>\n<i>Thao tác từ Web Dashboard VCRT</i>"
    printf '{"status":"ok","action":"soft_block","mac":"%s","duration":%d,"expire":%d}\n' "$mac" "$dur" "$expire"
}

handle_hard_block() {
    local mac="$1" dur="${2:-30}" name="$3" ip="$4"
    [ -z "$mac" ] && { json_error "missing_mac"; return 1; }
    local mac_low=$(echo "$mac" | tr '[:upper:]' '[:lower:]')

    # 1. NFTABLES (fw4): Chặn forward và input
    nft add element inet fw4 scanwifi_block_full "{ $mac_low }" 2>/dev/null || true
    nft add element inet fw4 scanwifi_block_wan "{ $mac_low }" 2>/dev/null || true

    # 2. Legacy iptables
    iptables -D FORWARD -m mac --mac-source "$mac" -j DROP 2>/dev/null || true
    iptables -D INPUT -m mac --mac-source "$mac" -j DROP 2>/dev/null || true
    iptables -I FORWARD -m mac --mac-source "$mac" -j DROP 2>/dev/null || true
    iptables -I INPUT -m mac --mac-source "$mac" -j DROP 2>/dev/null || true

    # 3. Chặn kết nối lại Wi-Fi: Đưa vào macfilter deny và nạp runtime
    uci set wireless.default_radio0.macfilter='deny' 2>/dev/null || true
    uci -q del_list wireless.default_radio0.maclist="$mac_low" 2>/dev/null || true
    uci add_list wireless.default_radio0.maclist="$mac_low" 2>/dev/null || true

    uci set wireless.default_radio1.macfilter='deny' 2>/dev/null || true
    uci -q del_list wireless.default_radio1.maclist="$mac_low" 2>/dev/null || true
    uci add_list wireless.default_radio1.maclist="$mac_low" 2>/dev/null || true
    uci commit wireless 2>/dev/null || true

    echo "$mac_low" >> /var/run/hostapd-phy0-ap0.maclist 2>/dev/null || true
    echo "$mac_low" >> /var/run/hostapd-phy1-ap0.maclist 2>/dev/null || true
    ubus call hostapd.phy0-ap0 reload 2>/dev/null || true
    ubus call hostapd.phy1-ap0 reload 2>/dev/null || true

    # 4. Đá văng thiết bị khỏi Wi-Fi
    ubus call hostapd.phy0-ap0 del_client "{\"addr\":\"$mac_low\",\"deauth\":true,\"reason\":1}" 2>/dev/null || true
    ubus call hostapd.phy1-ap0 del_client "{\"addr\":\"$mac_low\",\"deauth\":true,\"reason\":1}" 2>/dev/null || true
    for wif in $(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}'); do
        case "$wif" in *sta*) continue ;; esac
        iw dev "$wif" station del "$mac_low" 2>/dev/null || true
    done

    # 5. Xóa ARP
    [ -n "$ip" ] && ip neigh del "$ip" dev br-lan 2>/dev/null || true

    local now_epoch expire
    now_epoch=$(date +%s 2>/dev/null || echo 0)
    case "$dur" in ''|*[!0-9]*) dur=30 ;; esac
    if [ "$dur" -gt 0 ] 2>/dev/null; then
        expire=$((now_epoch + dur * 60))
    else
        expire=0
    fi

    mkdir -p /etc/vcrt 2>/dev/null
    [ -f "$BLOCKS_TIMED_FILE" ] && grep -v -i "^${mac_low}|" "$BLOCKS_TIMED_FILE" > "${BLOCKS_TIMED_FILE}.tmp" 2>/dev/null || true
    mv -f "${BLOCKS_TIMED_FILE}.tmp" "$BLOCKS_TIMED_FILE" 2>/dev/null || true
    echo "${mac_low}|hard|${now_epoch}|${expire}|${dur}|${name}|${ip}" >> "$BLOCKS_TIMED_FILE"

    echo "$mac_low" >> "$BLOCKED_HARD_FILE"
    grep -v -i "$mac_low" "$BLOCKED_SOFT_FILE" > "${BLOCKED_SOFT_FILE}.tmp" 2>/dev/null || true
    mv -f "${BLOCKED_SOFT_FILE}.tmp" "$BLOCKED_SOFT_FILE" 2>/dev/null || true

    send_telegram_event "🛑 <b>THIẾT BỊ BỊ ĐÁ KHỎI WI-FI & CHẶN!</b>\n━━━━━━━━━━━━━━━━━\n📱 <b>Tên máy:</b> <code>${name:-Thiết bị}</code>\n📍 <b>IP:</b> <code>${ip}</code>\n🔑 <b>MAC:</b> <code>${mac}</code>\n⏱ <b>Thời hạn:</b> <code>${dur} phút</code>\n<i>Thao tác từ Web Dashboard VCRT</i>"
    printf '{"status":"ok","action":"hard_block","mac":"%s","duration":%d,"expire":%d}\n' "$mac" "$dur" "$expire"
}

handle_unblock() {
    local mac="$1"
    [ -z "$mac" ] && { json_error "missing_mac"; return 1; }
    local mac_low=$(echo "$mac" | tr '[:upper:]' '[:lower:]')

    # 1. NFTABLES (fw4)
    nft delete element inet fw4 scanwifi_block_wan "{ $mac_low }" 2>/dev/null || true
    nft delete element inet fw4 scanwifi_block_full "{ $mac_low }" 2>/dev/null || true

    # 2. Legacy iptables
    iptables -D FORWARD -m mac --mac-source "$mac" -j DROP 2>/dev/null || true
    iptables -D INPUT -m mac --mac-source "$mac" -j DROP 2>/dev/null || true

    # 3. Gỡ bỏ khỏi danh sách cấm Wi-Fi
    if [ -f /var/run/hostapd-phy0-ap0.maclist ]; then
        sed -i "/$mac_low/d" /var/run/hostapd-phy0-ap0.maclist 2>/dev/null || true
        ubus call hostapd.phy0-ap0 reload 2>/dev/null || true
    fi
    if [ -f /var/run/hostapd-phy1-ap0.maclist ]; then
        sed -i "/$mac_low/d" /var/run/hostapd-phy1-ap0.maclist 2>/dev/null || true
        ubus call hostapd.phy1-ap0 reload 2>/dev/null || true
    fi
    uci -q del_list wireless.default_radio0.maclist="$mac_low" 2>/dev/null || true
    uci -q del_list wireless.default_radio1.maclist="$mac_low" 2>/dev/null || true
    uci commit wireless 2>/dev/null || true

    [ -f "$BLOCKS_TIMED_FILE" ] && grep -v -i "^${mac_low}|" "$BLOCKS_TIMED_FILE" > "${BLOCKS_TIMED_FILE}.tmp" 2>/dev/null || true
    mv -f "${BLOCKS_TIMED_FILE}.tmp" "$BLOCKS_TIMED_FILE" 2>/dev/null || true

    grep -v -i "$mac_low" "$BLOCKED_SOFT_FILE" > "${BLOCKED_SOFT_FILE}.tmp" 2>/dev/null || true
    mv -f "${BLOCKED_SOFT_FILE}.tmp" "$BLOCKED_SOFT_FILE" 2>/dev/null || true
    grep -v -i "$mac_low" "$BLOCKED_HARD_FILE" > "${BLOCKED_HARD_FILE}.tmp" 2>/dev/null || true
    mv -f "${BLOCKED_HARD_FILE}.tmp" "$BLOCKED_HARD_FILE" 2>/dev/null || true

    send_telegram_event "🔓 <b>THIẾT BỊ ĐÃ ĐƯỢC MỞ MẠNG!</b>\n━━━━━━━━━━━━━━━━━\n🔑 <b>MAC:</b> <code>${mac}</code>\n<i>Thao tác từ Web Dashboard VCRT</i>"
    printf '{"status":"ok","action":"unblock","mac":"%s"}\n' "$mac"
}
