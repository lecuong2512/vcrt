#!/bin/sh
# VCRT OS v2.0 - NextDNS Management Module
# Endpoints: nextdns_sync_ip, nextdns_get, nextdns_apikey_set, nextdns_apikey_del, nextdns_proxy, nextdns_set, nextdns_disable

handle_nextdns_sync_ip() {
    local prof tok ak linked_res="Chưa liên kết"
    prof=$(cat "$NEXTDNS_CONF_FILE" 2>/dev/null || echo "")
    tok=$(cat "$NEXTDNS_TOKEN_FILE" 2>/dev/null || echo "")

    if [ -z "$tok" ] && [ -n "$prof" ]; then
        ak=$(cat "$NEXTDNS_APIKEY" 2>/dev/null | tr -d ' \r\n')
        if [ -n "$ak" ]; then
            tok=$(curl -s -k -m 5 -H "X-Api-Key: $ak" "https://api.nextdns.io/profiles/$prof" 2>/dev/null | grep -o '"updateToken":"[^"]*"' | cut -d'"' -f4)
            [ -n "$tok" ] && echo "$tok" > "$NEXTDNS_TOKEN_FILE"
        fi
    fi

    if [ -n "$prof" ]; then
        if [ -n "$tok" ]; then
            linked_res=$(curl -s -m 5 "https://link-ip.nextdns.io/$prof/$tok" 2>/dev/null || echo "")
        fi
        if [ -z "$linked_res" ] || echo "$linked_res" | grep -q "error"; then
            local alt_res
            alt_res=$(curl -s -m 5 "https://link-ip.nextdns.io/$prof" 2>/dev/null || echo "")
            [ -n "$alt_res" ] && ! echo "$alt_res" | grep -q "error" && linked_res="$alt_res"
        fi
        [ -n "$linked_res" ] && echo "$linked_res" > "$NEXTDNS_LINKED_IP_TMP"
    fi

    json_ok "\"linked_ip\":\"$(json_escape "$linked_res")\""
}

handle_nextdns_get() {
    local cur_prof="" is_active="false"
    if [ -f "$NEXTDNS_CONF_FILE" ] && [ -s "$NEXTDNS_CONF_FILE" ]; then
        cur_prof=$(cat "$NEXTDNS_CONF_FILE" 2>/dev/null | tr -d ' \r\n')
        if [ -n "$cur_prof" ]; then
            if [ -f /etc/dnsmasq.d/nextdns.conf ] || grep -q "NEXTDNS_START" /etc/dnsmasq.conf 2>/dev/null; then
                is_active="true"
            fi
        fi
    fi

    local has_api_key="false" masked_key="" ak
    if [ -f "$NEXTDNS_APIKEY" ] && [ -s "$NEXTDNS_APIKEY" ]; then
        chmod 600 "$NEXTDNS_APIKEY" 2>/dev/null || true
        ak=$(cat "$NEXTDNS_APIKEY" | tr -d ' \r\n')
        if [ -n "$ak" ]; then
            has_api_key="true"
            local len=${#ak}
            if [ "$len" -gt 8 ]; then
                masked_key="$(echo "$ak" | cut -c1-4)****$(echo "$ak" | cut -c$((len-3))-$len)"
            else
                masked_key="****"
            fi
        fi
    fi

    local linked_ip
    linked_ip=$(cat "$NEXTDNS_LINKED_IP_TMP" 2>/dev/null || echo "")

    cat << EOF
{
  "active": ${is_active},
  "profile_id": "$(json_escape "$cur_prof")",
  "installed": true,
  "routed": ${is_active},
  "has_api_key": ${has_api_key},
  "has_apikey": ${has_api_key},
  "masked_api_key": "$(json_escape "$masked_key")",
  "apikey_masked": "$(json_escape "$masked_key")",
  "linked_ip": "$(json_escape "$linked_ip")"
}
EOF
}

handle_nextdns_apikey_set() {
    local ak="${PARAM_APIKEY}"
    if [ -z "$ak" ] && [ -n "$POST_BODY" ]; then
        ak=$(echo "$POST_BODY" | grep -o '"api_key":"[^"]*"' | cut -d'"' -f4)
        [ -z "$ak" ] && ak=$(echo "$POST_BODY" | grep -o '"apikey":"[^"]*"' | cut -d'"' -f4)
    fi
    ak=$(echo "$ak" | tr -d ' \r\n"')

    if [ -n "$ak" ]; then
        echo "$ak" > "$NEXTDNS_APIKEY"
        chmod 600 "$NEXTDNS_APIKEY" 2>/dev/null || true

        local cur_prof
        cur_prof=$(cat "$NEXTDNS_CONF_FILE" 2>/dev/null | tr -d ' \r\n')
        if [ -n "$cur_prof" ]; then
            PARAM_PROFILE="$cur_prof"
            handle_nextdns_set >/dev/null 2>&1 || true
        fi

        json_ok '"has_api_key":true,"has_apikey":true'
    else
        json_error "missing_api_key"
    fi
}

handle_nextdns_apikey_del() {
    rm -f "$NEXTDNS_APIKEY"
    json_ok '"has_api_key":false,"has_apikey":false'
}

handle_nextdns_proxy() {
    local ak
    ak=$(cat "$NEXTDNS_APIKEY" 2>/dev/null | tr -d ' \r\n')
    [ -z "$ak" ] && ak="$PARAM_APIKEY"
    if [ -z "$ak" ]; then
        json_error "Vui lòng nhập NextDNS API Key để truy cập tính năng này"
        return 1
    fi

    local ep
    ep=$(echo "$PARAM_ENDPOINT" | sed -e 's/%253F/?/g' -e 's/%2526/\&/g' -e 's/%253D/=/g' -e 's/%252F/\//g' -e 's/%2F/\//g' -e 's/%3F/?/g' -e 's/%3D/=/g' -e 's/%26/\&/g' -e 's/%20/ /g' -e 's/%3A/:/g')
    [ -z "$ep" ] && ep="profiles/$PARAM_PROFILE"

    local meth="$PARAM_METHOD"
    [ -z "$meth" ] && meth="GET"
    meth=$(echo "$meth" | tr 'a-z' 'A-Z')

    local body_to_send=""
    if [ -n "$POST_BODY" ]; then
        body_to_send="$POST_BODY"
    elif [ -n "$PARAM_BODY" ]; then
        body_to_send="$PARAM_BODY"
    fi

    if [ "$meth" = "GET" ]; then
        curl -s -k -m 8 \
            -H "X-Api-Key: $ak" \
            -H "Accept: application/json" \
            "https://api.nextdns.io/$ep" 2>/dev/null || json_error "curl_failed"
    elif [ "$meth" = "DELETE" ]; then
        curl -s -k -m 8 -X DELETE \
            -H "X-Api-Key: $ak" \
            -H "Accept: application/json" \
            "https://api.nextdns.io/$ep" 2>/dev/null || json_error "curl_failed"
        killall -HUP dnsmasq 2>/dev/null &
    else
        echo "$body_to_send" > /tmp/ndns_body.json
        curl -s -k -m 8 -X "$meth" \
            -H "X-Api-Key: $ak" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -d @/tmp/ndns_body.json \
            "https://api.nextdns.io/$ep" 2>/dev/null || json_error "curl_failed"
        rm -f /tmp/ndns_body.json
        killall -HUP dnsmasq 2>/dev/null &
    fi
}

handle_nextdns_set() {
    [ -z "$PARAM_PROFILE" ] && { json_error "missing_profile_id"; return 1; }

    PARAM_PROFILE=$(echo "$PARAM_PROFILE" | tr -d ' \r\n' | tr 'A-Z' 'a-z')
    echo "$PARAM_PROFILE" > "$NEXTDNS_CONF_FILE"

    local ak tok="" lip="" prof_json=""
    local servers_ipv4="" servers_ipv6=""
    ak=$(cat "$NEXTDNS_APIKEY" 2>/dev/null | tr -d ' \r\n')

    # 1. Nếu có API Key, truy vấn thông tin Profile từ NextDNS API
    if [ -n "$ak" ]; then
        prof_json=$(curl -s -k -m 8 -H "X-Api-Key: $ak" "https://api.nextdns.io/profiles/$PARAM_PROFILE" 2>/dev/null)
        if [ -n "$prof_json" ]; then
            tok=$(echo "$prof_json" | grep -o '"updateToken":"[^"]*"' | head -n1 | cut -d'"' -f4)
            # Lấy IP IPv4 từ linkedIp.servers hoặc endpoints.ipv4
            servers_ipv4=$(echo "$prof_json" | grep -o '"servers":\[[^]]*\]' | head -n1 | sed -e 's/.*\[//; s/\].*//; s/"//g; s/,/ /g')
            if [ -z "$servers_ipv4" ]; then
                servers_ipv4=$(echo "$prof_json" | grep -o '"ipv4":\[[^]]*\]' | head -n1 | sed -e 's/.*\[//; s/\].*//; s/"//g; s/,/ /g')
            fi
            # Lấy IPv6 từ setup.ipv6 hoặc endpoints.ipv6
            servers_ipv6=$(echo "$prof_json" | grep -o '"ipv6":\[[^]]*\]' | head -n1 | sed -e 's/.*\[//; s/\].*//; s/"//g; s/,/ /g')
        fi
    fi

    [ -z "$tok" ] && tok=$(cat "$NEXTDNS_TOKEN_FILE" 2>/dev/null | tr -d ' \r\n')
    [ -n "$tok" ] && echo "$tok" > "$NEXTDNS_TOKEN_FILE"

    # 2. Tính toán địa chỉ IPv6 chuẩn theo Profile ID nếu API chưa cấp
    if [ -z "$servers_ipv6" ]; then
        local prof_len=${#PARAM_PROFILE}
        if [ "$prof_len" -eq 6 ]; then
            local p1=$(echo "$PARAM_PROFILE" | cut -c1-2)
            local p2=$(echo "$PARAM_PROFILE" | cut -c3-6)
            servers_ipv6="2a07:a8c0::${p1}:${p2} 2a07:a8c1::${p1}:${p2}"
        elif [ "$prof_len" -gt 2 ]; then
            local p1=$(echo "$PARAM_PROFILE" | cut -c1-2)
            local p2=$(echo "$PARAM_PROFILE" | cut -c3-)
            servers_ipv6="2a07:a8c0::${p1}:${p2} 2a07:a8c1::${p1}:${p2}"
        fi
    fi

    # 3. Fallback IPv4 nếu chưa có từ API
    if [ -z "$servers_ipv4" ]; then
        servers_ipv4="45.90.28.0 45.90.30.0"
    fi

    # 4. Gọi đồng bộ Link IP
    if [ -n "$tok" ]; then
        lip=$(curl -s -m 5 "https://link-ip.nextdns.io/$PARAM_PROFILE/$tok" 2>/dev/null)
    fi
    local lip_alt
    lip_alt=$(curl -s -m 5 "https://link-ip.nextdns.io/$PARAM_PROFILE" 2>/dev/null)
    [ -z "$lip" ] && lip="$lip_alt"
    [ -n "$lip" ] && echo "$lip" > "$NEXTDNS_LINKED_IP_TMP"

    # 5. Backup cấu hình dnsmasq trước khi áp dụng
    local bak_dnsmasq_conf="/tmp/vcrt_dnsmasq_conf.bak"
    local bak_uci_dhcp="/tmp/vcrt_uci_dhcp.bak"
    local bak_nextdns_d="/tmp/vcrt_nextdns_d.bak"

    cp -f /etc/dnsmasq.conf "$bak_dnsmasq_conf" 2>/dev/null || true
    cp -f /etc/config/dhcp "$bak_uci_dhcp" 2>/dev/null || true
    [ -f /etc/dnsmasq.d/nextdns.conf ] && cp -f /etc/dnsmasq.d/nextdns.conf "$bak_nextdns_d" 2>/dev/null

    # Cấu hình dnsmasq qua UCI
    uci -q delete dhcp.@dnsmasq[0].server
    uci set dhcp.@dnsmasq[0].noresolv='1'
    uci set dhcp.@dnsmasq[0].strictorder='1'
    uci set dhcp.@dnsmasq[0].boguspriv='1'
    for srv in $servers_ipv4 $servers_ipv6; do
        [ -n "$srv" ] && uci add_list dhcp.@dnsmasq[0].server="$srv"
    done
    uci set dhcp.@dnsmasq[0].confdir='/etc/dnsmasq.d'
    uci commit dhcp

    # Ghi file cấu hình chuẩn /etc/dnsmasq.d/nextdns.conf
    mkdir -p /etc/dnsmasq.d 2>/dev/null
    {
        echo "no-resolv"
        echo "bogus-priv"
        echo "strict-order"
        for srv in $servers_ipv4 $servers_ipv6; do
            [ -n "$srv" ] && echo "server=$srv"
        done
    } > /etc/dnsmasq.d/nextdns.conf

    # Dọn dẹp block cũ và chèn block cấu hình NextDNS vào /etc/dnsmasq.conf
    sed -i '/# NEXTDNS_START/,/# NEXTDNS_END/d' /etc/dnsmasq.conf 2>/dev/null || true
    {
        echo "# NEXTDNS_START"
        echo "no-resolv"
        echo "bogus-priv"
        echo "strict-order"
        for srv in $servers_ipv4 $servers_ipv6; do
            [ -n "$srv" ] && echo "server=$srv"
        done
        echo "# NEXTDNS_END"
    } >> /etc/dnsmasq.conf

    # Kiểm tra an toàn cú pháp dnsmasq trước khi restart
    if ! dnsmasq --test 2>/dev/null; then
        [ -f "$bak_dnsmasq_conf" ] && cp -f "$bak_dnsmasq_conf" /etc/dnsmasq.conf 2>/dev/null
        [ -f "$bak_uci_dhcp" ] && cp -f "$bak_uci_dhcp" /etc/config/dhcp 2>/dev/null
        if [ -f "$bak_nextdns_d" ]; then
            cp -f "$bak_nextdns_d" /etc/dnsmasq.d/nextdns.conf 2>/dev/null
        else
            rm -f /etc/dnsmasq.d/nextdns.conf 2>/dev/null
        fi
        rm -f "$bak_dnsmasq_conf" "$bak_uci_dhcp" "$bak_nextdns_d"
        /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
        json_error "Cấu hình NextDNS không tương thích với dnsmasq! Đã tự động khôi phục cấu hình an toàn."
        return 1
    fi

    rm -f "$bak_dnsmasq_conf" "$bak_uci_dhcp" "$bak_nextdns_d"

    killall nextdns 2>/dev/null || true
    killall https-dns-proxy 2>/dev/null || true
    /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true

    json_ok "\"profile_id\":\"$(json_escape "$PARAM_PROFILE")\",\"mode\":\"dnsmasq_native\",\"linked_ip\":\"$(json_escape "$lip")\",\"ipv4\":\"$(json_escape "$servers_ipv4")\",\"ipv6\":\"$(json_escape "$servers_ipv6")\""
}

handle_nextdns_disable() {
    rm -f "$NEXTDNS_CONF_FILE" "$NEXTDNS_TOKEN_FILE" "$NEXTDNS_LINKED_IP_TMP" /etc/dnsmasq.d/nextdns.conf 2>/dev/null
    sed -i '/# NEXTDNS_START/,/# NEXTDNS_END/d' /etc/dnsmasq.conf 2>/dev/null || true
    uci set dhcp.@dnsmasq[0].noresolv='0'
    uci -q delete dhcp.@dnsmasq[0].server
    uci commit dhcp
    /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true

    json_ok '"action":"nextdns_disabled"'
}
