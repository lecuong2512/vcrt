#!/bin/sh
# VCRT OS v2.0 - Platform Adapter: Generic Auto-Detect Fallback
# Tu dong quet phan cung va thiet lap cac thong so tuong thich cao nhat

export PLATFORM_ID="generic"

# 1. Device Name Fallback
dev_name=$(cat /tmp/sysinfo/model 2>/dev/null)
[ -z "$dev_name" ] && dev_name=$(cat /tmp/sysinfo/board_name 2>/dev/null)
[ -z "$dev_name" ] && dev_name=$(awk -F: '/machine|Hardware|model name/ {gsub(/^ /,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null)
[ -z "$dev_name" ] && dev_name="OpenWrt Generic Router"
export DEVICE_NAME_DEFAULT="$dev_name"

# 2. Flash Chip Size (MB) - Tinh tu /proc/mtd hoac mtdinfo
flash_calc=16
if [ -f /proc/mtd ]; then
    total_mtd_bytes=$(awk '/mtd[0-9]+:/ {hex="0x"$2; sum += strtonum(hex)} END {print sum}' /proc/mtd 2>/dev/null)
    if [ -n "$total_mtd_bytes" ] && [ "$total_mtd_bytes" -gt 0 ] 2>/dev/null; then
        flash_calc=$((total_mtd_bytes / 1048576))
        [ "$flash_calc" -le 0 ] && flash_calc=16
    fi
fi
export FLASH_CHIP_MB="$flash_calc"

# 3. RAM Fallback (MiB) - Tu /proc/meminfo
ram_tot=$(awk '/MemTotal/{print int($2/1024); exit}' /proc/meminfo 2>/dev/null)
ram_avail=$(awk '/MemAvailable/{print int($2/1024); exit}' /proc/meminfo 2>/dev/null)
[ -z "$ram_tot" ] || [ "$ram_tot" -le 0 ] 2>/dev/null && ram_tot=128
[ -z "$ram_avail" ] || [ "$ram_avail" -le 0 ] 2>/dev/null && ram_avail=40
export RAM_DEFAULT_TOTAL="$ram_tot"
export RAM_DEFAULT_AVAIL="$ram_avail"

# 4. Radios 5GHz & 2.4GHz Auto-Detect tu UCI wireless
r5=""
r24=""
for r in $(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d. -f2 | cut -d= -f1); do
    b=$(uci -q get wireless.${r}.band)
    case "$b" in
        5g|5G|5GHz|a|ac|ax) [ -z "$r5" ] && r5="$r" ;;
        2g|2G|2.4GHz|b|g|n) [ -z "$r24" ] && r24="$r" ;;
    esac
done

# Neu UCI chua co band, thu nhan dien qua iwinfo / iw
if [ -z "$r5" ] || [ -z "$r24" ]; then
    if command -v iwinfo >/dev/null 2>&1; then
        for ifc in $(iwinfo 2>/dev/null | grep -E '^[a-zA-Z0-9_-]+' | awk '{print $1}'); do
            freq=$(iwinfo "$ifc" info 2>/dev/null | grep -i "channel" | awk '{print $4}')
            case "$freq" in
                5.*) [ -z "$r5" ] && r5="radio0" ;;
                2.*) [ -z "$r24" ] && r24="radio1" ;;
            esac
        done
    fi
fi

[ -z "$r5" ] && r5="radio0"
[ -z "$r24" ] && r24="radio1"
export RADIO_5G="$r5"
export RADIO_24G="$r24"

# 5. Interface AP 5GHz & 2.4GHz
if5=""
if24=""
for ifsec in $(uci show wireless 2>/dev/null | grep "\.mode='ap'" | cut -d. -f1,2); do
    dev=$(uci -q get ${ifsec}.device)
    ifname=$(uci -q get ${ifsec}.ifname)
    [ "$dev" = "$r5" ] && [ -z "$if5" ] && if5="${ifname:-phy0-ap0}"
    [ "$dev" = "$r24" ] && [ -z "$if24" ] && if24="${ifname:-phy1-ap0}"
done
[ -z "$if5" ] && if5="phy0-ap0"
[ -z "$if24" ] && if24="phy1-ap0"
export IFACE_5G="$if5"
export IFACE_24G="$if24"

# 6. Switch & Ports Detection
if command -v swconfig >/dev/null 2>&1; then
    sw_first=$(swconfig list 2>/dev/null | awk '{print $2; exit}')
    export SWITCH_DEV="${sw_first:-switch0}"
    export HAS_SWITCH=true
    export PORT_WAN=4
    export PORT_LAN1=0
    export PORT_LAN2=1
    export HAS_PORT_LAN3=false
    export PORT_LAN3=""
else
    export SWITCH_DEV=""
    export HAS_SWITCH=false
    export PORT_WAN=0
    export PORT_LAN1=1
    export PORT_LAN2=2
    export HAS_PORT_LAN3=true
    export PORT_LAN3=3
fi

# 7. Thermal Sensor Auto-Detect
t_path=""
for cand in /sys/class/thermal/thermal_zone0/temp /sys/devices/virtual/thermal/thermal_zone0/temp /sys/class/hwmon/hwmon0/temp1_input; do
    if [ -f "$cand" ]; then
        t_path="$cand"
        break
    fi
done
export THERMAL_PATH="${t_path:-/sys/class/thermal/thermal_zone0/temp}"

# 8. Hardware NAT Flow Offloading
if [ -d /sys/module/mtk_ppe ] || [ -d /sys/module/xt_FLOWOFFLOAD ] || grep -q -i "mediatek" /proc/cpuinfo 2>/dev/null; then
    export HAS_HWNAT=true
else
    export HAS_HWNAT=false
fi

# 9. WAN & LAN Interfaces
w_if=$(uci -q get network.wan.device)
[ -z "$w_if" ] && w_if=$(uci -q get network.wan.ifname)
[ -z "$w_if" ] && w_if="eth0.2"

l_if=$(uci -q get network.lan.device)
[ -z "$l_if" ] && l_if=$(uci -q get network.lan.ifname)
[ -z "$l_if" ] && l_if="br-lan"

export WAN_IFACE="$w_if"
export LAN_IFACE="$l_if"
export HAS_USB=true
export USB_DEV_PATH="/sys/bus/usb/devices"
