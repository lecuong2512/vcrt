#!/bin/sh
# ==============================================================================
# SCRIPT TOI UU HOA TOAN DIEN CHO XIAOMI MIWIFI MINI (MT7620A / 128MB RAM)
# Toi uu: Mang day LAN / Wi-Fi Repeater / Cam USB 4G phat Wi-Fi
# Toc do toi da, giam Ping/Jitter (BBR + HW NAT), Quan ly RAM, Bao mat va LuCI Overview
# IP LAN: 192.168.10.1
# ==============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}==================================================================${NC}"
echo -e "${GREEN}   BAT DAU TOI UU HOA ROUTER XIAOMI MIWIFI MINI (KWRT/OPENWRT)   ${NC}"
echo -e "${CYAN}==================================================================${NC}"

# 1. THIET LAP IP MANG LAN VA DHCP (192.168.10.1)
echo -e "${YELLOW}[1/8] Cau hinh dia chi IP LAN thanh 192.168.10.1...${NC}"
uci set network.lan.ipaddr='192.168.10.1'
uci set network.lan.netmask='255.255.255.0'
uci set dhcp.lan.start='100'
uci set dhcp.lan.limit='150'
uci set dhcp.lan.leasetime='12h'

# 2. CAU HINH GIAO DIEN USB 4G DONGLE (RNDIS / CDC-ETHER / QMI)
echo -e "${YELLOW}[2/8] Thiet lap ho tro USB 4G cam la chay (Auto Hotplug / Metric 20)...${NC}"
uci -q get network.wan_4g || uci set network.wan_4g=interface
uci set network.wan_4g.device='usb0'
uci set network.wan_4g.proto='dhcp'
uci set network.wan_4g.metric='20'

# Gan giao dien 4G vao Firewall Zone WAN
uci -q del_list firewall.@zone[1].network='wan_4g' 2>/dev/null || true
uci add_list firewall.@zone[1].network='wan_4g'

# 3. KICH HOAT HARDWARE FLOW OFFLOADING (MEDIATEK PPE HNAT) VA GIAM DO TRE
echo -e "${YELLOW}[3/8] Bat MediaTek Hardware NAT (PPE HNAT) ha tai CPU...${NC}"
uci set firewall.@defaults[0].flow_offloading='1'
uci set firewall.@defaults[0].flow_offloading_hw='1'

# 4. TOI UU THUAT TOAN DIEU KHIEN TAC NGHEN BBR VA HANG DOI FQ_CODEL
echo -e "${YELLOW}[4/8] Kich hoat TCP BBR, chong Bufferbloat va tinh chinh bo nho dem...${NC}"
cat << 'EOF' > /etc/sysctl.d/99-miwifi-opt.conf
# Toi uu mang va bo nho cho Xiaomi MiWiFi Mini (MT7620A)
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq_codel
vm.vfs_cache_pressure = 150
vm.swappiness = 25
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_fin_timeout = 20
net.ipv4.tcp_keepalive_time = 300
net.netfilter.nf_conntrack_max = 32768
EOF
sysctl -p /etc/sysctl.d/99-miwifi-opt.conf 2>/dev/null || true

# 5. TOI UU HOA WI-FI 2.4GHz VA 5GHz
echo -e "${YELLOW}[5/8] Toi uu cau hinh phat song Wi-Fi 2.4G va 5G...${NC}"
# 2.4GHz MT7620: Bang thong 20MHz de chong nhieu, kenh 6, WMM bat
if uci -q get wireless.radio0 >/dev/null; then
    uci set wireless.radio0.country='VN'
    uci set wireless.radio0.channel='6'
    uci set wireless.radio0.htmode='HT20'
    uci set wireless.radio0.disabled='0'
    uci -q get wireless.default_radio0 >/dev/null && {
        uci set wireless.default_radio0.ssid='Xiaomi_2.4G'
        uci set wireless.default_radio0.encryption='psk2+ccmp'
        uci set wireless.default_radio0.key='12345678'
        uci set wireless.default_radio0.wmm='1'
    }
fi

# 5GHz MT7612E: Bang thong 80MHz kenh 44 (Non-DFS), Short GI bat
if uci -q get wireless.radio1 >/dev/null; then
    uci set wireless.radio1.country='VN'
    uci set wireless.radio1.channel='44'
    uci set wireless.radio1.htmode='VHT80'
    uci set wireless.radio1.disabled='0'
    uci -q get wireless.default_radio1 >/dev/null && {
        uci set wireless.default_radio1.ssid='Xiaomi_5G'
        uci set wireless.default_radio1.encryption='psk2+ccmp'
        uci set wireless.default_radio1.key='12345678'
        uci set wireless.default_radio1.wmm='1'
        uci set wireless.default_radio1.short_gi_80='1'
    }
fi

# 6. QUAN LY RAM VA DON DEP DICH VU THUA
echo -e "${YELLOW}[6/8] Toi uu ZRAM Swap va tat cac dich vu rac...${NC}"
uci set system.@system[0].hostname='MiWiFi-Mini'
uci set system.@system[0].zonename='Asia/Ho_Chi_Minh'
uci set system.@system[0].timezone='ICT-7'
uci set system.@system[0].zram_size_mb='32'

# Tat dich vu dieu khien quat (router khong co quat)
/etc/init.d/luci-fan disable 2>/dev/null || true
/etc/init.d/luci-fan stop 2>/dev/null || true

# 7. GIA CO BAO MAT VA DNS REBINDING
echo -e "${YELLOW}[7/8] Khoa cong SSH va chong gia mao DNS Rebinding...${NC}"
uci set dropbear.main.Interface='lan'
uci set dropbear.main.PasswordAuth='on'
uci set dropbear.main.RootPasswordAuth='on'

uci set dhcp.@dnsmasq[0].rebind_protection='1'
uci set dhcp.@dnsmasq[0].rebind_localhost='1'
uci set dhcp.@dnsmasq[0].cachesize='1500'

# 8. MO KHOA HIEN THI DU THONG SO TREN TRANG CHU LUCI
echo -e "${YELLOW}[8/8] Tinh chinh LuCI Overview hien thi tuc thi RAM, ROM, Thiet bi ket noi, Toc do...${NC}"
INDEX_JS="/www/luci-static/resources/view/status/index.js"
if [ -f "$INDEX_JS" ]; then
    sed -i 's/deferFirstLoad:true/deferFirstLoad:false/g' "$INDEX_JS"
fi

# Luu cau hinh UCI
uci commit network
uci commit dhcp
uci commit firewall
uci commit wireless
uci commit system
uci commit dropbear

echo -e "${CYAN}==================================================================${NC}"
echo -e "${GREEN}            DA HOAN TAT TOI UU HOA THANH CONG!                   ${NC}"
echo -e "${CYAN}==================================================================${NC}"
echo -e "${YELLOW}Luu y quan trong:${NC}"
echo -e "1. Dia chi quan tri moi cua router: ${GREEN}http://192.168.10.1${NC}"
echo -e "2. Ten Wi-Fi: ${CYAN}Xiaomi_2.4G${NC} va ${CYAN}Xiaomi_5G${NC} (Mat khau mac dinh: 12345678)"
echo -e "3. Router se khoi dong lai dich vu mang sau 3 giay..."

sleep 3
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/dnsmasq restart
exit 0
