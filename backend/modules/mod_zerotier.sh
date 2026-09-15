#!/bin/sh
# VCRT OS v2.0 - ZeroTier Management Module
# Endpoints: zerotier_get, zerotier_join, zerotier_leave, zerotier_info

handle_zerotier_get() {
    local installed="false" running="false" node_id="" status="OFFLINE" version="" networks_json="[]"

    if command -v zerotier-cli >/dev/null 2>&1; then
        installed="true"
    fi

    if pgrep -f zerotier-one >/dev/null 2>&1 || pidof zerotier-one >/dev/null 2>&1; then
        running="true"
    fi

    if [ "$installed" = "true" ] && [ "$running" = "true" ]; then
        local info_out
        info_out=$(zerotier-cli status 2>/dev/null || zerotier-cli info 2>/dev/null)
        if [ -n "$info_out" ]; then
            node_id=$(echo "$info_out" | awk '{print $3}')
            version=$(echo "$info_out" | awk '{print $2}')
            status=$(echo "$info_out" | awk '{print $5}')
            [ -z "$status" ] && status="ONLINE"
        fi

        local net_out
        net_out=$(zerotier-cli listnetworks 2>/dev/null)
        if [ -n "$net_out" ]; then
            networks_json=$(echo "$net_out" | awk '
            NR > 1 {
                nwid = $3;
                name = $4;
                mac = $5;
                status = $6;
                type = $7;
                dev = $8;
                ip = $9;
                if (!first) printf ",";
                first = 0;
                printf "{\"nwid\":\"%s\",\"name\":\"%s\",\"mac\":\"%s\",\"status\":\"%s\",\"type\":\"%s\",\"dev\":\"%s\",\"assigned_ip\":\"%s\"}", nwid, name, mac, status, type, dev, ip;
            }
            BEGIN { first = 1; printf "["; }
            END { printf "]"; }
            ')
        fi
    fi

    cat << EOF
{
  "status": "ok",
  "installed": ${installed},
  "running": ${running},
  "node_id": "$(json_escape "$node_id")",
  "version": "$(json_escape "$version")",
  "online_status": "$(json_escape "$status")",
  "networks": ${networks_json}
}
EOF
}

handle_zerotier_join() {
    local nwid="${PARAM_KEY}"
    [ -z "$nwid" ] && [ -n "$POST_BODY" ] && nwid=$(echo "$POST_BODY" | grep -o '"nwid"[ ]*:[ ]*"[^"]*"' | head -n1 | cut -d'"' -f4)
    [ -z "$nwid" ] && [ -n "$POST_BODY" ] && nwid=$(echo "$POST_BODY" | grep -o '"network_id"[ ]*:[ ]*"[^"]*"' | head -n1 | cut -d'"' -f4)
    [ -z "$nwid" ] && nwid="${PARAM_PROFILE}"

    if [ -z "$nwid" ]; then
        json_error "Thiếu mã Network ID (16 ký tự)"
        return 1
    fi

    if ! command -v zerotier-cli >/dev/null 2>&1; then
        json_error "ZeroTier chưa được cài đặt trên router"
        return 1
    fi

    local res
    res=$(zerotier-cli join "$nwid" 2>&1)

    # Lưu vào UCI config nếu có package zerotier
    if uci -q get zerotier >/dev/null; then
        uci add_list zerotier.@zerotier[0].join="$nwid" 2>/dev/null || true
        uci commit zerotier 2>/dev/null || true
    fi

    json_ok "\"nwid\":\"$(json_escape "$nwid")\",\"output\":\"$(json_escape "$res")\""
}

handle_zerotier_leave() {
    local nwid="${PARAM_KEY}"
    [ -z "$nwid" ] && [ -n "$POST_BODY" ] && nwid=$(echo "$POST_BODY" | grep -o '"nwid"[ ]*:[ ]*"[^"]*"' | head -n1 | cut -d'"' -f4)
    [ -z "$nwid" ] && [ -n "$POST_BODY" ] && nwid=$(echo "$POST_BODY" | grep -o '"network_id"[ ]*:[ ]*"[^"]*"' | head -n1 | cut -d'"' -f4)
    [ -z "$nwid" ] && nwid="${PARAM_PROFILE}"

    if [ -z "$nwid" ]; then
        json_error "Thiếu mã Network ID"
        return 1
    fi

    if ! command -v zerotier-cli >/dev/null 2>&1; then
        json_error "ZeroTier chưa được cài đặt trên router"
        return 1
    fi

    local res
    res=$(zerotier-cli leave "$nwid" 2>&1)

    if uci -q get zerotier >/dev/null; then
        uci del_list zerotier.@zerotier[0].join="$nwid" 2>/dev/null || true
        uci commit zerotier 2>/dev/null || true
    fi

    json_ok "\"nwid\":\"$(json_escape "$nwid")\",\"output\":\"$(json_escape "$res")\""
}

handle_zerotier_info() {
    if ! command -v zerotier-cli >/dev/null 2>&1; then
        json_error "ZeroTier chưa được cài đặt trên router"
        return 1
    fi

    local peers_json="[]"
    local peers_out
    peers_out=$(zerotier-cli listpeers 2>/dev/null)
    if [ -n "$peers_out" ]; then
        peers_json=$(echo "$peers_out" | awk '
        NR > 1 {
            zt_addr = $3;
            path = $4;
            lat = $5;
            ver = $6;
            role = $7;
            if (!first) printf ",";
            first = 0;
            printf "{\"address\":\"%s\",\"path\":\"%s\",\"latency\":\"%s\",\"version\":\"%s\",\"role\":\"%s\"}", zt_addr, path, lat, ver, role;
        }
        BEGIN { first = 1; printf "["; }
        END { printf "]"; }
        ')
    fi

    local status_raw
    status_raw=$(zerotier-cli status 2>/dev/null || echo "")

    cat << EOF
{
  "status": "ok",
  "status_raw": "$(json_escape "$status_raw")",
  "peers": ${peers_json}
}
EOF
}
