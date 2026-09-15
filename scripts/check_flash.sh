#!/bin/sh
# ==============================================================================
# VCRT OS v2.0 - FLASH STORAGE AUDIT & CLEANUP ADVISOR
# Báo cáo dung lượng Flash ROM / Overlay và đề xuất giải phóng an toàn
# Tương thích BusyBox POSIX (OpenWrt / KWrt)
# ==============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

DO_CLEAN=0
[ "$1" = "--clean" ] || [ "$1" = "-c" ] && DO_CLEAN=1

echo -e "${CYAN}==================================================================${NC}"
echo -e "${BOLD}${GREEN}   💾 VCRT OS v2.0 - KIEM TRA DUNG LUONG FLASH & OVERLAY        ${NC}"
echo -e "${CYAN}==================================================================${NC}"

# 1. Kiem tra phan vung Overlay & Rootfs
target_mnt="/overlay"
[ ! -d "$target_mnt" ] && target_mnt="/"

df_info=$(df -k "$target_mnt" 2>/dev/null | awk 'NR==2 {print $2, $3, $4, $5}')
tot_kb=$(echo "$df_info" | awk '{print $1}')
used_kb=$(echo "$df_info" | awk '{print $2}')
avail_kb=$(echo "$df_info" | awk '{print $3}')
pct=$(echo "$df_info" | awk '{print $4}')

[ -z "$tot_kb" ] && tot_kb=1
[ -z "$used_kb" ] && used_kb=0
[ -z "$avail_kb" ] && avail_kb=0
[ -z "$pct" ] && pct="0%"

tot_mb=$(awk -v k="$tot_kb" 'BEGIN{printf "%.2f", k/1024}')
used_mb=$(awk -v k="$used_kb" 'BEGIN{printf "%.2f", k/1024}')
avail_mb=$(awk -v k="$avail_kb" 'BEGIN{printf "%.2f", k/1024}')

# Kiem tra chip Flash tu /proc/mtd
flash_mb="16"
if [ -f /proc/mtd ]; then
    tot_mtd=$(awk '/mtd[0-9]+:/ {hex="0x"$2; sum += strtonum(hex)} END {print sum}' /proc/mtd 2>/dev/null)
    if [ -n "$tot_mtd" ] && [ "$tot_mtd" -gt 0 ] 2>/dev/null; then
        flash_mb=$((tot_mtd / 1048576))
    fi
fi

echo -e "🔹 ${BOLD}Chip Flash ROM:${NC} ${GREEN}${flash_mb} MB${NC}"
echo -e "🔹 ${BOLD}Phan vung Overlay (${target_mnt}):${NC}"
echo -e "   - Tong dung luong : ${tot_mb} MB (${tot_kb} KB)"
echo -e "   - Da su dung      : ${used_mb} MB (${used_kb} KB) - ${BOLD}${RED}${pct}${NC}"
echo -e "   - Con trong       : ${avail_mb} MB (${avail_kb} KB)"

# Canh bao neu con it hon 500 KB
pct_num=$(echo "$pct" | tr -d '%')
if [ "$avail_kb" -lt 500 ] 2>/dev/null; then
    echo -e "\n${RED}⚠️  CANH BAO NGUY HIEM: Overlay sap day (con duoi 500 KB)! Router co the bi bootloop.${NC}"
elif [ "$pct_num" -gt 85 ] 2>/dev/null; then
    echo -e "\n${YELLOW}⚠️  Luu y: Overlay da dung hon 85%, nen don dep cac goi khong can thiet.${NC}"
else
    echo -e "\n${GREEN}✅ Tinh trang bo nho tot. Khong gian con lai du cho he thong hoat dong on dinh.${NC}"
fi

echo -e "\n${CYAN}------------------------------------------------------------------${NC}"
echo -e "${BOLD}📋 DANH SACH THANH PHAN CO THE XOA / TOI UU AN TOAN:${NC}"
echo -e "${CYAN}------------------------------------------------------------------${NC}"

reclaim_kb=0

# A. Kiem tra cac goi tieng Trung LuCI
zh_pkgs=""
zh_pkg_count=0
if command -v opkg >/dev/null 2>&1; then
    zh_pkgs=$(opkg list-installed 2>/dev/null | grep -E 'luci-i18n-.*-zh-cn' | awk '{print $1}')
    for p in $zh_pkgs; do
        zh_pkg_count=$((zh_pkg_count + 1))
        reclaim_kb=$((reclaim_kb + 25))
    done
fi

if [ "$zh_pkg_count" -gt 0 ]; then
    echo -e " 1. ${YELLOW}Goi ngon ngu tieng Trung (${zh_pkg_count} goi):${NC} ~${zh_pkg_count}x25 KB = ~$((zh_pkg_count * 25)) KB"
    for p in $zh_pkgs; do
        echo -e "    - $p"
    done
else
    echo -e " 1. ${GREEN}Goi ngon ngu tieng Trung:${NC} Da sach se (0 goi)"
fi

# B. File .lmo tieng Trung con sot lai tren dia
lmo_kb=0
lmo_files=$(find /usr/lib/lua/luci/i18n /www/luci-static/resources/i18n -name "*zh-cn*" 2>/dev/null || true)
if [ -n "$lmo_files" ]; then
    for f in $lmo_files; do
        sz=$(du -k "$f" 2>/dev/null | awk '{print $1}')
        [ -n "$sz" ] && lmo_kb=$((lmo_kb + sz))
    done
fi
if [ "$lmo_kb" -gt 0 ]; then
    echo -e " 2. ${YELLOW}Tap tin .lmo / json tieng Trung sot lai:${NC} ~${lmo_kb} KB"
    reclaim_kb=$((reclaim_kb + lmo_kb))
else
    echo -e " 2. ${GREEN}Tap tin .lmo / json tieng Trung:${NC} Khong phat hien"
fi

# C. Danh sach cache opkg
opkg_cache_kb=0
if [ -d /var/opkg-lists ]; then
    sz=$(du -sk /var/opkg-lists 2>/dev/null | awk '{print $1}')
    [ -n "$sz" ] && opkg_cache_kb="$sz"
fi
if [ "$opkg_cache_kb" -gt 0 ]; then
    echo -e " 3. ${YELLOW}Cache danh muc goi OPKG (/var/opkg-lists):${NC} ~${opkg_cache_kb} KB"
    reclaim_kb=$((reclaim_kb + opkg_cache_kb))
else
    echo -e " 3. ${GREEN}Cache OPKG:${NC} Sach se"
fi

# D. LuCI index cache
luci_cache_kb=0
for cand in /tmp/luci-indexcache /tmp/luci-modulecache; do
    if [ -f "$cand" ]; then
        sz=$(du -k "$cand" 2>/dev/null | awk '{print $1}')
        [ -n "$sz" ] && luci_cache_kb=$((luci_cache_kb + sz))
    fi
done
if [ "$luci_cache_kb" -gt 0 ]; then
    echo -e " 4. ${YELLOW}Cache giao dien LuCI:${NC} ~${luci_cache_kb} KB"
    reclaim_kb=$((reclaim_kb + luci_cache_kb))
else
    echo -e " 4. ${GREEN}Cache LuCI:${NC} Sach se"
fi

# E. Log & Crash files
log_kb=0
for cand in /tmp/log /var/log; do
    if [ -d "$cand" ]; then
        sz=$(du -sk "$cand" 2>/dev/null | awk '{print $1}')
        [ -n "$sz" ] && log_kb=$((log_kb + sz))
    fi
done
if [ "$log_kb" -gt 50 ]; then
    echo -e " 5. ${YELLOW}Log he thong tam thoi (/var/log):${NC} ~${log_kb} KB"
    reclaim_kb=$((reclaim_kb + log_kb))
fi

echo -e "${CYAN}------------------------------------------------------------------${NC}"
reclaim_mb=$(awk -v k="$reclaim_kb" 'BEGIN{printf "%.2f", k/1024}')
echo -e "✨ ${BOLD}Uoc tinh dung luong co the giai phong:${NC} ${GREEN}~${reclaim_mb} MB (${reclaim_kb} KB)${NC}"
echo -e "${CYAN}------------------------------------------------------------------${NC}"

# Thuc hien don dep neu duoc yeu cau
if [ "$DO_CLEAN" = "1" ]; then
    echo -e "\n${BOLD}${YELLOW}>> DANG TIEN HANH DON DEP BO NHO FLASH AN TOAN...${NC}"

    # 1. Go bo cac goi tieng Trung
    if [ "$zh_pkg_count" -gt 0 ]; then
        echo "   -> Dang xoa cac goi tieng Trung qua opkg..."
        for p in $zh_pkgs; do
            opkg remove --force-depends "$p" >/dev/null 2>&1 || true
        done
    fi

    # 2. Xoa cac tap tin lmo sot lai
    if [ "$lmo_kb" -gt 0 ]; then
        echo "   -> Dang xoa cac tap tin .lmo tieng Trung..."
        rm -rf /usr/lib/lua/luci/i18n/*zh-cn* /www/luci-static/resources/i18n/*zh-cn* 2>/dev/null || true
    fi

    # 3. Don cache opkg
    if [ "$opkg_cache_kb" -gt 0 ]; then
        echo "   -> Dang lam sach cache opkg-lists..."
        rm -rf /var/opkg-lists/* 2>/dev/null || true
    fi

    # 4. Don cache LuCI
    echo "   -> Dang lam sach LuCI cache..."
    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache /tmp/luci-* 2>/dev/null || true

    # Kiem tra lai sau khi don dep
    df_after=$(df -k "$target_mnt" 2>/dev/null | awk 'NR==2 {print $3, $4, $5}')
    used_after_kb=$(echo "$df_after" | awk '{print $1}')
    avail_after_kb=$(echo "$df_after" | awk '{print $2}')
    pct_after=$(echo "$df_after" | awk '{print $3}')
    avail_after_mb=$(awk -v k="$avail_after_kb" 'BEGIN{printf "%.2f", k/1024}')

    echo -e "\n${GREEN}🎉 DA HOAN TAT DON DEP!${NC}"
    echo -e "   - Dung luong trong moi: ${BOLD}${GREEN}${avail_after_mb} MB (${avail_after_kb} KB)${NC}"
    echo -e "   - Ty le su dung con   : ${BOLD}${GREEN}${pct_after}${NC}"
else
    echo -e "\n💡 ${BOLD}De tu dong don dep an toan, hay chay lenh:${NC}"
    echo -e "   ${CYAN}sh $0 --clean${NC} (hoac ${CYAN}sh $0 -c${NC})\n"
fi

exit 0
