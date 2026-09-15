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

    if [ -n "$prof" ] && [ -n "$tok" ]; then
        linked_res=$(curl -s -m 5 "https://link-ip.nextdns.io/$prof/$tok" 2>/dev/null || echo "")
        echo "$linked_res" > "$NEXTDNS_LINKED_IP_TMP"
    fi

    json_ok "\"linked_ip\":\"$(json_escape "$linked_res")\""
}

handle_nextdns_get() {
    local cur_prof="" is_active="false"
    if [ -f /etc/dnsmasq.conf ] && grep -q "add-cpe-id=" /etc/dnsmasq.conf 2>/dev/null; then
        cur_prof=$(grep "add-cpe-id=" /etc/dnsmasq.conf | head -n1 | cut -d= -f2 | tr -d ' \r\n')
        [ -n "$cur_prof" ] && is_active="true"
    fi
    [ -z "$cur_prof" ] && cur_prof=$(cat "$NEXTDNS_CONF_FILE" 2>/dev/null || echo "")

    local has_api_key="false" masked_key="" ak
    if [ -f "$NEXTDNS_APIKEY" ] && [ -s "$NEXTDNS_APIKEY" ]; then
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
  "masked_api_key": "$(json_escape "$masked_key")",
  "linked_ip": "$(json_escape "$linked_ip")"
}
EOF
}

handle_nextdns_apikey_set() {
    local ak="${PARAM_APIKEY}"
    [ -z "$ak" ] && ak="${POST_BODY}"
    ak=$(echo "$ak" | tr -d ' \r\n"')
    if [ -n "$ak" ]; then
        echo "$ak" > "$NEXTDNS_APIKEY"
        chmod 600 "$NEXTDNS_APIKEY" 2>/dev/null || true
        json_ok '"has_api_key":true'
    else
        json_error "missing_api_key"
    fi
}

handle_nextdns_apikey_del() {
    rm -f "$NEXTDNS_APIKEY"
    json_ok '"has_api_key":false'
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

    echo "$PARAM_PROFILE" > "$NEXTDNS_CONF_FILE"

    # Lấy updateToken và cập nhật linked IP
    local ak
    ak=$(cat "$NEXTDNS_APIKEY" 2>/dev/null | tr -d ' \r\n')
    if [ -n "$ak" ]; then
        local tok
        tok=$(curl -s -k -m 6 -H "X-Api-Key: $ak" "https://api.nextdns.io/profiles/$PARAM_PROFILE" 2>/dev/null | grep -o '"updateToken":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$tok" ]; then
            echo "$tok" > "$NEXTDNS_TOKEN_FILE"
            local lip
            lip=$(curl -s -m 5 "https://link-ip.nextdns.io/$PARAM_PROFILE/$tok" 2>/dev/null)
            [ -n "$lip" ] && echo "$lip" > "$NEXTDNS_LINKED_IP_TMP"
        fi
    fi

    # Cấu hình dnsmasq native
    uci -q delete dhcp.@dnsmasq[0].server
    uci set dhcp.@dnsmasq[0].noresolv='1'
    uci set dhcp.@dnsmasq[0].strictorder='1'
    uci set dhcp.@dnsmasq[0].boguspriv='1'
    uci add_list dhcp.@dnsmasq[0].server='45.90.28.0'
    uci add_list dhcp.@dnsmasq[0].server='45.90.30.0'
    uci set dhcp.@dnsmasq[0].confdir='/etc/dnsmasq.d'
    uci commit dhcp

    mkdir -p /etc/dnsmasq.d 2>/dev/null
    cat << EOF > /etc/dnsmasq.d/nextdns.conf
no-resolv
bogus-priv
strict-order
server=45.90.28.0
server=45.90.30.0
server=2a07:a8c0::
server=2a07:a8c1::
add-cpe-id=$PARAM_PROFILE
EOF

    sed -i '/# NEXTDNS_START/,/# NEXTDNS_END/d' /etc/dnsmasq.conf 2>/dev/null || true
    cat << EOF >> /etc/dnsmasq.conf
# NEXTDNS_START
no-resolv
bogus-priv
strict-order
server=45.90.28.0
server=45.90.30.0
server=2a07:a8c0::
server=2a07:a8c1::
add-cpe-id=$PARAM_PROFILE
# NEXTDNS_END
EOF

    killall nextdns 2>/dev/null || true
    killall https-dns-proxy 2>/dev/null || true
    /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true

    json_ok "\"profile_id\":\"$(json_escape "$PARAM_PROFILE")\",\"mode\":\"dnsmasq_native\""
}

handle_nextdns_disable() {
    rm -f "$NEXTDNS_CONF_FILE" /etc/dnsmasq.d/nextdns.conf
    sed -i '/# NEXTDNS_START/,/# NEXTDNS_END/d' /etc/dnsmasq.conf 2>/dev/null || true
    uci set dhcp.@dnsmasq[0].noresolv='0'
    uci -q delete dhcp.@dnsmasq[0].server
    uci commit dhcp
    /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true

    json_ok '"action":"nextdns_disabled"'
}
