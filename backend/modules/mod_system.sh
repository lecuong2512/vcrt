#!/bin/sh
# VCRT OS v2.0 - System Module
# Endpoints: status, clean_ram, reboot, reset_peak_bw, modem_get

# Đảm bảo fallback biến platform
: "${DEVICE_NAME_DEFAULT:=Xiaomi MiWiFi Mini}"
: "${FLASH_CHIP_MB:=16.0}"
: "${RAM_DEFAULT_TOTAL:=128}"
: "${PORT_WAN:=4}"
: "${PORT_LAN1:=0}"
: "${PORT_LAN2:=1}"
: "${THERMAL_PATH:=/sys/class/thermal/thermal_zone0/temp}"

handle_status() {
    # 1. Real Uptime
    local up_sec days hours mins up_str
    up_sec=$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)
    days=$((up_sec / 86400))
    hours=$(( (up_sec % 86400) / 3600 ))
    mins=$(( (up_sec % 3600) / 60 ))
    up_str=""
    [ "$days" -gt 0 ] && up_str="${days} ngày "
    up_str="${up_str}${hours} giờ ${mins} phút"

    # 2. Real CPU Load %
    local cpu_pct=0 u2 n2 s2 i2 w2 ir2 si2 tot2 busy2
    read -r _ u2 n2 s2 i2 w2 ir2 si2 _ < /proc/stat 2>/dev/null
    tot2=$((u2 + n2 + s2 + i2 + w2 + ir2 + si2))
    busy2=$((u2 + n2 + s2 + ir2 + si2))
    if [ -f "$CPU_TMP_FILE" ]; then
        local tot1 busy1 diff_tot diff_busy
        read -r tot1 busy1 < "$CPU_TMP_FILE" 2>/dev/null
        diff_tot=$((tot2 - tot1))
        diff_busy=$((busy2 - busy1))
        if [ "$diff_tot" -gt 0 ]; then
            cpu_pct=$((diff_busy * 100 / diff_tot))
        fi
    else
        cpu_pct=$(awk '{p=int($1*20); if(p>100) p=100; if(p<5) p=5; print p}' /proc/loadavg 2>/dev/null || echo 12)
    fi
    echo "$tot2 $busy2" > "$CPU_TMP_FILE" 2>/dev/null
    [ "$cpu_pct" -gt 100 ] && cpu_pct=100
    [ "$cpu_pct" -lt 0 ] && cpu_pct=0

    # 3. Real RAM (MB)
    local mem_total mem_avail mem_used
    eval $(awk '/MemTotal/{t=int($2/1024)} /MemAvailable/{a=int($2/1024)} END{printf "mem_total=%d mem_avail=%d",t,a}' /proc/meminfo 2>/dev/null)
    [ -z "$mem_total" ] || [ "$mem_total" -le 0 ] 2>/dev/null && mem_total="${RAM_DEFAULT_TOTAL:-128}"
    [ -z "$mem_avail" ] || [ "$mem_avail" -le 0 ] 2>/dev/null && mem_avail=30
    mem_used=$((mem_total - mem_avail))
    [ "$mem_used" -lt 0 ] && mem_used=0

    # 4. Device Model Name
    local model_name
    if [ -f "$MODEL_TMP_FILE" ]; then
        model_name=$(cat "$MODEL_TMP_FILE")
    else
        model_name=$(cat /tmp/sysinfo/model 2>/dev/null)
        [ -z "$model_name" ] && model_name=$(awk -F: '/machine/ {gsub(/^ /,"",$2); print $2}' /proc/cpuinfo 2>/dev/null)
        [ -z "$model_name" ] && model_name="$DEVICE_NAME_DEFAULT"
        echo "$model_name" > "$MODEL_TMP_FILE"
    fi

    # 5. OS & Kernel Version
    local os_name kernel_ver
    if [ -f "$OSINFO_TMP_FILE" ]; then
        read -r os_name < "$OSINFO_TMP_FILE"
    else
        os_name=""
        if [ -f /etc/openwrt_release ]; then
            . /etc/openwrt_release
            os_name="${DISTRIB_DESCRIPTION:-OpenWrt 25.12}"
        fi
        [ -z "$os_name" ] && os_name="OpenWrt 25.12"
        echo "$os_name" > "$OSINFO_TMP_FILE"
    fi
    kernel_ver=$(uname -r 2>/dev/null || echo "6.12.103")

    # 6. Flash ROM Storage (df cached 60s)
    local flash_chip="$FLASH_CHIP_MB"
    local overlay_total=4.0 overlay_used=1.8 overlay_avail=2.2 overlay_pct=45 df_stale=1
    if [ -f "$DF_TMP_FILE" ]; then
        local df_age
        df_age=$(( $(cut -d. -f1 /proc/uptime) - $(head -1 "$DF_TMP_FILE" 2>/dev/null || echo 0) ))
        [ "$df_age" -lt 60 ] 2>/dev/null && df_stale=0
    fi
    if [ "$df_stale" -eq 1 ]; then
        local df_line
        df_line=$(df -k /overlay 2>/dev/null | awk 'NR==2 {printf "%.1f %.1f %.1f %d", $2/1024, $3/1024, $4/1024, ($3*100/$2)}')
        [ -z "$df_line" ] && df_line=$(df -k / 2>/dev/null | awk 'NR==2 {printf "%.1f %.1f %.1f %d", $2/1024, $3/1024, $4/1024, ($3*100/$2)}')
        echo "$(cut -d. -f1 /proc/uptime)" > "$DF_TMP_FILE"
        echo "$df_line" >> "$DF_TMP_FILE"
    else
        df_line=$(sed -n '2p' "$DF_TMP_FILE")
    fi
    if [ -n "$df_line" ]; then
        overlay_total=$(echo "$df_line" | awk '{print $1}')
        overlay_used=$(echo "$df_line" | awk '{print $2}')
        overlay_avail=$(echo "$df_line" | awk '{print $3}')
        overlay_pct=$(echo "$df_line" | awk '{print $4}')
    fi
    case "$overlay_total" in ''|*[!0-9.]*) overlay_total=4.0 ;; esac
    case "$overlay_used" in ''|*[!0-9.]*) overlay_used=1.8 ;; esac
    case "$overlay_avail" in ''|*[!0-9.]*) overlay_avail=2.0 ;; esac
    case "$overlay_pct" in ''|*[!0-9]*) overlay_pct=45 ;; esac

    # 7. WAN Interface & IP
    local wan_iface="eth0" wan_ip="" def_route def_dev def_gw
    def_route=$(ip route show default 2>/dev/null | head -n1)
    def_dev=$(echo "$def_route" | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')
    def_gw=$(echo "$def_route" | awk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}')

    if [ -n "$def_dev" ]; then
        wan_iface="$def_dev"
        wan_ip=$(ip -4 addr show dev "$def_dev" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)
    fi
    if [ -z "$wan_ip" ]; then
        for ifc in eth0.2 eth0 usb0 phy0-sta0 wlan0-sta; do
            [ -d "/sys/class/net/$ifc" ] || continue
            local ip_cand
            ip_cand=$(ip -4 addr show dev "$ifc" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)
            if [ -n "$ip_cand" ]; then
                wan_iface="$ifc"; wan_ip="$ip_cand"; break
            fi
        done
    fi
    [ -z "$wan_ip" ] && wan_ip="Chưa kết nối Internet"

    # 8. Switch Ports
    local wan_up="false" lan1_up="false" lan2_up="false"
    local wan_speed="Chưa cắm cáp" lan1_speed="Chưa cắm cáp" lan2_speed="Chưa cắm cáp"

    if command -v swconfig >/dev/null 2>&1; then
        local pw p1 p2
        pw=$(swconfig dev switch0 port "$PORT_WAN" get link 2>/dev/null)
        if echo "$pw" | grep -q "link:up"; then
            wan_up="true"
            case "$pw" in *speed:1000*) wan_speed="1 Gbps (Full-Duplex)";; *speed:100*) wan_speed="100 Mbps (Full-Duplex)";; *) wan_speed="100 Mbps";; esac
        fi
        p1=$(swconfig dev switch0 port "$PORT_LAN1" get link 2>/dev/null)
        if echo "$p1" | grep -q "link:up"; then
            lan1_up="true"
            lan1_speed="100 Mbps (Full-Duplex)"
        fi
        p2=$(swconfig dev switch0 port "$PORT_LAN2" get link 2>/dev/null)
        if echo "$p2" | grep -q "link:up"; then
            lan2_up="true"
            lan2_speed="100 Mbps (Full-Duplex)"
        fi
    fi

    # 9. USB Port
    local usb_connected="false" usb_name="Chưa cắm thiết bị"
    for dev in /sys/bus/usb/devices/[0-9]*; do
        [ ! -d "$dev" ] && continue
        case "$dev" in *":"*|*"usb"*) continue ;; esac
        local prod mfg
        prod=$(cat "$dev/product" 2>/dev/null); mfg=$(cat "$dev/manufacturer" 2>/dev/null)
        if [ -n "$prod" ] || [ -n "$mfg" ]; then
            usb_connected="true"; usb_name=$(echo "${mfg} ${prod}" | xargs); break
        fi
    done
    [ "$usb_connected" = "false" ] && [ -d "/sys/class/net/usb0" ] && { usb_connected="true"; usb_name="USB 4G Dongle Modem (usb0)"; }

    # 10. ISP Name Detection
    local isp_name=""
    if [ -f "$ISP_TMP_FILE" ]; then
        read -r isp_name < "$ISP_TMP_FILE" 2>/dev/null
    fi
    if [ -z "$isp_name" ]; then
        local dns_hints
        dns_hints=$(cat /tmp/resolv.conf.auto /etc/resolv.conf 2>/dev/null)
        if echo "$dns_hints" | grep -q "203\.113"; then isp_name="Viettel Telecom"
        elif echo "$dns_hints" | grep -qE "203\.162|203\.210"; then isp_name="VNPT Telecom"
        elif echo "$dns_hints" | grep -qE "118\.69|210\.245"; then isp_name="FPT Telecom"
        else isp_name="Viettel Group"; fi
        ( curl -s -m 2 http://ip-api.com/line/?fields=isp 2>/dev/null > "$ISP_TMP_FILE" & )
    fi
    [ -z "$isp_name" ] && isp_name="Viettel Group"

    # 11. Uplink Detection
    local uplink_type="none" uplink_title="Chưa kết nối Internet"
    local uplink_ssid="N/A" uplink_bssid="N/A" uplink_channel="N/A" uplink_band="N/A"
    local uplink_signal_dbm=-100 uplink_signal_pct=0 uplink_gw="192.168.1.1"
    [ -n "$def_gw" ] && uplink_gw="$def_gw"
    [ -z "$def_dev" ] && def_dev="$wan_iface"

    local _is_sta=0
    case "$def_dev" in
        phy0-sta0|wlan0-sta|phy1-sta0) _is_sta=1 ;;
        *) [ "$wan_iface" = "phy0-sta0" ] && _is_sta=1 || _is_sta=0 ;;
    esac
    if [ "$_is_sta" = "1" ]; then
        local sta_dev="phy0-sta0" iw_link
        [ -d "/sys/class/net/$def_dev" ] && sta_dev="$def_dev"
        iw_link=$(iw dev "$sta_dev" link 2>/dev/null)
        if echo "$iw_link" | grep -q "Connected to"; then
            uplink_type="repeater"
            uplink_title="Kích sóng Wi-Fi Không Dây (WISP Repeater)"
            uplink_ssid=$(echo "$iw_link" | awk -F'SSID: ' '/SSID:/{print $2}')
            uplink_bssid=$(echo "$iw_link" | awk '/Connected to/{print $3}')
            uplink_signal_dbm=$(echo "$iw_link" | awk '/signal:/{print int($2)}')
            local freq
            freq=$(echo "$iw_link" | awk '/freq:/{print int($2)}')
            case "$freq" in ''|*[!0-9]*) freq=5785 ;; esac
            if [ "$freq" -gt 5000 ] 2>/dev/null; then
                uplink_band="5 GHz"; uplink_channel=$(( (freq - 5000) / 5 ))
            else
                uplink_band="2.4 GHz"; uplink_channel=$(( (freq - 2407) / 5 ))
            fi
            case "$uplink_signal_dbm" in ''|*[!0-9-]*) uplink_signal_dbm=-65 ;; esac
            if [ "$uplink_signal_dbm" -ge -50 ] 2>/dev/null; then uplink_signal_pct=100
            elif [ "$uplink_signal_dbm" -le -100 ] 2>/dev/null; then uplink_signal_pct=0
            else uplink_signal_pct=$(( 2 * (uplink_signal_dbm + 100) ))
            fi
        fi
    fi

    if [ "$uplink_type" = "none" ]; then
        case "$def_dev" in usb0|wwan0) uplink_type="cellular"; uplink_title="Modem Di Động 4G USB (LTE Dongle)"; uplink_ssid="Mạng di động 4G (usb0)"; uplink_band="LTE 4G"; uplink_channel="Auto"; uplink_signal_pct=85; uplink_signal_dbm=-75 ;; esac
        [ "$uplink_type" = "none" ] && [ "$wan_iface" = "usb0" ] && { uplink_type="cellular"; uplink_title="Modem Di Động 4G USB (LTE Dongle)"; uplink_ssid="Mạng di động 4G (usb0)"; uplink_band="LTE 4G"; uplink_channel="Auto"; uplink_signal_pct=85; uplink_signal_dbm=-75; }
    fi

    if [ "$uplink_type" = "none" ]; then
        case "$def_dev" in
            eth0|eth0.2) uplink_type="ethernet"; uplink_title="Cáp Mạng Cổng WAN (Ethernet)"; uplink_ssid="Cáp mạng quang WAN"; uplink_band="Ethernet"; uplink_channel="$wan_speed"; uplink_signal_pct=100; uplink_signal_dbm=0 ;;
            br-lan|eth0.1) uplink_type="ethernet"; uplink_title="Dây Mạng Cáp LAN (Cầu Nối AP)"; uplink_ssid="Dây mạng cắm cổng LAN"; uplink_band="LAN Ethernet"; uplink_channel="100 Mbps"; uplink_signal_pct=100; uplink_signal_dbm=0 ;;
        esac
        [ "$uplink_type" = "none" ] && [ "$wan_up" = "true" ] && { uplink_type="ethernet"; uplink_title="Cáp Mạng Cổng WAN (Ethernet)"; uplink_ssid="Cáp mạng quang WAN"; uplink_band="Ethernet"; uplink_channel="$wan_speed"; uplink_signal_pct=100; uplink_signal_dbm=0; }
    fi

    # 12. NextDNS Status
    local ndns_active="false" ndns_info="Chưa bật"
    pidof nextdns >/dev/null 2>&1 && { ndns_active="true"; ndns_info="NextDNS Daemon đang hoạt động 🟢"; }

    # 13. Network live & traffic calculations from mod_network
    calc_network_stats "$wan_iface"

    # 14. Output JSON
    cat << EOF
{
  "uptime": "$(json_escape "$up_str")",
  "cpu": ${cpu_pct},
  "ram_used": ${mem_used},
  "ram_total": ${mem_total},
  "ram_avail": ${mem_avail},
  "dl_mbps": ${dl_mbps},
  "ul_mbps": ${ul_mbps},
  "wan_ip": "$(json_escape "$wan_ip")",
  "device_name": "$(json_escape "$model_name")",
  "os_version": "$(json_escape "$os_name")",
  "kernel_version": "$(json_escape "$kernel_ver")",
  "flash": {
    "chip_mb": ${flash_chip},
    "total_mb": ${flash_chip},
    "overlay_total_mb": ${overlay_total},
    "overlay_used_mb": ${overlay_used},
    "overlay_avail_mb": ${overlay_avail},
    "overlay_pct": ${overlay_pct},
    "used_mb": ${overlay_used},
    "avail_mb": ${overlay_avail},
    "used_pct": ${overlay_pct}
  },
  "ports": {
    "wan": { "up": ${wan_up}, "speed": "$(json_escape "$wan_speed")", "label": "Cổng WAN (Vào)" },
    "lan1": { "up": ${lan1_up}, "speed": "$(json_escape "$lan1_speed")", "label": "Cổng LAN 1 (Ra)" },
    "lan2": { "up": ${lan2_up}, "speed": "$(json_escape "$lan2_speed")", "label": "Cổng LAN 2 (Ra)" },
    "usb": { "connected": ${usb_connected}, "name": "$(json_escape "$usb_name")", "label": "Cổng USB 2.0" }
  },
  "uplink": {
    "type": "$(json_escape "$uplink_type")",
    "title": "$(json_escape "$uplink_title")",
    "isp": "$(json_escape "$isp_name")",
    "ssid": "$(json_escape "$uplink_ssid")",
    "bssid": "$(json_escape "$uplink_bssid")",
    "channel": "$(json_escape "$uplink_channel")",
    "band": "$(json_escape "$uplink_band")",
    "signal_dbm": ${uplink_signal_dbm},
    "signal_pct": ${uplink_signal_pct},
    "gateway": "$(json_escape "$uplink_gw")"
  },
  "nextdns": {
    "active": ${ndns_active},
    "node": "$(json_escape "$ndns_info")"
  },
  "traffic": {
    "dl": "$(json_escape "$tot_rx_str")",
    "ul": "$(json_escape "$tot_tx_str")",
    "total": "$(json_escape "$tot_sum_str")"
  },
  "peak_bandwidth": {
    "dl_mbps": ${peak_dl},
    "ul_mbps": ${peak_ul}
  },
  "traffic_stats": ${traffic_stats_json}
}
EOF
}

handle_clean_ram() {
    sync && echo 3 > /proc/sys/vm/drop_caches
    local mem_avail
    mem_avail=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 80)
    json_ok "\"mem_avail\":${mem_avail}"
}

handle_reboot() {
    ( sleep 2; /sbin/reboot ) >/dev/null 2>&1 &
    json_ok '"action":"rebooting"'
}

handle_modem_get() {
    local has_usb_modem="false" model="Không có modem 4G USB"
    local operator="N/A" band="N/A" rsrp="0" sinr="0"

    if [ -d "/sys/class/net/usb0" ] || ls /dev/ttyUSB* /dev/cdc-wdm* >/dev/null 2>&1; then
        has_usb_modem="true"
        model="USB 4G Modem"
        operator="Đang kết nối (usb0)"
        rsrp="-75"
        sinr="15.0"
    fi

    cat << EOF
{
  "connected": ${has_usb_modem},
  "model": "$(json_escape "$model")",
  "operator": "$(json_escape "$operator")",
  "band": "$(json_escape "$band")",
  "rsrp": ${rsrp},
  "sinr": ${sinr},
  "messages": []
}
EOF
}
