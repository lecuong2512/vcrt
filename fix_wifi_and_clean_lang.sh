#!/bin/sh
# ==============================================================================
# FIX WIFI + XOA TIENG TRUNG + CAU HINH PHAT SONG XIAOMI MIWIFI MINI
# ==============================================================================

echo '=== [1/4] Xoa sach ngon ngu tieng Trung va chuyen sang Tieng Anh ==='
# Chuyen ngon ngu LuCI sang Tieng Anh (en)
uci set luci.main.lang='en'
uci commit luci

# Xoa cac goi ngon ngu tieng Trung .lmo
rm -rf /usr/lib/lua/luci/i18n/*zh-cn* 2>/dev/null || true
rm -rf /www/luci-static/resources/i18n/*zh-cn* 2>/dev/null || true

# Xoa cache LuCI de cap nhat ngay lap tuc
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache /tmp/luci-* 2>/dev/null || true

# Xoa cac comment tieng Trung trong dhcp
sed -i 's/后台地址/Router_Admin/g' /etc/config/dhcp 2>/dev/null || true

echo '=== [2/4] Kich hoat ca 2 bang tan Wi-Fi 2.4GHz va 5GHz ==='
# Xoa co tat wifi (disabled 0)
uci set wireless.radio0.disabled='0'
uci set wireless.radio1.disabled='0'

# Thiet lap thong so chuan cho song 2.4GHz (Kenh 6, 20MHz, WMM)
uci set wireless.radio0.country='VN'
uci set wireless.radio0.channel='6'
uci set wireless.radio0.htmode='HT20'

# Thiet lap thong so chuan cho song 5GHz (Kenh 44, 80MHz, Short GI)
uci set wireless.radio1.country='VN'
uci set wireless.radio1.channel='44'
uci set wireless.radio1.htmode='VHT80'

# Tao / Cap nhat diem phat song AP cho 2.4GHz
uci -q get wireless.default_radio0 || uci set wireless.default_radio0=wifi-iface
uci set wireless.default_radio0.device='radio0'
uci set wireless.default_radio0.network='lan'
uci set wireless.default_radio0.mode='ap'
uci set wireless.default_radio0.ssid='Xiaomi_2.4G'
uci set wireless.default_radio0.encryption='psk2+ccmp'
uci set wireless.default_radio0.key='12345678'
uci set wireless.default_radio0.disabled='0'
uci set wireless.default_radio0.wmm='1'

# Tao / Cap nhat diem phat song AP cho 5GHz
uci -q get wireless.default_radio1 || uci set wireless.default_radio1=wifi-iface
uci set wireless.default_radio1.device='radio1'
uci set wireless.default_radio1.network='lan'
uci set wireless.default_radio1.mode='ap'
uci set wireless.default_radio1.ssid='Xiaomi_5G'
uci set wireless.default_radio1.encryption='psk2+ccmp'
uci set wireless.default_radio1.key='12345678'
uci set wireless.default_radio1.disabled='0'
uci set wireless.default_radio1.wmm='1'
uci set wireless.default_radio1.short_gi_80='1'

uci commit wireless

echo '=== [3/4] Khoi dong lai song Wi-Fi va LuCI Web ==='
wifi reload
/etc/init.d/uhttpd restart
/etc/init.d/rpcd restart

echo '=== [4/4] HOAN TAT! ==='
echo '1. Giao dien da duoc chuyen sang Tieng Anh sach se (khong con tieng Trung).'
echo '2. Wi-Fi da phat ca 2 song: Xiaomi_2.4G va Xiaomi_5G (Mat khau: 12345678).'
