#!/bin/sh
# VCRT OS v2.0 - Platform Adapter: MediaTek Filogic (MT7981 / MT7986 / Wi-Fi 6)

export PLATFORM_ID="mediatek_filogic"
export DEVICE_NAME_DEFAULT="MediaTek Filogic Router (Wi-Fi 6)"
export FLASH_CHIP_MB=128
export RAM_DEFAULT_TOTAL=256
export RAM_DEFAULT_AVAIL=160

# Filogic 820/830: radio0 = 2.4GHz, radio1 = 5GHz (dao nguoc so voi Xiaomi Mini)
export RADIO_5G="radio1"
export RADIO_24G="radio0"
export IFACE_5G="phy1-ap0"
export IFACE_24G="phy0-ap0"

# OpenWrt DSA architecture (khong dung swconfig cu)
export SWITCH_DEV=""
export HAS_SWITCH=false
export PORT_WAN=0
export PORT_LAN1=1
export PORT_LAN2=2
export HAS_PORT_LAN3=true
export PORT_LAN3=3

export THERMAL_PATH="/sys/class/thermal/thermal_zone0/temp"
export HAS_HWNAT=true
export WAN_IFACE="wan"
export LAN_IFACE="br-lan"
export HAS_USB=true
export USB_DEV_PATH="/sys/bus/usb/devices"
export HAS_WIFI6=true
