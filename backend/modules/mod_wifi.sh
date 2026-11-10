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
    if [ -n "$PARAM_CH5" ]; then
        uci set "wireless.${RADIO_5G}.channel"="$PARAM_CH5"
        case "$PARAM_CH5" in
            52|56|60|64|100|104|108|112|116|120|124|128|132|136|140|144)
                uci set "wireless.${RADIO_5G}.acs_exclude_dfs"='0'
                ;;
            *)
                uci set "wireless.${RADIO_5G}.acs_exclude_dfs"='1'
                ;;
        esac
    else
        uci set "wireless.${RADIO_5G}.acs_exclude_dfs"='1'
    fi
    uci set "wireless.${RADIO_5G}.disabled"='0'
    [ -n "$PARAM_POWER5" ] && uci set "wireless.${RADIO_5G}.txpower"="$PARAM_POWER5"

    [ -n "$PARAM_SSID24" ] && uci set "${sec24}.ssid"="$PARAM_SSID24"
    if [ -n "$PARAM_PASS24" ]; then
        uci set "${sec24}.key"="$PARAM_PASS24"
        uci set "${sec24}.encryption"="psk2+ccmp"
    fi
    uci set "wireless.${RADIO_24G}.disabled"='0'
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

_json_field() {
    local json="$1" key="$2"
    printf '%s' "$json" | sed -n "s/.*\"${key}\"[ ]*:[ ]*\"\([^\"]*\)\".*/\1/p" | head -n1
}

_parse_iw_scan_json() {
    local band_label="$1"
    awk -v band="$band_label" '
    function jesc(s) {
        gsub(/\\/, "\\\\", s);
        gsub(/"/, "\\\"", s);
        gsub(/\t/, " ", s);
        return s;
    }
    function flush_bss() {
        if (bssid != "" && ssid != "") {
            if (!first) printf ",";
            first = 0;
            ch = 1;
            if (freq > 5000) ch = int((freq - 5000) / 5);
            else if (freq == 2484) ch = 14;
            else if (freq > 2400) ch = int((freq - 2407) / 5);
            dbm = int(sig);
            pct = (dbm <= -100 ? 0 : (dbm >= -50 ? 100 : 2 * (dbm + 100)));
            sec = "Open";
            if (has_sae && has_psk) sec = "WPA2/WPA3";
            else if (has_sae) sec = "WPA3 SAE";
            else if (has_rsn && has_wpa) sec = "WPA/WPA2 PSK";
            else if (has_rsn) sec = "WPA2 PSK";
            else if (has_wpa) sec = "WPA PSK";
            else if (has_priv) sec = "WEP/PSK";
            essid_e = jesc(ssid);
            bssid_u = toupper(bssid);
            printf "{\"ssid\":\"%s\",\"bssid\":\"%s\",\"channel\":\"%d\",\"signal\":%d,\"rssi\":%d,\"security\":\"%s\",\"encryption\":\"%s\",\"band\":\"%s\"}",
                essid_e, bssid_u, ch, pct, dbm, sec, sec, band;
        }
    }
    BEGIN { first = 1; printf "["; }
    /^BSS / {
        flush_bss();
        bssid = $2; sub(/\(.*$/, "", bssid);
        ssid = ""; freq = 0; sig = -100;
        has_rsn = 0; has_wpa = 0; has_sae = 0; has_psk = 0; has_priv = 0;
    }
    /^[ \t]*freq:/ { freq = int($2); }
    /^[ \t]*signal:/ { sig = int($2); }
    /^[ \t]*capability:/ { if ($0 ~ /Privacy/) has_priv = 1; }
    /^[ \t]*SSID:/ {
        sub(/^[ \t]*SSID:[ \t]*/, "", $0);
        ssid = $0;
    }
    /^[ \t]*RSN:/ { has_rsn = 1; }
    /^[ \t]*WPA:/ { has_wpa = 1; }
    /Authentication suites:/ {
        if ($0 ~ /SAE/) has_sae = 1;
        if ($0 ~ /PSK/) has_psk = 1;
    }
    END { flush_bss(); printf "]"; }
    '
}

_parse_iwinfo_scan_json() {
    local band_label="$1"
    awk -v band="$band_label" '
    function jesc(s) {
        gsub(/\\/, "\\\\", s);
        gsub(/"/, "\\\"", s);
        gsub(/\t/, " ", s);
        return s;
    }
    function flush_cell() {
        if (bssid != "" && ssid != "" && ssid != "unknown") {
            if (!first) printf ",";
            first = 0;
            dbm = int(sig);
            pct = (dbm <= -100 ? 0 : (dbm >= -50 ? 100 : 2 * (dbm + 100)));
            essid_e = jesc(ssid);
            enc_e = jesc(enc);
            printf "{\"ssid\":\"%s\",\"bssid\":\"%s\",\"channel\":\"%d\",\"signal\":%d,\"rssi\":%d,\"security\":\"%s\",\"encryption\":\"%s\",\"band\":\"%s\"}",
                essid_e, toupper(bssid), ch, pct, dbm, enc_e, enc_e, band;
        }
    }
    BEGIN { first = 1; printf "["; }
    /Cell [0-9]+/ {
        flush_cell();
        bssid = $5; ssid = ""; ch = 0; sig = -100; enc = "Open";
    }
    /ESSID:/ {
        match($0, /"[^"]*"/);
        if (RSTART > 0) ssid = substr($0, RSTART + 1, RLENGTH - 2);
    }
    /Channel:/ { ch = int($NF); }
    /Signal:/ { sig = int($2); }
    /Encryption:/ {
        sub(/^[ \t]*Encryption:[ \t]*/, "", $0);
        enc = ($0 == "none" ? "Open" : $0);
    }
    END { flush_cell(); printf "]"; }
    '
}

handle_wifi_scan() {
    _detect_radios

    local scan_band="${PARAM_BAND:-2.4g}"
    [ -n "$POST_BODY" ] && [ -z "$PARAM_BAND" ] && scan_band=$(_json_field "$POST_BODY" "band")
    [ -z "$scan_band" ] && scan_band="2.4g"

    local target_radio="$RADIO_24G" band_label="2.4GHz" default_ifc="$IFACE_24G"
    if [ "$scan_band" = "5g" ]; then
        target_radio="$RADIO_5G"
        band_label="5GHz"
        default_ifc="$IFACE_5G"
    fi

    # Đảm bảo radio không bị tắt
    local rad_disabled
    rad_disabled=$(uci -q get "wireless.${target_radio}.disabled")
    if [ "$rad_disabled" = "1" ]; then
        uci set "wireless.${target_radio}.disabled"='0'
        [ "$scan_band" = "5g" ] && uci set "wireless.${target_radio}.acs_exclude_dfs"='1'
        uci commit wireless
        wifi up "$target_radio" >/dev/null 2>&1 || wifi reload >/dev/null 2>&1
        sleep 3
    fi

    local s_ifname="" sta_cand="" ifc ch
    for ifc in $(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}'); do
        case "$ifc" in *mon*) continue ;; esac
        ch=$(iw dev "$ifc" info 2>/dev/null | awk '/channel/{print $2}')
        case "$ch" in ''|*[!0-9]*) ch=0 ;; esac
        if [ "$scan_band" = "5g" ] && [ "$ch" -gt 14 ] 2>/dev/null; then
            case "$ifc" in
                *sta*) [ -z "$sta_cand" ] && sta_cand="$ifc" ;;
                *) s_ifname="$ifc"; break ;;
            esac
        elif [ "$scan_band" != "5g" ] && [ "$ch" -gt 0 ] && [ "$ch" -le 14 ] 2>/dev/null; then
            case "$ifc" in
                *sta*) [ -z "$sta_cand" ] && sta_cand="$ifc" ;;
                *) s_ifname="$ifc"; break ;;
            esac
        fi
    done
    [ -z "$s_ifname" ] && s_ifname="$sta_cand"
    [ -z "$s_ifname" ] && s_ifname="$default_ifc"

    # Kiểm tra kênh DFS trên 5GHz: Linux mac80211/mt76x2e chặn scan (-EBUSY) nếu AP đang phát kênh DFS (52..144)
    local cur_ch
    cur_ch=$(iw dev "$s_ifname" info 2>/dev/null | awk '/channel/{print $2}')
    case "$cur_ch" in ''|*[!0-9]*) cur_ch=0 ;; esac

    local scan_out="" networks_json="[]"
    scan_out=$(iw dev "$s_ifname" scan ap-force 2>&1)

    if [ "$scan_band" = "5g" ] && echo "$scan_out" | grep -qiE "Resource busy|-16"; then
        # Nếu đang bị kẹt DFS trên AP và không có STA phụ thuộc kênh DFS -> chuyển sang kênh non-DFS CH 36 (5180 MHz) để quét
        local phy_idx has_sta_on_phy=0
        phy_idx=$(iw dev "$s_ifname" info 2>/dev/null | awk '/wiphy/{print $2}')
        if [ -n "$phy_idx" ]; then
            iw dev 2>/dev/null | awk -v p="$phy_idx" '$1=="phy#"p{in_p=1; next} /^phy#/{in_p=0} in_p && /type managed/{found=1} END{exit !found}' && has_sta_on_phy=1
        fi
        if [ "$has_sta_on_phy" -eq 0 ]; then
            uci set "wireless.${RADIO_5G}.acs_exclude_dfs"='1'
            uci set "wireless.${RADIO_5G}.channel"='36'
            uci commit wireless
            ubus call "hostapd.${s_ifname}" switch_chan '{"freq":5180,"bcn_count":2,"center_freq1":5210,"bandwidth":80,"sec_channel_offset":1,"ht":true,"vht":true,"force":true}' >/dev/null 2>&1 || true
            sleep 2
            scan_out=$(iw dev "$s_ifname" scan ap-force 2>&1)
            if echo "$scan_out" | grep -qiE "Resource busy|-16"; then
                wifi up "$RADIO_5G" >/dev/null 2>&1 || wifi reload >/dev/null 2>&1
                sleep 4
                scan_out=$(iw dev "$s_ifname" scan ap-force 2>&1)
            fi
        fi
    fi

    if echo "$scan_out" | grep -q "^BSS "; then
        networks_json=$(printf '%s\n' "$scan_out" | _parse_iw_scan_json "$band_label")
    elif command -v iwinfo >/dev/null 2>&1; then
        local iw_out
        iw_out=$(iwinfo "$s_ifname" scan 2>/dev/null)
        if [ -n "$iw_out" ]; then
            networks_json=$(printf '%s\n' "$iw_out" | _parse_iwinfo_scan_json "$band_label")
        fi
    fi
    [ -z "$networks_json" ] && networks_json="[]"

    printf '{"status":"ok","band":"%s","interface":"%s","networks":%s}\n' "$scan_band" "$s_ifname" "$networks_json"
}

handle_wifi_connect_uplink() {
    local u_ssid="" u_pass="" u_band="" u_channel="" u_bssid="" u_security=""

    if [ -n "$POST_BODY" ]; then
        u_ssid=$(_json_field "$POST_BODY" "ssid")
        u_pass=$(_json_field "$POST_BODY" "key")
        [ -z "$u_pass" ] && u_pass=$(_json_field "$POST_BODY" "pass")
        u_band=$(_json_field "$POST_BODY" "band")
        u_channel=$(_json_field "$POST_BODY" "channel")
        [ -z "$u_channel" ] && u_channel=$(printf '%s' "$POST_BODY" | sed -n 's/.*"channel"[ ]*:[ ]*\([0-9][0-9]*\).*/\1/p' | head -n1)
        u_bssid=$(_json_field "$POST_BODY" "bssid")
        u_security=$(_json_field "$POST_BODY" "security")
    fi

    [ -z "$u_ssid" ] && u_ssid="${PARAM_SSID:-$PARAM_SSID5}"
    [ -z "$u_ssid" ] && u_ssid="${PARAM_SSID24}"
    [ -z "$u_pass" ] && u_pass="${PARAM_KEY:-${PARAM_PASS:-$PARAM_PASS5}}"
    [ -z "$u_band" ] && u_band="${PARAM_BAND:-2.4g}"
    [ -z "$u_channel" ] && u_channel="$PARAM_CHANNEL"
    [ -z "$u_bssid" ] && u_bssid="$PARAM_BSSID"
    [ -z "$u_security" ] && u_security="$PARAM_SECURITY"

    [ -z "$u_band" ] && u_band="2.4g"
    [ -z "$u_ssid" ] && { json_error "Thiếu tên Wi-Fi (SSID)"; return 1; }

    local sta_bak="/tmp/vcrt_wireless_sta.bak"
    cp -f /etc/config/wireless "$sta_bak" 2>/dev/null || true

    _detect_radios
    local target_radio="$RADIO_24G" target_phy_idx="1" max_wait=16
    if [ "$u_band" = "5g" ]; then
        target_radio="$RADIO_5G"
        target_phy_idx="0"
        max_wait=25
    fi

    # Dò tìm đúng phy index từ path/phy trong UCI nếu có
    local r_path r_phy
    r_path=$(uci -q get "wireless.${target_radio}.path")
    r_phy=$(uci -q get "wireless.${target_radio}.phy")
    if [ -n "$r_phy" ]; then
        target_phy_idx=$(echo "$r_phy" | tr -dc '0-9')
    elif [ -n "$r_path" ]; then
        for pdir in /sys/class/ieee80211/phy*; do
            [ -e "$pdir/device" ] || continue
            if readlink -f "$pdir/device" 2>/dev/null | grep -q "$r_path"; then
                target_phy_idx=$(basename "$pdir" | tr -dc '0-9')
                break
            fi
        done
    fi

    # Đảm bảo radio bật và đồng bộ kênh an toàn (tránh AP bị kẹt DFS 60s trước khi STA kịp quét)
    uci set "wireless.${target_radio}.disabled"='0'
    if [ "$u_band" = "5g" ]; then
        uci set "wireless.${target_radio}.acs_exclude_dfs"='1'
        case "$u_channel" in
            36|40|44|48|149|153|157|161|165)
                uci set "wireless.${target_radio}.channel"="$u_channel"
                ;;
            *)
                # Kênh gốc là DFS hoặc không rõ -> đặt non-DFS auto để AP lên ngay, sau đó STA sẽ kéo AP theo kênh gốc
                uci set "wireless.${target_radio}.channel"='auto'
                ;;
        esac
    elif [ -n "$u_channel" ]; then
        case "$u_channel" in
            [1-9]|1[0-3]) uci set "wireless.${target_radio}.channel"="$u_channel" ;;
        esac
    fi

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

    local enc="psk2"
    if [ -z "$u_pass" ]; then
        enc="none"
    else
        case "$u_security" in
            *WPA2/WPA3*) enc="sae-mixed" ;;
            *SAE*|*WPA3*)
                if echo "$u_security" | grep -qi "PSK"; then enc="sae-mixed"; else enc="sae"; fi
                ;;
            *WPA\ PSK*)
                if echo "$u_security" | grep -qi "WPA2\|RSN"; then enc="psk2"; else enc="psk"; fi
                ;;
        esac
    fi

    uci set wireless.sta=wifi-iface
    uci set wireless.sta.device="$target_radio"
    uci set wireless.sta.mode='sta'
    uci set wireless.sta.network='wwan'
    uci set wireless.sta.ssid="$u_ssid"
    uci set wireless.sta.encryption="$enc"
    [ -n "$u_pass" ] && uci set wireless.sta.key="$u_pass"
    uci commit wireless

    local log_mark
    log_mark=$(logread 2>/dev/null | wc -l)
    case "$log_mark" in ''|*[!0-9]*) log_mark=0 ;; esac

    wifi reload >/dev/null 2>&1
    sleep 1
    ifup wwan >/dev/null 2>&1

    # Kiểm tra kết nối & 4-Way Handshake (tối đa 25s cho 5GHz, 16s cho 2.4GHz)
    local sta_iface="" connected=0 auth_failed=0 i=0
    while [ "$i" -lt "$max_wait" ]; do
        sleep 1
        i=$((i + 1))

        if logread 2>/dev/null | tail -n +"$((log_mark + 1))" | grep -qiE "4-Way Handshake failed|pre-shared key may be incorrect|wrong key|MIC failure"; then
            auth_failed=1
            break
        fi

        if [ -z "$sta_iface" ]; then
            local cand
            for cand in $(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}'); do
                case "$cand" in
                    phy${target_phy_idx}-sta*|*sta*)
                        sta_iface="$cand"
                        case "$cand" in phy${target_phy_idx}-sta*) break ;; esac
                        ;;
                esac
            done
        fi

        if [ -n "$sta_iface" ]; then
            if iw dev "$sta_iface" link 2>/dev/null | grep -q "Connected to"; then
                connected=1
                break
            fi
            if ubus call "wpa_supplicant.${sta_iface}" iface_status 2>/dev/null | grep -q '"state": "COMPLETED"'; then
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
