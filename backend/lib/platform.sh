#!/bin/sh
# VCRT OS v2.0 - Platform Auto-Detection Layer
# Ho tro phat hien da thiet bi router OpenWrt (BusyBox POSIX standard)

detect_platform() {
    local board=""
    local model=""
    local cpu=""

    [ -f /tmp/sysinfo/board_name ] && board=$(cat /tmp/sysinfo/board_name 2>/dev/null)
    [ -f /tmp/sysinfo/model ] && model=$(cat /tmp/sysinfo/model 2>/dev/null)
    [ -f /proc/cpuinfo ] && cpu=$(cat /proc/cpuinfo 2>/dev/null)

    # Xac dinh thu muc chua platform adapters
    if [ -z "$PLATFORM_DIR" ]; then
        if [ -d "/www/cgi-bin/platforms" ]; then
            PLATFORM_DIR="/www/cgi-bin/platforms"
        elif [ -d "$(dirname "$0")/../platforms" ]; then
            PLATFORM_DIR="$(dirname "$0")/../platforms"
        elif [ -d "$(dirname "$0")/platforms" ]; then
            PLATFORM_DIR="$(dirname "$0")/platforms"
        elif [ -d "./backend/platforms" ]; then
            PLATFORM_DIR="./backend/platforms"
        else
            PLATFORM_DIR="/www/cgi-bin/platforms"
        fi
    fi

    local target_id="${board} ${model} ${cpu}"

    case "$target_id" in
        *"xiaomi,miwifi-mini"*|*"MiWiFi-Mini"*|*"MiWiFi Mini"*|*"miwifi-mini"*)
            if [ -f "$PLATFORM_DIR/xiaomi_mini.sh" ]; then
                . "$PLATFORM_DIR/xiaomi_mini.sh"
            else
                . "$PLATFORM_DIR/generic.sh"
            fi
            ;;
        *"xiaomi,mi-router-4a"*|*"xiaomi,mi-router-4a-gigabit"*|*"Mi Router 4A"*|*"MIR4A"*)
            if [ -f "$PLATFORM_DIR/xiaomi_4a.sh" ]; then
                . "$PLATFORM_DIR/xiaomi_4a.sh"
            else
                . "$PLATFORM_DIR/generic.sh"
            fi
            ;;
        *"glinet"*|*"gl-"*|*"GL.iNet"*|*"GL-"*)
            if [ -f "$PLATFORM_DIR/glinet.sh" ]; then
                . "$PLATFORM_DIR/glinet.sh"
            else
                . "$PLATFORM_DIR/generic.sh"
            fi
            ;;
        *"filogic"*|*"mt798"*|*"MT798"*|*"360 T7"*|*"NX30 Pro"*)
            if [ -f "$PLATFORM_DIR/mediatek_filogic.sh" ]; then
                . "$PLATFORM_DIR/mediatek_filogic.sh"
            else
                . "$PLATFORM_DIR/generic.sh"
            fi
            ;;
        *)
            if [ -f "$PLATFORM_DIR/generic.sh" ]; then
                . "$PLATFORM_DIR/generic.sh"
            fi
            ;;
    esac
}

detect_platform
