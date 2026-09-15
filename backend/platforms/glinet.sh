#!/bin/sh
# VCRT OS v2.0 - Platform Adapter: GL.iNet Series Routers

export PLATFORM_ID="glinet"
export DEVICE_NAME_DEFAULT="GL.iNet Router"
export FLASH_CHIP_MB=128
export RAM_DEFAULT_TOTAL=128
export RAM_DEFAULT_AVAIL=60
export RADIO_5G="radio0"
export RADIO_24G="radio1"
export IFACE_5G="phy0-ap0"
export IFACE_24G="phy1-ap0"
export SWITCH_DEV="switch0"
export PORT_WAN=0
export PORT_LAN1=1
export PORT_LAN2=2
export HAS_PORT_LAN3=false
export PORT_LAN3=""
export THERMAL_PATH="/sys/class/thermal/thermal_zone0/temp"
export HAS_HWNAT=true
export HAS_SWITCH=true
export WAN_IFACE="eth0"
export LAN_IFACE="br-lan"
export HAS_USB=true
export HAS_GL_MODEM=true
export USB_DEV_PATH="/sys/bus/usb/devices"

# Kiem tra switch DSA / swconfig
if ! command -v swconfig >/dev/null 2>&1; then
    export HAS_SWITCH=false
    export SWITCH_DEV=""
fi

# Phat hien modem 4G dac thu GL.iNet
if [ -f /etc/init.d/gl_modem ] || [ -e /dev/cdc-wdm0 ] || [ -d /sys/class/net/wwan0 ]; then
    export GL_MODEM_ACTIVE=true
else
    export GL_MODEM_ACTIVE=false
fi
