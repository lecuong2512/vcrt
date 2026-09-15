#!/bin/sh
# VCRT OS v2.0 - Core Backend CGI Dispatcher
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# 1. Xử lý preflight CORS cho HTTP OPTIONS
if [ "$REQUEST_METHOD" = "OPTIONS" ]; then
    printf "Access-Control-Allow-Origin: *\r\n"
    printf "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
    printf "Access-Control-Allow-Headers: Content-Type, Authorization\r\n\r\n"
    exit 0
fi

# 2. Parse Query String
ACTION="" MAC="" TYPE="" PARAM_PROFILE="" PARAM_ENDPOINT="" PARAM_METHOD=""
PARAM_APIKEY="" PARAM_BODY="" PARAM_SSID="" PARAM_SSID5="" PARAM_PASS5=""
PARAM_CH5="" PARAM_POWER5="" PARAM_POWER24="" PARAM_SSID24="" PARAM_PASS24=""
PARAM_CH24="" PARAM_BAND="" PARAM_BSSID="" PARAM_KEY="" PARAM_MINUTES=""
PARAM_NAME="" PARAM_IP="" PARAM_USER="" PARAM_PASS="" PARAM_NEW_PASS=""
PARAM_TOKEN="" PARAM_BOT_TOKEN="" PARAM_CHAT_ID="" PARAM_NOTIF_WIFI=""
PARAM_NOTIF_EXPIRE="" PARAM_NOTIF_DAILY="" PARAM_DAILY_HOUR=""
PARAM_BOT_ENABLED="" PARAM_AUTO_UPDATE="" PARAM_ENABLED=""

OLD_IFS="$IFS"
IFS='&'
for item in $QUERY_STRING; do
    case "$item" in
        action=*) ACTION="${item#action=}" ;;
        mac=*) MAC="${item#mac=}" ;;
        type=*) TYPE="${item#type=}" ;;
        profile_id=*|profile=*) PARAM_PROFILE="${item#*=}" ;;
        endpoint=*) PARAM_ENDPOINT="${item#endpoint=}" ;;
        method=*) PARAM_METHOD="${item#method=}" ;;
        api_key=*|apikey=*) PARAM_APIKEY="${item#*=}" ;;
        body=*) PARAM_BODY="${item#body=}" ;;
        ssid=*) PARAM_SSID="${item#ssid=}" ;;
        ssid5=*) PARAM_SSID5="${item#ssid5=}" ;;
        pass5=*) PARAM_PASS5="${item#pass5=}" ;;
        ch5=*) PARAM_CH5="${item#ch5=}" ;;
        power5=*) PARAM_POWER5="${item#power5=}" ;;
        power24=*) PARAM_POWER24="${item#power24=}" ;;
        ssid24=*) PARAM_SSID24="${item#ssid24=}" ;;
        pass24=*) PARAM_PASS24="${item#pass24=}" ;;
        ch24=*) PARAM_CH24="${item#ch24=}" ;;
        band=*) PARAM_BAND="${item#band=}" ;;
        bssid=*) PARAM_BSSID="${item#bssid=}" ;;
        key=*|nwid=*|network_id=*) PARAM_KEY="${item#*=}" ;;
        minutes=*|duration=*) PARAM_MINUTES="${item#*=}" ;;
        name=*) PARAM_NAME="${item#name=}" ;;
        ip=*) PARAM_IP="${item#ip=}" ;;
        user=*) PARAM_USER="${item#user=}" ;;
        pass=*) PARAM_PASS="${item#pass=}" ;;
        new_pass=*) PARAM_NEW_PASS="${item#new_pass=}" ;;
        token=*) PARAM_TOKEN="${item#token=}" ;;
        bot_token=*) PARAM_BOT_TOKEN="${item#bot_token=}" ;;
        chat_id=*|chatid=*) PARAM_CHAT_ID="${item#*=}" ;;
        notif_wifi=*) PARAM_NOTIF_WIFI="${item#notif_wifi=}" ;;
        notif_expire=*) PARAM_NOTIF_EXPIRE="${item#notif_expire=}" ;;
        notif_daily=*) PARAM_NOTIF_DAILY="${item#notif_daily=}" ;;
        daily_hour=*) PARAM_DAILY_HOUR="${item#daily_hour=}" ;;
        bot_enabled=*) PARAM_BOT_ENABLED="${item#bot_enabled=}" ;;
        auto_update=*) PARAM_AUTO_UPDATE="${item#auto_update=}" ;;
        enabled=*) PARAM_ENABLED="${item#enabled=}" ;;
    esac
done
IFS="$OLD_IFS"

[ -n "$PARAM_SSID" ] && PARAM_SSID=$(echo "$PARAM_SSID" | tr '+' ' ')
[ -n "$PARAM_SSID5" ] && PARAM_SSID5=$(echo "$PARAM_SSID5" | tr '+' ' ')
[ -n "$PARAM_PASS5" ] && PARAM_PASS5=$(echo "$PARAM_PASS5" | tr '+' ' ')
[ -n "$PARAM_SSID24" ] && PARAM_SSID24=$(echo "$PARAM_SSID24" | tr '+' ' ')
[ -n "$PARAM_PASS24" ] && PARAM_PASS24=$(echo "$PARAM_PASS24" | tr '+' ' ')
[ -n "$PARAM_NAME" ] && PARAM_NAME=$(echo "$PARAM_NAME" | tr '+' ' ')
[ -n "$MAC" ] && MAC=$(echo "$MAC" | tr 'A-Z' 'a-z')

# 3. Đọc POST Body nếu có
POST_BODY=""
if [ "$REQUEST_METHOD" = "POST" ]; then
    if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
        POST_BODY=$(head -c "$CONTENT_LENGTH" 2>/dev/null)
    fi
fi

# 4. Định vị thư mục & Nạp thư viện chung
BACKEND_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$BACKEND_DIR/lib/constants.sh"
[ -f "$BACKEND_DIR/lib/platform.sh" ] && . "$BACKEND_DIR/lib/platform.sh"
. "$BACKEND_DIR/lib/json_helper.sh"
. "$BACKEND_DIR/lib/watchdog.sh"

# 5. Xác thực người dùng (mod_auth.sh)
if [ -f "$BACKEND_DIR/modules/mod_auth.sh" ]; then
    . "$BACKEND_DIR/modules/mod_auth.sh"
fi

if [ "$ACTION" != "login" ] && command -v require_auth >/dev/null 2>&1; then
    require_auth || exit 0
fi

# 6. HTTP Headers tiêu chuẩn cho mọi endpoint đã xác thực
printf "Content-Type: application/json; charset=utf-8\r\n"
printf "Access-Control-Allow-Origin: *\r\n"
printf "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
printf "Access-Control-Allow-Headers: Content-Type, Authorization\r\n\r\n"

# 7. Nạp các module tính năng
. "$BACKEND_DIR/modules/mod_network.sh"
. "$BACKEND_DIR/modules/mod_system.sh"
. "$BACKEND_DIR/modules/mod_clients.sh"
. "$BACKEND_DIR/modules/mod_wifi.sh"
. "$BACKEND_DIR/modules/mod_nextdns.sh"
. "$BACKEND_DIR/modules/mod_telegram.sh"
. "$BACKEND_DIR/modules/mod_update.sh"
. "$BACKEND_DIR/modules/mod_zerotier.sh"

# 8. Case Switch Router
case "$ACTION" in
    status|"")
        handle_status
        ;;
    clean_ram)
        handle_clean_ram
        ;;
    reboot)
        handle_reboot
        ;;
    reset_peak_bw)
        handle_reset_peak_bw
        ;;
    modem_get)
        handle_modem_get
        ;;
    clients)
        handle_clients
        ;;
    soft_block)
        handle_soft_block "$MAC" "$PARAM_MINUTES" "$PARAM_NAME" "$PARAM_IP"
        ;;
    hard_block)
        handle_hard_block "$MAC" "$PARAM_MINUTES" "$PARAM_NAME" "$PARAM_IP"
        ;;
    unblock)
        handle_unblock "$MAC"
        ;;
    wifi_get)
        handle_wifi_get
        ;;
    wifi_apply|wifi_apply_safe)
        handle_wifi_apply
        ;;
    wifi_scan)
        handle_wifi_scan
        ;;
    wifi_connect_uplink)
        handle_wifi_connect_uplink
        ;;
    wifi_rollback)
        handle_wifi_rollback
        ;;
    wifi_confirm)
        handle_wifi_confirm
        ;;
    nextdns_sync_ip)
        handle_nextdns_sync_ip
        ;;
    nextdns_get)
        handle_nextdns_get
        ;;
    nextdns_apikey_set)
        handle_nextdns_apikey_set
        ;;
    nextdns_apikey_del)
        handle_nextdns_apikey_del
        ;;
    nextdns_proxy)
        handle_nextdns_proxy
        ;;
    nextdns_set)
        handle_nextdns_set
        ;;
    nextdns_disable)
        handle_nextdns_disable
        ;;
    telegram_get)
        handle_telegram_get
        ;;
    telegram_set)
        handle_telegram_set
        ;;
    telegram_test)
        handle_telegram_test
        ;;
    telegram_service)
        handle_telegram_service
        ;;
    check_update)
        handle_check_update
        ;;
    do_update)
        handle_do_update
        ;;
    set_auto_update)
        handle_set_auto_update
        ;;
    zerotier_get)
        handle_zerotier_get
        ;;
    zerotier_join)
        handle_zerotier_join
        ;;
    zerotier_leave)
        handle_zerotier_leave
        ;;
    zerotier_info)
        handle_zerotier_info
        ;;
    *)
        printf '{"error":"unknown_action","action":"%s"}\n' "$(json_escape "$ACTION")"
        ;;
esac
