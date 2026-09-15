#!/bin/sh
# ==============================================================================
# VCRT OS v2.0 - Telegram Bot Helper Utilities
# BusyBox POSIX Shell Standard - Ultra-lightweight & Optimized
# ==============================================================================

# ─── BẢO VỆ DỮ LIỆU VỚI TELEGRAM SPOILER (<tg-spoiler>) ───────────────────────
spoiler_wrap() {
    local text="${1:-N/A}"
    printf '<tg-spoiler>%s</tg-spoiler>\n' "$text"
}

mask_ip() {
    local ip="${1:-N/A}"
    printf '<tg-spoiler>%s</tg-spoiler>\n' "$ip"
}

mask_wan_ip() {
    local ip="${1:-N/A}"
    printf '<tg-spoiler>%s</tg-spoiler>\n' "$ip"
}

mask_mac() {
    local mac="${1:-N/A}"
    local mac_u
    mac_u=$(printf '%s' "$mac" | tr 'a-z' 'A-Z')
    printf '<tg-spoiler>%s</tg-spoiler>\n' "$mac_u"
}

# ─── ĐỊNH DẠNG DUNG LƯỢNG (BYTES -> KB / MB / GB) ─────────────────────────────
format_bytes() {
    local b="${1:-0}"
    awk -v b="$b" '
    BEGIN {
        if (b >= 1073741824) printf "%.2f GB", b / 1073741824;
        else if (b >= 1048576) printf "%.1f MB", b / 1048576;
        else printf "%.1f KB", b / 1024;
    }'
}

# ─── ĐỊNH DẠNG THỜI GIAN (GIÂY -> NGÀY / GIỜ / PHÚT) ─────────────────────────
format_duration() {
    local sec="${1:-0}"
    case "$sec" in ''|*[!0-9]*) sec=0 ;; esac
    local d=$(( sec / 86400 ))
    local h=$(( (sec % 86400) / 3600 ))
    local m=$(( (sec % 3600) / 60 ))
    local s=$(( sec % 60 ))
    local out=""

    if [ "$d" -gt 0 ]; then
        out="${d} ngày "
    fi
    if [ "$h" -gt 0 ] || [ -n "$out" ]; then
        out="${out}${h} giờ "
    fi
    out="${out}${m} phút"
    if [ "$d" -eq 0 ] && [ "$h" -eq 0 ]; then
        out="${out} ${s} giây"
    fi
    printf '%s' "$out"
}

# ─── THANH TRỰC QUAN CPU (CPU VISUAL BAR 10 BLOCKS) ───────────────────────────
cpu_bar() {
    local pct="${1:-0}"
    case "$pct" in ''|*[!0-9]*) pct=0 ;; esac
    [ "$pct" -gt 100 ] && pct=100
    local filled=$(( pct / 10 ))
    local bar=""
    local i=0
    while [ "$i" -lt 10 ]; do
        if [ "$i" -lt "$filled" ]; then
            bar="${bar}■"
        else
            bar="${bar}□"
        fi
        i=$(( i + 1 ))
    done
    printf '[%s]' "$bar"
}

# ─── TRA CỨU TÊN THIẾT BỊ THEO MAC ───────────────────────────────────────────
get_device_name() {
    local mac="${1:-}"
    [ -z "$mac" ] && { printf "Thiết bị không tên"; return 0; }
    local mac_l
    mac_l=$(printf '%s' "$mac" | tr 'A-Z' 'a-z')

    # 1. Tra cứu file đặt tên thủ công /etc/vcrt/device_names
    if [ -f "${DEVICE_NAMES_FILE:-/etc/vcrt/device_names}" ]; then
        local custom_name
        custom_name=$(awk -F'[| \t]' -v m="$mac_l" 'tolower($1)==m {print $2; exit}' "${DEVICE_NAMES_FILE:-/etc/vcrt/device_names}" 2>/dev/null)
        if [ -n "$custom_name" ]; then
            printf '%s' "$custom_name"
            return 0
        fi
    fi

    # 2. Tra cứu DHCP Leases
    if [ -f /tmp/dhcp.leases ]; then
        local dhcp_name
        dhcp_name=$(awk -v m="$mac_l" 'tolower($2)==m {print $4; exit}' /tmp/dhcp.leases 2>/dev/null)
        if [ -n "$dhcp_name" ] && [ "$dhcp_name" != "*" ]; then
            printf '%s' "$dhcp_name"
            return 0
        fi
    fi

    # 3. Tra cứu ARP Table + /etc/hosts
    if [ -f /proc/net/arp ]; then
        local ip_match
        ip_match=$(awk -v m="$mac_l" 'tolower($4)==m {print $1; exit}' /proc/net/arp 2>/dev/null)
        if [ -n "$ip_match" ] && [ -f /etc/hosts ]; then
            local host_name
            host_name=$(awk -v ip="$ip_match" '$1==ip {print $2; exit}' /etc/hosts 2>/dev/null)
            if [ -n "$host_name" ] && [ "$host_name" != "localhost" ]; then
                printf '%s' "$host_name"
                return 0
            fi
        fi
    fi

    printf "Thiết bị không tên"
}

# ─── LẤY IP ZEROTIER VPN ĐANG HOẠT ĐỘNG ───────────────────────────────────────
get_zerotier_ip() {
    local zt_ip=""
    # 1. Lấy từ zerotier-cli listnetworks
    if command -v zerotier-cli >/dev/null 2>&1; then
        zt_ip=$(zerotier-cli listnetworks 2>/dev/null | awk 'NR>1 && $9!="" {print $9; exit}' | cut -d/ -f1)
    fi

    # 2. Lấy từ interface mạng bắt đầu bằng zt
    if [ -z "$zt_ip" ]; then
        local zt_dev
        zt_dev=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^zt' | head -n1)
        if [ -n "$zt_dev" ]; then
            zt_ip=$(ip -4 addr show dev "$zt_dev" 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)
        fi
    fi
    printf '%s' "$zt_ip"
}

# ─── QUÉT TOÀN BỘ SÓNG WI-FI PHẦN CỨNG THỜI GIAN THỰC ─────────────────────────
get_wifi_stations() {
    local devs
    devs=$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}')
    [ -z "$devs" ] && devs="wlan0 wlan1 phy0-ap0 phy1-ap0 ra0 rai0"

    for ifc in $devs; do
        case "$ifc" in *sta*|*mon*) continue ;; esac
        local ch
        ch=$(iw dev "$ifc" info 2>/dev/null | awk '/channel/{print $2}')
        [ -z "$ch" ] && command -v iwinfo >/dev/null 2>&1 && ch=$(iwinfo "$ifc" info 2>/dev/null | awk '/Channel:/{print $4}')
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

# ─── TELEGRAM MESSAGE DISPATCHER ──────────────────────────────────────────────
send_message() {
    local target_chat="$1"
    local text="$2"
    local parse_mode="${3:-HTML}"
    [ -z "$BOT_TOKEN" ] || [ -z "$target_chat" ] && return 1

    local clean_target
    clean_target=$(printf '%s' "$target_chat" | tr -d ' \r\n')
    local api_url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
    local keyboard="${KEYBOARD:-}"

    local res
    if [ -n "$keyboard" ]; then
        res=$(curl -4 --tlsv1.2 --tls-max 1.2 -s --max-time 10 -X POST "$api_url" \
            --data-urlencode "chat_id=${clean_target}" \
            --data-urlencode "parse_mode=${parse_mode}" \
            --data-urlencode "reply_markup=${keyboard}" \
            --data-urlencode "text=${text}" 2>&1)
    else
        res=$(curl -4 --tlsv1.2 --tls-max 1.2 -s --max-time 10 -X POST "$api_url" \
            --data-urlencode "chat_id=${clean_target}" \
            --data-urlencode "parse_mode=${parse_mode}" \
            --data-urlencode "text=${text}" 2>&1)
    fi

    printf '[%s] Sent to %s: %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$clean_target" "$res" >> /tmp/vcrt_bot.log 2>/dev/null || true

    # Fallback retry dạng plain text nếu bị lỗi parse HTML entities
    if printf '%s' "$res" | grep -q "can't parse entities"; then
        local plain_text
        plain_text=$(printf '%s' "$text" | sed 's/<[^>]*>//g')
        if [ -n "$keyboard" ]; then
            curl -4 --tlsv1.2 --tls-max 1.2 -s --max-time 10 -X POST "$api_url" \
                --data-urlencode "chat_id=${clean_target}" \
                --data-urlencode "reply_markup=${keyboard}" \
                --data-urlencode "text=${plain_text}" >/dev/null 2>&1 || true
        else
            curl -4 --tlsv1.2 --tls-max 1.2 -s --max-time 10 -X POST "$api_url" \
                --data-urlencode "chat_id=${clean_target}" \
                --data-urlencode "text=${plain_text}" >/dev/null 2>&1 || true
        fi
    fi
}

send_msg() {
    # Alias tương thích ngược: send_msg "text" [target_chat]
    local text="$1"
    local target_chat="$2"
    if [ -n "$target_chat" ]; then
        send_message "$target_chat" "$text" "HTML"
    else
        send_message_all "$text"
    fi
}

send_message_all() {
    local text="$1"
    local parse_mode="${2:-HTML}"
    [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ] && return 1

    for cid in $(printf '%s' "$CHAT_ID" | tr ',;' ' '); do
        local clean_cid
        clean_cid=$(printf '%s' "$cid" | tr -d ' \r\n')
        [ -z "$clean_cid" ] && continue
        send_message "$clean_cid" "$text" "$parse_mode"
    done
}

send_document() {
    local target_chat="$1"
    local file_path="$2"
    local caption="${3:-}"
    [ -z "$BOT_TOKEN" ] || [ -z "$target_chat" ] || [ ! -f "$file_path" ] && return 1

    local clean_target
    clean_target=$(printf '%s' "$target_chat" | tr -d ' \r\n')
    local api_url="https://api.telegram.org/bot${BOT_TOKEN}/sendDocument"

    curl -4 --tlsv1.2 --tls-max 1.2 -s --max-time 60 -X POST "$api_url" \
        -F "chat_id=${clean_target}" \
        -F "document=@${file_path}" \
        -F "caption=${caption}" >/dev/null 2>&1 || true
}
