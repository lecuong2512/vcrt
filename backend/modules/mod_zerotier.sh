#!/bin/sh
# VCRT OS v2.0 - ZeroTier Management Module
# Endpoints: zerotier_get, zerotier_service, zerotier_join, zerotier_leave, zerotier_info

_ensure_zt_tun() {
    if [ ! -c /dev/net/tun ]; then
        mkdir -p /dev/net 2>/dev/null || true
        mknod /dev/net/tun c 10 200 2>/dev/null || true
        chmod 600 /dev/net/tun 2>/dev/null || true
    fi
}

_patch_zt_init() {
    if [ -f /etc/init.d/zerotier ]; then
        if grep -q 'procd_open_instance$' /etc/init.d/zerotier 2>/dev/null; then
            sed -i 's/procd_open_instance$/procd_open_instance main/' /etc/init.d/zerotier 2>/dev/null || true
        fi
    fi
}

_clean_zt_earth() {
    if uci -q get zerotier.earth >/dev/null 2>&1; then
        local earth_id
        earth_id=$(uci -q get zerotier.earth.nwid 2>/dev/null)
        uci -q delete zerotier.earth 2>/dev/null || true
        uci -q commit zerotier 2>/dev/null || true
        [ -n "$earth_id" ] && rm -f "/var/lib/zerotier-one/networks.d/${earth_id}.*" 2>/dev/null || true
    fi
}

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
            version=$(echo "$info_out" | awk '{print $4}')
            status=$(echo "$info_out" | awk '{print $5}')
            [ -z "$status" ] && status="OFFLINE"
        fi

        local net_out
        net_out=$(zerotier-cli listnetworks 2>/dev/null)
        if [ -n "$net_out" ]; then
            networks_json=$(echo "$net_out" | awk '
            NR > 1 {
                if ($1 != "200" || $2 != "listnetworks") next;
                nwid = $3;
                mac_col = 0;
                for (i = 4; i <= NF; i++) {
                    if ($i ~ /^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$/) {
                        mac_col = i;
                        break;
                    }
                }
                name = "";
                if (mac_col > 4) {
                    for (i = 4; i < mac_col; i++) {
                        name = (name == "") ? $i : (name " " $i);
                    }
                }
                if (mac_col > 0) {
                    mac = $mac_col;
                    status = $(mac_col + 1);
                    type = $(mac_col + 2);
                    dev = $(mac_col + 3);
                    ip_raw = "";
                    for (i = mac_col + 4; i <= NF; i++) {
                        if ($i != "-") {
                            ip_raw = (ip_raw == "") ? $i : (ip_raw " " $i);
                        }
                    }
                } else {
                    name = $4; mac = $5; status = $6; type = $7; dev = $8;
                    ip_raw = ($9 == "-") ? "" : $9;
                }

                first_ip = ip_raw;
                sub(/ .*/, "", first_ip);
                ip_clean = first_ip;
                sub(/\/.*/, "", ip_clean);

                gsub(/\\/, "\\\\", name);
                gsub(/"/, "\\\"", name);

                if (!first) printf ",";
                first = 0;
                printf "{\"nwid\":\"%s\",\"name\":\"%s\",\"mac\":\"%s\",\"status\":\"%s\",\"type\":\"%s\",\"dev\":\"%s\",\"assigned_ip\":\"%s\",\"ip\":\"%s\"}", nwid, name, mac, status, type, dev, ip_raw, ip_clean;
            }
            BEGIN { first = 1; printf "["; }
            END { printf "]"; }
            ')
        fi
    else
        status="OFFLINE"
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

handle_zerotier_service() {
    local state="${PARAM_STATE}"
    [ -z "$state" ] && [ -n "$POST_BODY" ] && state=$(echo "$POST_BODY" | grep -o '"state"[ ]*:[ ]*"[^"]*"' | head -n1 | cut -d'"' -f4)
    [ -z "$state" ] && [ -n "$POST_BODY" ] && state=$(echo "$POST_BODY" | grep -o '"action"[ ]*:[ ]*"[^"]*"' | head -n1 | cut -d'"' -f4)
    [ -z "$state" ] && [ -n "$PARAM_BODY" ] && state=$(echo "$PARAM_BODY" | grep -o '"state"[ ]*:[ ]*"[^"]*"' | head -n1 | cut -d'"' -f4)
    [ -z "$state" ] && [ -n "$PARAM_KEY" ] && state="${PARAM_KEY}"
    [ -z "$state" ] && state="restart"

    case "$state" in
        stop)
            /etc/init.d/zerotier stop 2>/dev/null || true
            killall -9 zerotier-one 2>/dev/null || true
            if [ -f /etc/config/zerotier ]; then
                uci -q set zerotier.global.enabled='0' 2>/dev/null || uci -q set zerotier.@zerotier[0].enabled='0' 2>/dev/null || true
                uci -q commit zerotier 2>/dev/null || true
            fi
            json_ok '"action":"service_stopped"'
            ;;
        start|restart|*)
            _ensure_zt_tun
            _patch_zt_init
            _clean_zt_earth

            if [ ! -f /etc/config/zerotier ]; then
                touch /etc/config/zerotier
                uci -q set zerotier.global=zerotier
                uci -q set zerotier.global.enabled='1'
                uci -q commit zerotier 2>/dev/null || true
            else
                uci -q set zerotier.global.enabled='1' 2>/dev/null || uci -q set zerotier.@zerotier[0].enabled='1' 2>/dev/null || true
                uci -q commit zerotier 2>/dev/null || true
            fi

            if [ -f /etc/init.d/zerotier ]; then
                /etc/init.d/zerotier enable 2>/dev/null || true
                /etc/init.d/zerotier restart 2>/dev/null || true
            fi

            sleep 2
            if ! pgrep -f zerotier-one >/dev/null 2>&1 && ! pidof zerotier-one >/dev/null 2>&1; then
                zerotier-one -d 2>/dev/null &
                sleep 1
            fi
            json_ok '"action":"service_started"'
            ;;
    esac
}

handle_zerotier_join() {
    local nwid="${PARAM_KEY}"
    [ -z "$nwid" ] && [ -n "$POST_BODY" ] && nwid=$(echo "$POST_BODY" | grep -o '"nwid"[ ]*:[ ]*"[^"]*"' | head -n1 | cut -d'"' -f4)
    [ -z "$nwid" ] && [ -n "$POST_BODY" ] && nwid=$(echo "$POST_BODY" | grep -o '"network_id"[ ]*:[ ]*"[^"]*"' | head -n1 | cut -d'"' -f4)
    [ -z "$nwid" ] && nwid="${PARAM_PROFILE}"

    nwid=$(echo "$nwid" | tr -cd '0-9a-fA-F')

    if [ ${#nwid} -ne 16 ]; then
        json_error "Mã Network ID phải đúng 16 ký tự hex"
        return 1
    fi

    if ! command -v zerotier-cli >/dev/null 2>&1; then
        json_error "ZeroTier chưa được cài đặt trên router"
        return 1
    fi

    _ensure_zt_tun
    _patch_zt_init

    if ! pgrep -f zerotier-one >/dev/null 2>&1 && ! pidof zerotier-one >/dev/null 2>&1; then
        uci -q set zerotier.global.enabled='1' 2>/dev/null || true
        uci -q commit zerotier 2>/dev/null || true
        [ -f /etc/init.d/zerotier ] && /etc/init.d/zerotier restart 2>/dev/null || true
        sleep 2
        if ! pgrep -f zerotier-one >/dev/null 2>&1; then
            zerotier-one -d 2>/dev/null &
            sleep 2
        fi
    fi

    local res
    res=$(zerotier-cli join "$nwid" 2>&1)

    if echo "$res" | grep -Eq 'cannot connect|fatal|ERROR|Error'; then
        /etc/init.d/zerotier restart 2>/dev/null || zerotier-one -d 2>/dev/null &
        json_error "Không thể kết nối daemon ZeroTier: $res. Đang khởi động lại dịch vụ..."
        return 1
    fi

    if [ -f /etc/config/zerotier ]; then
        _clean_zt_earth
        local sec_exists=0
        for s in $(uci show zerotier 2>/dev/null | grep '\.id=' | cut -d'.' -f2 | cut -d'=' -f1); do
            local sid
            sid=$(uci -q get zerotier."$s".id)
            if [ "$sid" = "$nwid" ]; then
                sec_exists=1
                break
            fi
        done

        if [ "$sec_exists" -eq 0 ]; then
            uci -q set zerotier."net_${nwid}"=network
            uci -q set zerotier."net_${nwid}".id="$nwid"
            uci -q set zerotier."net_${nwid}".allow_managed='1'
            uci -q set zerotier."net_${nwid}".allow_global='0'
            uci -q set zerotier."net_${nwid}".allow_default='0'
            uci -q set zerotier."net_${nwid}".allow_dns='0'
            uci -q commit zerotier 2>/dev/null || true
        fi
    fi

    if [ -d /var/lib/zerotier-one/networks.d ]; then
        touch "/var/lib/zerotier-one/networks.d/${nwid}.conf" 2>/dev/null || true
        printf "allowManaged=1\nallowGlobal=0\nallowDefault=0\nallowDNS=0\n" > "/var/lib/zerotier-one/networks.d/${nwid}.local.conf" 2>/dev/null || true
    fi

    json_ok "\"nwid\":\"$(json_escape "$nwid")\",\"output\":\"$(json_escape "$res")\""
}

handle_zerotier_leave() {
    local nwid="${PARAM_KEY}"
    [ -z "$nwid" ] && [ -n "$POST_BODY" ] && nwid=$(echo "$POST_BODY" | grep -o '"nwid"[ ]*:[ ]*"[^"]*"' | head -n1 | cut -d'"' -f4)
    [ -z "$nwid" ] && [ -n "$POST_BODY" ] && nwid=$(echo "$POST_BODY" | grep -o '"network_id"[ ]*:[ ]*"[^"]*"' | head -n1 | cut -d'"' -f4)
    [ -z "$nwid" ] && nwid="${PARAM_PROFILE}"

    nwid=$(echo "$nwid" | tr -cd '0-9a-fA-F')

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

    if [ -f /etc/config/zerotier ]; then
        uci -q delete zerotier."net_${nwid}" 2>/dev/null || true
        for s in $(uci show zerotier 2>/dev/null | grep '\.id=' | cut -d'.' -f2 | cut -d'=' -f1); do
            local sid
            sid=$(uci -q get zerotier."$s".id)
            if [ "$sid" = "$nwid" ]; then
                uci -q delete zerotier."$s" 2>/dev/null || true
            fi
        done
        sed -i "/${nwid}/d" /etc/config/zerotier 2>/dev/null || true
        uci -q commit zerotier 2>/dev/null || true
    fi

    rm -f "/var/lib/zerotier-one/networks.d/${nwid}.conf" "/var/lib/zerotier-one/networks.d/${nwid}.local.conf" 2>/dev/null || true

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
