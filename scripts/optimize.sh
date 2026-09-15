#!/bin/sh
# ==============================================================================
# VCRT OS v2.0 - KERNEL & SYSTEM MULTI-PLATFORM OPTIMIZER
# Tinh chinh hieu nang: TCP BBR, fq_codel, Hardware NAT, ZRAM, DHCP, USB 4G
# Tuong thich: Xiaomi Mini, Xiaomi 4A, GL.iNet, MediaTek Filogic, Generic OpenWrt
# ==============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}==================================================================${NC}"
echo -e "${GREEN}   ⚡ TOI UU HOA HE THONG & KERNEL VCRT OS v2.0 (DA PLATFORM)   ${NC}"
echo -e "${CYAN}==================================================================${NC}"

# 1. Nhan dien phan cung tu Platform Abstraction Layer
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR=""
if [ -d "/www/cgi-bin/platforms" ]; then
    PLATFORM_DIR="/www/cgi-bin/platforms"
elif [ -d "$SCRIPT_DIR/../backend/platforms" ]; then
    PLATFORM_DIR="$SCRIPT_DIR/../backend/platforms"
elif [ -d "$SCRIPT_DIR/platforms" ]; then
    PLATFORM_DIR="$SCRIPT_DIR/platforms"
fi

if [ -f "/www/cgi-bin/lib/platform.sh" ]; then
    export PLATFORM_DIR
    . "/www/cgi-bin/lib/platform.sh"
    detect_platform
elif [ -f "$SCRIPT_DIR/../backend/lib/platform.sh" ]; then
    export PLATFORM_DIR
    . "$SCRIPT_DIR/../backend/lib/platform.sh"
    detect_platform
fi

# Fallback neu chua nhan dien
[ -z "$PLATFORM_ID" ] && PLATFORM_ID="generic"
[ -z "$DEVICE_NAME_DEFAULT" ] && DEVICE_NAME_DEFAULT="OpenWrt Router"
[ -z "$HAS_HWNAT" ] && HAS_HWNAT=true
[ -z "$HAS_USB" ] && HAS_USB=true

# Tinh toan dung luong RAM thuc te
real_ram=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo "${RAM_DEFAULT_TOTAL:-128}")
[ -z "$real_ram" ] || [ "$real_ram" -le 0 ] && real_ram=128

echo -e "${YELLOW}>> Thong tin phan cung Router:${NC}"
echo -e "   - Thiet bi: ${GREEN}${DEVICE_NAME_DEFAULT}${NC} (Platform: ${CYAN}${PLATFORM_ID}${NC})"
echo -e "   - RAM thuc: ${GREEN}${real_ram} MB${NC}"
echo -e "   - HWNAT   : ${GREEN}${HAS_HWNAT}${NC}"

# 2. TOI UU TCP BBR VA HANG DOI FQ_CODEL (Chong Bufferbloat)
echo -e "${YELLOW}[1/7] Tinh chinh Thuat toan dieu khien tac nghen BBR & Kernel Sysctl...${NC}"
modprobe tcp_bbr 2>/dev/null || true
cc_alg="bbr"
if ! grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
    cc_alg="cubic"
fi

# Conntrack va Swap tuy theo dung luong RAM
if [ "$real_ram" -le 64 ]; then
    conn_max=16384
    swappiness=30
    zram_mb=16
elif [ "$real_ram" -le 128 ]; then
    conn_max=32768
    swappiness=25
    zram_mb=32
elif [ "$real_ram" -le 256 ]; then
    conn_max=65536
    swappiness=15
    zram_mb=64
else
    conn_max=131072
    swappiness=10
    zram_mb=128
fi

mkdir -p /etc/sysctl.d 2>/dev/null
cat << EOF > /etc/sysctl.d/99-vcrt-opt.conf
# VCRT OS v2.0 Kernel Optimization for ${DEVICE_NAME_DEFAULT}
net.ipv4.tcp_congestion_control = ${cc_alg}
net.core.default_qdisc = fq_codel
vm.vfs_cache_pressure = 150
vm.swappiness = ${swappiness}
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_fin_timeout = 20
net.ipv4.tcp_keepalive_time = 300
net.netfilter.nf_conntrack_max = ${conn_max}
EOF
sysctl -p /etc/sysctl.d/99-vcrt-opt.conf 2>/dev/null || true
echo -e "   -> Congestion Control: ${GREEN}${cc_alg}${NC} | QDisc: ${GREEN}fq_codel${NC} | Conntrack Max: ${GREEN}${conn_max}${NC}"

# 3. KICH HOAT HARDWARE FLOW OFFLOADING (HWNAT / PPE)
echo -e "${YELLOW}[2/7] Cau hinh Hardware Flow Offloading (MediaTek PPE / HNAT)...${NC}"
uci set firewall.@defaults[0].flow_offloading='1'
if [ "$HAS_HWNAT" = "true" ]; then
    uci set firewall.@defaults[0].flow_offloading_hw='1'
    echo -e "   -> Da bat Hardware Flow Offloading (PPE HNAT) giam tai CPU gan nhu bang 0."
else
    uci set firewall.@defaults[0].flow_offloading_hw='0'
    echo -e "   -> Da bat Software Flow Offloading (Router khong ho tro HWNAT)."
fi

# 4. QUAN LY BO NHO RAM VA ZRAM SWAP
echo -e "${YELLOW}[3/7] Thiet lap bo nho ao ZRAM Swap (${zram_mb} MB) va Hostname...${NC}"
uci set system.@system[0].hostname="${DEVICE_NAME_DEFAULT%% *}"
uci set system.@system[0].zonename='Asia/Ho_Chi_Minh'
uci set system.@system[0].timezone='ICT-7'
uci set system.@system[0].zram_size_mb="${zram_mb}"

# Tat dich vu luci-fan neu router khong co quat
if [ "$PLATFORM_ID" = "xiaomi_mini" ] || [ "$PLATFORM_ID" = "xiaomi_4a" ]; then
    /etc/init.d/luci-fan disable 2>/dev/null || true
    /etc/init.d/luci-fan stop 2>/dev/null || true
fi

# 5. CAU HINH MANG LAN, DNSMASQ VA BAO MAT DROPBEAR
echo -e "${YELLOW}[4/7] Toi uu DHCP Cache, DNS Rebinding Protection va Bao mat...${NC}"
current_lan=$(uci -q get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1")
uci set dhcp.lan.start='100'
uci set dhcp.lan.limit='150'
uci set dhcp.lan.leasetime='12h'

uci set dhcp.@dnsmasq[0].rebind_protection='1'
uci set dhcp.@dnsmasq[0].rebind_localhost='1'
uci set dhcp.@dnsmasq[0].cachesize='1500'

uci set dropbear.main.Interface='lan'
uci set dropbear.main.PasswordAuth='on'
uci set dropbear.main.RootPasswordAuth='on'

# 6. HO TRO USB 4G DONGLE (RNDIS / CDC-ETHER / QMI) HOTPLUG
if [ "$HAS_USB" = "true" ]; then
    echo -e "${YELLOW}[5/7] Cau hinh ho tro USB 4G Dongle (Auto Hotplug / Metric 20)...${NC}"
    uci -q get network.wan_4g || uci set network.wan_4g=interface
    uci set network.wan_4g.device='usb0'
    uci set network.wan_4g.proto='dhcp'
    uci set network.wan_4g.metric='20'
    uci -q del_list firewall.@zone[1].network='wan_4g' 2>/dev/null || true
    uci add_list firewall.@zone[1].network='wan_4g'
fi

# 7. TOI UU HOA WI-FI 2.4GHz VA 5GHz THEO PLATFORM
echo -e "${YELLOW}[6/7] Tinh chinh thong so phat song Wi-Fi chong nhieu...${NC}"
r_5g="${RADIO_5G:-radio0}"
r_24g="${RADIO_24G:-radio1}"

if uci -q get wireless.${r_24g} >/dev/null 2>&1; then
    uci set wireless.${r_24g}.country='VN'
    uci set wireless.${r_24g}.channel='6'
    uci set wireless.${r_24g}.htmode='HT20'
    uci set wireless.${r_24g}.disabled='0'
fi

if uci -q get wireless.${r_5g} >/dev/null 2>&1; then
    uci set wireless.${r_5g}.country='VN'
    uci set wireless.${r_5g}.channel='44'
    if [ "$HAS_WIFI6" = "true" ]; then
        uci set wireless.${r_5g}.htmode='HE80'
    else
        uci set wireless.${r_5g}.htmode='VHT80'
    fi
    uci set wireless.${r_5g}.disabled='0'
fi

# 8. TINH CHINH LUCI OVERVIEW KHONG DEFER LOAD
INDEX_JS="/www/luci-static/resources/view/status/index.js"
if [ -f "$INDEX_JS" ]; then
    sed -i 's/deferFirstLoad:true/deferFirstLoad:false/g' "$INDEX_JS" 2>/dev/null || true
fi

# Commit toan bo thay doi
uci commit network 2>/dev/null || true
uci commit dhcp 2>/dev/null || true
uci commit firewall 2>/dev/null || true
uci commit wireless 2>/dev/null || true
uci commit system 2>/dev/null || true
uci commit dropbear 2>/dev/null || true

echo -e "${YELLOW}[7/7] Ap dung cau hinh va khoi dong lai dich vu mang...${NC}"
/etc/init.d/network restart 2>/dev/null || true
/etc/init.d/firewall restart 2>/dev/null || true
/etc/init.d/dnsmasq restart 2>/dev/null || true

echo -e "${CYAN}==================================================================${NC}"
echo -e "${GREEN}       🎉 TOI UU HOA HE THONG VCRT OS v2.0 THANH CONG!          ${NC}"
echo -e "${CYAN}==================================================================${NC}"
echo -e "   - IP Router: ${GREEN}http://${current_lan}${NC} hoac ${GREEN}http://vcrt.lan${NC}"
echo -e "   - Thuat toan TCP: ${CYAN}${cc_alg}${NC} | ZRAM Swap: ${CYAN}${zram_mb} MB${NC}"
echo -e "   - HW Flow Offloading: ${CYAN}${HAS_HWNAT}${NC}"

exit 0
