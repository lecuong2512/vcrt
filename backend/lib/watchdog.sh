#!/bin/sh
# VCRT OS v2.0 - Generic Watchdog & Auto-Rollback Engine
# Hỗ trợ bảo vệ tự động hoàn tác cho Wi-Fi, WAN, DNS khi cấu hình lỗi

watchdog_backup() {
    local svc="$1"
    [ -z "$svc" ] && return 1
    if [ -f "/etc/config/$svc" ]; then
        cp -f "/etc/config/$svc" "/tmp/vcrt_${svc}_wd.bak" 2>/dev/null
        return 0
    fi
    return 1
}

watchdog_arm() {
    local svc="$1"
    local timeout="${2:-60}"
    [ -z "$svc" ] && return 1

    case "$timeout" in ''|*[!0-9]*) timeout=60 ;; esac
    [ "$timeout" -lt 10 ] && timeout=10

    # Hủy watchdog cũ nếu có
    if [ -f "/tmp/vcrt_wd_${svc}.pid" ]; then
        local old_pid
        old_pid=$(cat "/tmp/vcrt_wd_${svc}.pid" 2>/dev/null)
        [ -n "$old_pid" ] && kill "$old_pid" 2>/dev/null
        rm -f "/tmp/vcrt_wd_${svc}.pid"
    fi

    touch "/tmp/vcrt_wd_${svc}.pending"

    # Chạy subshell ngầm đếm ngược
    (
        sleep "$timeout"
        if [ -f "/tmp/vcrt_wd_${svc}.pending" ]; then
            watchdog_rollback "$svc"
        fi
    ) >/dev/null 2>&1 &
    echo $! > "/tmp/vcrt_wd_${svc}.pid"
    return 0
}

watchdog_confirm() {
    local svc="$1"
    [ -z "$svc" ] && return 1
    rm -f "/tmp/vcrt_wd_${svc}.pending"
    if [ -f "/tmp/vcrt_wd_${svc}.pid" ]; then
        local pid
        pid=$(cat "/tmp/vcrt_wd_${svc}.pid" 2>/dev/null)
        [ -n "$pid" ] && kill "$pid" 2>/dev/null
        rm -f "/tmp/vcrt_wd_${svc}.pid"
    fi
    rm -f "/tmp/vcrt_${svc}_wd.bak"
    return 0
}

watchdog_rollback() {
    local svc="$1"
    [ -z "$svc" ] && return 1
    local bak="/tmp/vcrt_${svc}_wd.bak"
    if [ -f "$bak" ]; then
        cp -f "$bak" "/etc/config/$svc" 2>/dev/null
        case "$svc" in
            wireless)
                uci commit wireless 2>/dev/null
                wifi reload >/dev/null 2>&1 &
                ;;
            network)
                uci commit network 2>/dev/null
                /etc/init.d/network restart >/dev/null 2>&1 &
                ;;
            dhcp)
                uci commit dhcp 2>/dev/null
                /etc/init.d/dnsmasq restart >/dev/null 2>&1 &
                ;;
            *)
                uci commit "$svc" 2>/dev/null
                ;;
        esac
    fi
    rm -f "/tmp/vcrt_wd_${svc}.pending" "/tmp/vcrt_wd_${svc}.pid" "$bak"
    return 0
}

watchdog_is_pending() {
    local svc="$1"
    [ -f "/tmp/vcrt_wd_${svc}.pending" ] && return 0
    return 1
}
