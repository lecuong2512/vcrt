#!/bin/sh
# VCRT OS v2.0 - Wi-Fi Management Module
# Endpoints: wifi_get, wifi_apply, wifi_scan, wifi_connect_uplink, wifi_rollback, wifi_confirm

# Fallback biến platform nếu chưa khai báo
: "${RADIO_5G:=radio0}"
: "${RADIO_24G:=radio1}"
: "${IFACE_5G:=phy0-ap0}"
: "${IFACE_24G:=phy1-ap0}"

_detect_radios() {
    local r
    for r in radio0 radio1 radio2; do
        local b
        b=$(uci -q get "wireless.${r}.band")
        if [ "$b" = "5g" ] || [ "$b" = "5GHz" ]; then
            RADIO_5G="$r"
        elif [ "$b" = "2g" ] || [ "$b" = "2.4GHz" ]; then
            RADIO_24G="$r"
        fi
    done
}

handle_wifi_get() {
    _detect_radios

    local sec5="" sec24="" iface dev
    for iface in $(uci show wireless 2>/dev/null | grep "\.mode='ap'" | cut -d. -f1,2); do
        dev=$(uci -q get "${iface}.device")
        [ "$dev" = "$RADIO_5G" ] && [ -z "$sec5" ] && sec5="$iface"
        [ "$dev" = "$RADIO_24G" ] && [ -z "$sec24" ] && sec24="$iface"
    done
    [ -z "$sec5" ] && sec5="wireless.default_${RADIO_5G}"
    [ -z "$sec24" ] && sec24="wireless.default_${RADIO_24G}"

    # Doc cau hinh tu UCI
    local uci_ssid5 uci_pass5 conf_ch5 uci_power5
    uci_ssid5=$(uci -q get "${sec5}.ssid")
    uci_pass5=$(uci -q get "${sec5}.key")
    conf_ch5=$(uci -q get "wireless.${RADIO_5G}.channel")
    [ -z "$conf_ch5" ] && conf_ch5="auto"
    uci_power5=$(uci -q get "wireless.${RADIO_5G}.txpower")

    local uci_ssid24 uci_pass24 conf_ch24 uci_power24
    uci_ssid24=$(uci -q get "${sec24}.ssid")
    uci_pass24=$(uci -q get "${sec24}.key")
    conf_ch24=$(uci -q get "wireless.${RADIO_24G}.channel")
    [ -z "$conf_ch24" ] && conf_ch24="auto"
    uci_power24=$(uci -q get "wireless.${RADIO_24G}.txpower")

    # Do tim thuc te tat ca interface qua iwinfo va iw dev
    local real_ssid5="" real_ch5="" real_power5="" ifc5=""
    local real_ssid24="" real_ch24="" real_power24="" ifc24=""

    local ifc_list=""
    if command -v iw >/dev/null 2>&1; then
        ifc_list=$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}')
    fi
    if [ -z "$ifc_list" ]; then
        ifc_list=$(ls /sys/class/net 2>/dev/null | grep -E '^wlan|^phy|^ra')
    fi

    local ifc
    for ifc in $ifc_list; do
        case "$ifc" in *sta*|*mon*) continue ;; esac

        local info="" mode=""
        if command -v iwinfo >/dev/null 2>&1; then
            info=$(iwinfo "$ifc" info 2>/dev/null)
            mode=$(echo "$info" | awk -F'Mode:' '{print $2}' | awk '{print $1}')
        fi
        if [ -z "$mode" ] && command -v iw >/dev/null 2>&1; then
            mode=$(iw dev "$ifc" info 2>/dev/null | awk '$1=="type"{print $2}')
        fi

        case "$mode" in
            Master|AP|ap) ;;
            *) continue ;;
        esac

        local ch="" pwr="" essid="" is_5g=0
        ch=$(echo "$info" | awk -F'Channel:' '{print $2}' | awk '{print $1}' | tr -dc '0-9')
        [ -z "$ch" ] && ch=$(iw dev "$ifc" info 2>/dev/null | awk '/channel/{print $2}' | tr -dc '0-9')

        pwr=$(echo "$info" | awk -F'Tx-Power:' '{print $2}' | awk '{print $1}' | tr -dc '0-9')
        [ -z "$pwr" ] && pwr=$(iw dev "$ifc" info 2>/dev/null | awk '/txpower/{print $2}' | cut -d. -f1 | tr -dc '0-9')

        essid=$(echo "$info" | grep -o 'ESSID: "[^"]*"' | cut -d'"' -f2)
        [ -z "$essid" ] && essid=$(iw dev "$ifc" info 2>/dev/null | awk '/ssid/{print $2}')

        if [ -n "$ch" ] && [ "$ch" -gt 14 ] 2>/dev/null; then
            is_5g=1
        elif echo "$info" | grep -qiE "5\.[0-9]|5GHz|5[0-9]{3} *MHz"; then
            is_5g=1
        elif iw dev "$ifc" info 2>/dev/null | grep -qiE "5[0-9]{3} *MHz"; then
            is_5g=1
        fi

        if [ "$is_5g" -eq 1 ]; then
            [ -z "$real_ch5" ] && real_ch5="$ch"
            [ -z "$real_power5" ] && real_power5="$pwr"
            [ -z "$real_ssid5" ] && real_ssid5="$essid"
            [ -z "$ifc5" ] && ifc5="$ifc"
        else
            [ -z "$real_ch24" ] && real_ch24="$ch"
            [ -z "$real_power24" ] && real_power24="$pwr"
            [ -z "$real_ssid24" ] && real_ssid24="$essid"
            [ -z "$ifc24" ] && ifc24="$ifc"
        fi
    done

    [ -n "$ifc5" ] && IFACE_5G="$ifc5"
    [ -n "$ifc24" ] && IFACE_24G="$ifc24"

    local ssid5 pass5 ch5 power5
    ssid5="${real_ssid5:-$uci_ssid5}"
    pass5="$uci_pass5"
    ch5="${real_ch5:-$conf_ch5}"
    power5="${real_power5:-$uci_power5}"
    [ -z "$power5" ] && power5="20"

    local ssid24 pass24 ch24 power24
    ssid24="${real_ssid24:-$uci_ssid24}"
    pass24="$uci_pass24"
    ch24="${real_ch24:-$conf_ch24}"
    power24="${real_power24:-$uci_power24}"
    [ -z "$power24" ] && power24="20"

    cat << EOF
{
  "wifi5": {
    "ssid": "$(json_escape "$ssid5")",
    "pass": "$(json_escape "$pass5")",
    "channel": "$(json_escape "$ch5")",
    "configured_channel": "$(json_escape "$conf_ch5")",
    "real_channel": "$(json_escape "$real_ch5")",
    "power": "$(json_escape "$power5")",
    "interface": "$(json_escape "$IFACE_5G")"
  },
  "wifi24": {
    "ssid": "$(json_escape "$ssid24")",
    "pass": "$(json_escape "$pass24")",
    "channel": "$(json_escape "$ch24")",
    "configured_channel": "$(json_escape "$conf_ch24")",
    "real_channel": "$(json_escape "$real_ch24")",
    "power": "$(json_escape "$power24")",
    "interface": "$(json_escape "$IFACE_24G")"
  }
}
EOF
}


handle_wifi_apply() {
    _detect_radios
    watchdog_backup wireless
    cp -f /etc/config/wireless "$WIRELESS_BACKUP" 2>/dev/null || true

    local sec5="" sec24="" iface dev
    for iface in $(uci show wireless 2>/dev/null | grep "\.mode='ap'" | cut -d. -f1,2); do
        dev=$(uci -q get "${iface}.device")
        [ "$dev" = "$RADIO_5G" ] && [ -z "$sec5" ] && sec5="$iface"
        [ "$dev" = "$RADIO_24G" ] && [ -z "$sec24" ] && sec24="$iface"
    done
    [ -z "$sec5" ] && sec5="wireless.default_${RADIO_5G}"
    [ -z "$sec24" ] && sec24="wireless.default_${RADIO_24G}"

    [ -n "$PARAM_SSID5" ] && uci set "${sec5}.ssid"="$PARAM_SSID5"
    if [ -n "$PARAM_PASS5" ]; then
        uci set "${sec5}.key"="$PARAM_PASS5"
        uci set "${sec5}.encryption"="psk2+ccmp"
    fi
    [ -n "$PARAM_CH5" ] && uci set "wireless.${RADIO_5G}.channel"="$PARAM_CH5"
    [ -n "$PARAM_POWER5" ] && uci set "wireless.${RADIO_5G}.txpower"="$PARAM_POWER5"

    [ -n "$PARAM_SSID24" ] && uci set "${sec24}.ssid"="$PARAM_SSID24"
    if [ -n "$PARAM_PASS24" ]; then
        uci set "${sec24}.key"="$PARAM_PASS24"
        uci set "${sec24}.encryption"="psk2+ccmp"
    fi
    [ -n "$PARAM_CH24" ] && uci set "wireless.${RADIO_24G}.channel"="$PARAM_CH24"
    [ -n "$PARAM_POWER24" ] && uci set "wireless.${RADIO_24G}.txpower"="$PARAM_POWER24"

    uci commit wireless

    # Kích hoạt watchdog tự động rollback sau 60 giây nếu client mất kết nối và không confirm
    watchdog_arm wireless 60

    ( sleep 1; wifi reload ) >/dev/null 2>&1 &
    json_ok '"action":"wifi_apply","watchdog_timeout":60,"message":"Đã áp dụng cấu hình Wi-Fi mới. Cần xác nhận trong 60 giây để tránh tự động hoàn tác."'
}

handle_wifi_confirm() {
    watchdog_confirm wireless
    rm -f "$WIRELESS_BACKUP" 2>/dev/null || true
    json_ok '"action":"wifi_confirm","message":"Đã xác nhận lưu cấu hình Wi-Fi an toàn."'
}

handle_wifi_rollback() {
    watchdog_rollback wireless
    if [ -f "$WIRELESS_BACKUP" ]; then
        cp -f "$WIRELESS_BACKUP" /etc/config/wireless 2>/dev/null
        uci commit wireless 2>/dev/null
        ( sleep 1; wifi reload ) >/dev/null 2>&1 &
        rm -f "$WIRELESS_BACKUP"
    fi
    json_ok '"action":"wifi_rollback","message":"Đã khôi phục cấu hình Wi-Fi ban đầu."'
}

handle_wifi_scan() {
    local scan_band="${PARAM_BAND:-2.4g}"
    [ -n "$POST_BODY" ] && [ -z "$PARAM_BAND" ] && scan_band=$(echo "$POST_BODY" | grep -o '"band":"[^"]*"' | head -n1 | cut -d'"' -f4)
    [ -z "$scan_band" ] && scan_band="2.4g"

    local s_ifname="" ifc ch
    for ifc in $(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}'); do
        case "$ifc" in *sta*|*mon*) continue ;; esac
        ch=$(iw dev "$ifc" info 2>/dev/null | awk '/channel/{print $2}')
        case "$ch" in ''|*[!0-9]*) ch=6 ;; esac
        if [ "$scan_band" = "5g" ] && [ "$ch" -gt 14 ] 2>/dev/null; then
            s_ifname="$ifc"; break
        elif [ "$scan_band" != "5g" ] && [ "$ch" -le 14 ] 2>/dev/null; then
            s_ifname="$ifc"; break
        fi
    done
    [ -z "$s_ifname" ] && [ "$scan_band" = "5g" ] && s_ifname="${IFACE_5G:-wlan1}"
    [ -z "$s_ifname" ] && s_ifname="${IFACE_24G:-wlan0}"

    local scan_out="" networks_json=""
    if command -v iwinfo >/dev/null 2>&1; then
        scan_out=$(iwinfo "$s_ifname" scan 2>/dev/null)
    fi

    if [ -n "$scan_out" ]; then
        networks_json=$(echo "$scan_out" | awk '
        function flush_cell() {
            if (bssid != "" && ssid != "") {
                if (!first) printf ",";
                first = 0;
                printf "{\"ssid\":\"%s\",\"bssid\":\"%s\",\"channel\":%d,\"signal\":%d,\"encryption\":\"%s\"}", ssid, bssid, ch, sig, enc;
            }
        }
        BEGIN { first = 1; printf "["; }
        /Cell [0-9]+/ {
            flush_cell();
            bssid = $5; ssid = ""; ch = 0; sig = -100; enc = "none";
        }
        /ESSID:/ {
            match($0, /"[^"]*"/);
            if (RSTART > 0) ssid = substr($0, RSTART + 1, RLENGTH - 2);
        }
        /Channel:/ { ch = int($NF); }
        /Signal:/ { sig = int($2); }
        /Encryption:/ {
            sub(/^[ \t]*Encryption:[ \t]*/, "", $0);
            enc = $0;
        }
        END { flush_cell(); printf "]"; }
        ')
    else
        scan_out=$(iw dev "$s_ifname" scan 2>/dev/null)
        networks_json=$(echo "$scan_out" | awk '
        function flush_bss() {
            if (bssid != "" && ssid != "") {
                if (!first) printf ",";
                first = 0;
                ch = 1;
                if (freq > 5000) ch = int((freq - 5000) / 5);
                else if (freq > 2400) ch = int((freq - 2407) / 5);
                printf "{\"ssid\":\"%s\",\"bssid\":\"%s\",\"channel\":%d,\"signal\":%d,\"encryption\":\"%s\"}", ssid, bssid, ch, sig, enc;
            }
        }
        BEGIN { first = 1; printf "["; }
        /^BSS / {
            flush_bss();
            bssid = $2; sub(/\(.*$/, "", bssid); ssid = ""; freq = 0; sig = -100; enc = "none";
        }
        /^[ \t]*freq:/ { freq = int($2); }
        /^[ \t]*signal:/ { sig = int($2); }
        /^[ \t]*SSID:/ {
            sub(/^[ \t]*SSID:[ \t]*/, "", $0);
            ssid = $0;
        }
        /RSN:|WPA:/ { enc = "WPA2 PSK"; }
        END { flush_bss(); printf "]"; }
        ')
    fi
    [ -z "$networks_json" ] && networks_json="[]"

    printf '{"status":"ok","band":"%s","interface":"%s","networks":%s}\n' "$scan_band" "$s_ifname" "$networks_json"
}

handle_wifi_connect_uplink() {
    local u_ssid="${PARAM_SSID:-$PARAM_SSID5}"
    [ -z "$u_ssid" ] && u_ssid="${PARAM_SSID24}"
    [ -z "$u_ssid" ] && [ -n "$POST_BODY" ] && u_ssid=$(echo "$POST_BODY" | grep -o '"ssid":"[^"]*"' | head -n1 | cut -d'"' -f4)

    local u_pass="${PARAM_PASS:-$PARAM_PASS5}"
    [ -z "$u_pass" ] && u_pass="${PARAM_KEY}"
    [ -z "$u_pass" ] && [ -n "$POST_BODY" ] && u_pass=$(echo "$POST_BODY" | grep -o '"pass":"[^"]*"' | head -n1 | cut -d'"' -f4)

    local u_band="${PARAM_BAND:-2.4g}"
    [ -n "$POST_BODY" ] && [ -z "$PARAM_BAND" ] && u_band=$(echo "$POST_BODY" | grep -o '"band":"[^"]*"' | head -n1 | cut -d'"' -f4)
    [ -z "$u_band" ] && u_band="2.4g"

    [ -z "$u_ssid" ] && { json_error "Thiếu tên Wi-Fi (SSID)"; return 1; }

    local sta_bak="/tmp/vcrt_wireless_sta.bak"
    cp -f /etc/config/wireless "$sta_bak" 2>/dev/null || true

    _detect_radios
    local target_radio="$RADIO_24G"
    [ "$u_band" = "5g" ] && target_radio="$RADIO_5G"

    # Cấu hình network.wwan nếu chưa có
    if ! uci -q get network.wwan >/dev/null; then
        uci set network.wwan=interface
        uci set network.wwan.proto='dhcp'
        uci commit network
    fi

    # Đưa wwan vào firewall wan zone
    local wan_sec
    wan_sec=$(uci show firewall 2>/dev/null | grep "\.name='wan'" | head -n1 | cut -d. -f1,2)
    if [ -n "$wan_sec" ]; then
        local cur_nets
        cur_nets=$(uci -q get "${wan_sec}.network")
        if ! echo "$cur_nets" | grep -q "wwan"; then
            uci add_list "${wan_sec}.network"='wwan' 2>/dev/null || true
            uci commit firewall
            /etc/init.d/firewall reload >/dev/null 2>&1 &
        fi
    fi

    # Xóa các STA cũ và thêm STA mới
    local s
    for s in $(uci show wireless 2>/dev/null | grep "\.mode='sta'" | cut -d. -f1,2); do
        uci delete "$s"
    done

    uci set wireless.sta=wifi-iface
    uci set wireless.sta.device="$target_radio"
    uci set wireless.sta.mode='sta'
    uci set wireless.sta.network='wwan'
    uci set wireless.sta.ssid="$u_ssid"
    if [ -n "$u_pass" ]; then
        uci set wireless.sta.encryption='psk2'
        uci set wireless.sta.key="$u_pass"
    else
        uci set wireless.sta.encryption='none'
    fi
    uci commit wireless

    wifi reload >/dev/null 2>&1
    sleep 1
    ifup wwan >/dev/null 2>&1

    # Kiểm tra 4-Way Handshake tối đa 7s
    local sta_iface="" connected=0 auth_failed=0 i=0
    while [ "$i" -lt 7 ]; do
        sleep 1
        i=$((i + 1))

        if logread 2>/dev/null | tail -n 40 | grep -qiE "4-Way Handshake failed|pre-shared key may be incorrect|wrong key|MIC failure"; then
            auth_failed=1
            break
        fi

        if [ -z "$sta_iface" ]; then
            local cand
            for cand in $(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}'); do
                case "$cand" in *sta*) sta_iface="$cand"; break ;; esac
            done
        fi

        if [ -n "$sta_iface" ]; then
            if iw dev "$sta_iface" link 2>/dev/null | grep -q "Connected to"; then
                connected=1
                break
            fi
        fi

        if ubus call network.interface.wwan status 2>/dev/null | grep -q '"up": true'; then
            connected=1
            break
        fi
    done

    # Nếu thất bại -> auto rollback ngay lập tức
    if [ "$auth_failed" -eq 1 ] || [ "$connected" -eq 0 ]; then
        if [ -f "$sta_bak" ]; then
            cp -f "$sta_bak" /etc/config/wireless 2>/dev/null || true
            uci commit wireless
            wifi reload >/dev/null 2>&1
            sleep 1
            ifup wwan >/dev/null 2>&1
            rm -f "$sta_bak" 2>/dev/null || true
        fi

        if [ "$auth_failed" -eq 1 ]; then
            json_error "Mật khẩu Wi-Fi không chính xác! Không thể xác thực 4-Way Handshake. Router đã tự động giữ nguyên cấu hình cũ."
        else
            json_error "Không thể kết nối tới Wi-Fi ${u_ssid} (Mật khẩu có thể sai hoặc sóng quá yếu). Router đã tự động giữ nguyên cấu hình cũ."
        fi
        return 1
    fi

    rm -f "$sta_bak" 2>/dev/null || true
    json_ok "\"message\":\"Đã kết nối thành công tới Wi-Fi $(json_escape "$u_ssid")!\""
}
