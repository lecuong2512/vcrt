#!/bin/sh
# VCRT OS v2.0 - Network & Traffic Statistics Module
# Live bandwidth, Peak tracking, Multi-period Traffic Accounting

# Hàm tính toán lưu lượng và băng thông thời gian thực
calc_network_stats() {
    local wan_iface="$1"
    [ -z "$wan_iface" ] && wan_iface="eth0"

    local now_sec rx2 tx2
    now_sec=$(cut -d. -f1 /proc/uptime 2>/dev/null || date +%s)
    rx2=$(cat "/sys/class/net/${wan_iface}/statistics/rx_bytes" 2>/dev/null || echo 0)
    tx2=$(cat "/sys/class/net/${wan_iface}/statistics/tx_bytes" 2>/dev/null || echo 0)
    case "$rx2" in ''|*[!0-9]*) rx2=0 ;; esac
    case "$tx2" in ''|*[!0-9]*) tx2=0 ;; esac

    dl_mbps="0.0"
    ul_mbps="0.0"
    if [ -f "$BW_TMP_FILE" ]; then
        local last_sec last_rx last_tx dt drx dtx
        read -r last_sec last_rx last_tx < "$BW_TMP_FILE" 2>/dev/null
        dt=$((now_sec - last_sec))
        if [ "$dt" -gt 0 ] && [ "$dt" -lt 30 ]; then
            drx=$((rx2 - last_rx))
            dtx=$((tx2 - last_tx))
            [ "$drx" -lt 0 ] && drx=0
            [ "$dtx" -lt 0 ] && dtx=0
            dl_mbps=$(awk -v b="$drx" -v t="$dt" 'BEGIN {printf "%.1f", (b * 8) / (t * 1000000)}')
            ul_mbps=$(awk -v b="$dtx" -v t="$dt" 'BEGIN {printf "%.1f", (b * 8) / (t * 1000000)}')
        fi
    fi
    echo "$now_sec $rx2 $tx2" > "$BW_TMP_FILE" 2>/dev/null

    # Peak Bandwidth Tracking
    peak_dl="0.0"
    peak_ul="0.0"
    if [ -f "$PEAK_BW_FILE" ]; then
        read -r peak_dl peak_ul < "$PEAK_BW_FILE" 2>/dev/null
    fi
    case "$peak_dl" in ''|*[!0-9.]*) peak_dl="0.0" ;; esac
    case "$peak_ul" in ''|*[!0-9.]*) peak_ul="0.0" ;; esac

    local peak_changed=0
    if awk -v a="$dl_mbps" -v b="$peak_dl" 'BEGIN {exit !(a+0 > b+0)}'; then
        peak_dl="$dl_mbps"; peak_changed=1
    fi
    if awk -v a="$ul_mbps" -v b="$peak_ul" 'BEGIN {exit !(a+0 > b+0)}'; then
        peak_ul="$ul_mbps"; peak_changed=1
    fi
    if [ "$peak_dl" = "0.0" ] || [ "$peak_dl" = "0" ]; then
        peak_dl="$dl_mbps"; peak_changed=1
    fi
    if [ "$peak_ul" = "0.0" ] || [ "$peak_ul" = "0" ]; then
        peak_ul="$ul_mbps"; peak_changed=1
    fi
    [ "$peak_changed" -eq 1 ] && echo "$peak_dl $peak_ul" > "$PEAK_BW_FILE" 2>/dev/null

    # Traffic Accounting & Database Persistence
    mkdir -p "$CONFIG_DIR" /tmp 2>/dev/null
    [ ! -f "$TRAFFIC_DAILY_DB" ] && touch "$TRAFFIC_DAILY_DB" 2>/dev/null
    [ ! -f "$TRAFFIC_HOURLY_DB" ] && touch "$TRAFFIC_HOURLY_DB" 2>/dev/null

    local today_date today_hour today_year today_month now_epoch
    today_date=$(date +%Y-%m-%d 2>/dev/null || echo "2026-09-15")
    today_hour=$(date +%H 2>/dev/null || echo "10")
    today_year=$(date +%Y 2>/dev/null || echo "2026")
    today_month=$(date +%m 2>/dev/null || echo "09")
    now_epoch=$(date +%s 2>/dev/null || echo 0)

    local delta_rx=0 delta_tx=0
    if [ -f "$PREV_WAN_BYTES" ]; then
        local p_rx p_tx
        read -r p_rx p_tx < "$PREV_WAN_BYTES" 2>/dev/null
        case "$p_rx" in ''|*[!0-9]*) p_rx=0 ;; esac
        case "$p_tx" in ''|*[!0-9]*) p_tx=0 ;; esac
        if [ "$rx2" -ge "$p_rx" ] 2>/dev/null; then
            delta_rx=$((rx2 - p_rx))
            delta_tx=$((tx2 - p_tx))
        else
            delta_rx="$rx2"
            delta_tx="$tx2"
        fi
    else
        if ! grep -q "^${today_date}|" "$TRAFFIC_DAILY_DB" 2>/dev/null; then
            delta_rx="$rx2"
            delta_tx="$tx2"
        fi
    fi
    echo "$rx2 $tx2" > "$PREV_WAN_BYTES" 2>/dev/null

    if [ "$delta_rx" -gt 0 ] 2>/dev/null || [ "$delta_tx" -gt 0 ] 2>/dev/null; then
        if grep -q "^${today_date}|" "$TRAFFIC_DAILY_DB" 2>/dev/null; then
            awk -F'|' -v cur_d="$today_date" -v drx="$delta_rx" -v dtx="$delta_tx" '
            $1 == cur_d { printf "%s|%d|%d\n", $1, $2 + drx, $3 + dtx; next; }
            { print $0; }
            ' "$TRAFFIC_DAILY_DB" > "${TRAFFIC_DAILY_DB}.tmp" 2>/dev/null && mv -f "${TRAFFIC_DAILY_DB}.tmp" "$TRAFFIC_DAILY_DB"
        else
            echo "${today_date}|${delta_rx}|${delta_tx}" >> "$TRAFFIC_DAILY_DB" 2>/dev/null
        fi

        local cur_h_key="${today_date} ${today_hour}"
        if grep -q "^${cur_h_key}|" "$TRAFFIC_HOURLY_DB" 2>/dev/null; then
            awk -F'[ |]' -v cur_k="$cur_h_key" -v drx="$delta_rx" -v dtx="$delta_tx" '
            ($1 " " $2) == cur_k { printf "%s %s|%d|%d\n", $1, $2, $3 + drx, $4 + dtx; next; }
            { print $0; }
            ' "$TRAFFIC_HOURLY_DB" > "${TRAFFIC_HOURLY_DB}.tmp" 2>/dev/null && mv -f "${TRAFFIC_HOURLY_DB}.tmp" "$TRAFFIC_HOURLY_DB"
        else
            echo "${cur_h_key}|${delta_rx}|${delta_tx}" >> "$TRAFFIC_HOURLY_DB" 2>/dev/null
        fi
    fi

    # Danh sách 7 ngày gần nhất
    local past_7_dates="" i=6
    while [ "$i" -ge 0 ]; do
        local sec_past d_cand
        sec_past=$((now_epoch - i * 86400))
        d_cand=$(date -d "@$sec_past" +%Y-%m-%d 2>/dev/null)
        [ -z "$d_cand" ] && d_cand="$today_date"
        [ -n "$past_7_dates" ] && past_7_dates="${past_7_dates},"
        past_7_dates="${past_7_dates}${d_cand}"
        i=$((i - 1))
    done

    traffic_stats_json=$(awk \
    -v hourly_file="$TRAFFIC_HOURLY_DB" \
    -v daily_file="$TRAFFIC_DAILY_DB" \
    -v cur_date="$today_date" \
    -v cur_year="$today_year" \
    -v cur_month="$today_month" \
    -v cur_hour="$today_hour" \
    -v past_7_dates="$past_7_dates" \
    -v live_rx="$rx2" \
    -v live_tx="$tx2" \
    'function fmt(b) {
        if (b >= 1073741824) return sprintf("%.2f GB", b/1073741824);
        if (b >= 1048576) return sprintf("%.1f MB", b/1048576);
        if (b >= 1024) return sprintf("%.1f KB", b/1024);
        return sprintf("%d B", b);
    }
    BEGIN { FS = "[ |]"; }
    FILENAME == hourly_file {
        if ($1 == cur_date) {
            h = $2 + 0;
            h_rx[h] = $3 + 0; h_tx[h] = $4 + 0;
        }
        next;
    }
    FILENAME == daily_file {
        d = $1; split(d, dt, "-");
        y = dt[1] + 0; m = dt[2] + 0;
        r_b = $2 + 0; t_b = $3 + 0;
        d_rx[d] = r_b; d_tx[d] = t_b;
        ym = sprintf("%04d-%02d", y, m);
        m_rx[ym] += r_b; m_tx[ym] += t_b;
        yr_rx[y] += r_b; yr_tx[y] += t_b;
        next;
    }
    END {
        # 1. TODAY
        tod_rx = (cur_date in d_rx) ? d_rx[cur_date] : 0;
        tod_tx = (cur_date in d_tx) ? d_tx[cur_date] : 0;
        if (tod_rx == 0 && tod_tx == 0) { tod_rx = live_rx + 0; tod_tx = live_tx + 0; }
        tod_dl = fmt(tod_rx); tod_ul = fmt(tod_tx); tod_tot = fmt(tod_rx + tod_tx);

        cur_h = cur_hour + 0; p_today = "";
        for (h = 0; h <= cur_h; h++) {
            lbl = sprintf("%02dh:00", h);
            if (h == cur_h) lbl = sprintf("%02dh (Hiện tại)", h);
            rx_val = (h in h_rx) ? (h_rx[h] / 1048576) : 0.0;
            tx_val = (h in h_tx) ? (h_tx[h] / 1048576) : 0.0;
            if (p_today != "") p_today = p_today ", ";
            p_today = p_today sprintf("{\"label\":\"%s\",\"dl\":%.1f,\"ul\":%.1f}", lbl, rx_val, tx_val);
        }
        if (p_today == "") p_today = sprintf("{\"label\":\"Hiện tại\",\"dl\":%.1f,\"ul\":%.1f}", tod_rx/1048576, tod_tx/1048576);

        # 2. 7 DAYS
        split(past_7_dates, d7_arr, ",");
        p_7d = ""; tot_7d_rx = 0; tot_7d_tx = 0;
        for (i = 1; i <= 7; i++) {
            dk = d7_arr[i];
            rx_b = (dk in d_rx) ? d_rx[dk] : 0;
            tx_b = (dk in d_tx) ? d_tx[dk] : 0;
            if (dk == cur_date && rx_b == 0) { rx_b = tod_rx; tx_b = tod_tx; }
            tot_7d_rx += rx_b; tot_7d_tx += tx_b;
            lbl = (i == 7) ? "Hôm nay" : dk;
            sub(/^[0-9]+-/, "", lbl);
            if (p_7d != "") p_7d = p_7d ", ";
            p_7d = p_7d sprintf("{\"label\":\"%s\",\"dl\":%.1f,\"ul\":%.1f}", lbl, rx_b / 1048576, tx_b / 1048576);
        }
        s7_dl = fmt(tot_7d_rx); s7_ul = fmt(tot_7d_tx); s7_tot = fmt(tot_7d_rx + tot_7d_tx);

        # 3. 1 MONTH
        w_rx[1] = 0; w_rx[2] = 0; w_rx[3] = 0; w_rx[4] = 0;
        w_tx[1] = 0; w_tx[2] = 0; w_tx[3] = 0; w_tx[4] = 0;
        tot_m_rx = 0; tot_m_tx = 0;
        for (dk in d_rx) {
            split(dk, pfx, "-");
            if ((pfx[1] + 0) == (cur_year + 0) && (pfx[2] + 0) == (cur_month + 0)) {
                dy = pfx[3] + 0;
                w_idx = int((dy - 1) / 7) + 1;
                if (w_idx > 4) w_idx = 4;
                w_rx[w_idx] += d_rx[dk]; w_tx[w_idx] += d_tx[dk];
                tot_m_rx += d_rx[dk]; tot_m_tx += d_tx[dk];
            }
        }
        if (tot_m_rx == 0) { tot_m_rx = tot_7d_rx; tot_m_tx = tot_7d_tx; }
        sm_dl = fmt(tot_m_rx); sm_ul = fmt(tot_m_tx); sm_tot = fmt(tot_m_rx + tot_m_tx);
        p_m = "";
        for (w = 1; w <= 4; w++) {
            lbl = sprintf("Tuần %d", w);
            if (p_m != "") p_m = p_m ", ";
            p_m = p_m sprintf("{\"label\":\"%s\",\"dl\":%.1f,\"ul\":%.1f}", lbl, w_rx[w] / 1048576, w_tx[w] / 1048576);
        }

        # 4. 1 QUARTER
        q_num = int((cur_month - 1) / 3) + 1;
        q_start_m = (q_num - 1) * 3 + 1;
        tot_q_rx = 0; tot_q_tx = 0; p_q = "";
        for (m = q_start_m; m < q_start_m + 3; m++) {
            ym_k = sprintf("%04d-%02d", cur_year, m);
            q_m_r = (ym_k in m_rx) ? m_rx[ym_k] : 0;
            q_m_t = (ym_k in m_tx) ? m_tx[ym_k] : 0;
            tot_q_rx += q_m_r; tot_q_tx += q_m_t;
            lbl = sprintf("Tháng %d", m);
            if (m == cur_month) lbl = sprintf("Tháng %d (Hiện tại)", m);
            if (p_q != "") p_q = p_q ", ";
            p_q = p_q sprintf("{\"label\":\"%s\",\"dl\":%.1f,\"ul\":%.1f}", lbl, q_m_r / 1048576, q_m_t / 1048576);
        }
        if (tot_q_rx == 0) { tot_q_rx = tot_m_rx; tot_q_tx = tot_m_tx; }
        sq_dl = fmt(tot_q_rx); sq_ul = fmt(tot_q_tx); sq_tot = fmt(tot_q_rx + tot_q_tx);

        # 5. 1 YEAR
        tot_y_rx = (cur_year in yr_rx) ? yr_rx[cur_year] : 0;
        tot_y_tx = (cur_year in yr_tx) ? yr_tx[cur_year] : 0;
        if (tot_y_rx == 0) { tot_y_rx = tot_q_rx; tot_y_tx = tot_q_tx; }
        sy_dl = fmt(tot_y_rx); sy_ul = fmt(tot_y_tx); sy_tot = fmt(tot_y_rx + tot_y_tx);
        p_y = "";
        for (m = 1; m <= 12; m++) {
            ym_k = sprintf("%04d-%02d", cur_year, m);
            y_m_r = (ym_k in m_rx) ? m_rx[ym_k] : 0;
            y_m_t = (ym_k in m_tx) ? m_tx[ym_k] : 0;
            lbl = sprintf("T%d", m);
            if (p_y != "") p_y = p_y ", ";
            p_y = p_y sprintf("{\"label\":\"%s\",\"dl\":%.1f,\"ul\":%.1f}", lbl, y_m_r / 1048576, y_m_t / 1048576);
        }

        printf "{\n";
        printf "  \"today\": { \"dl\": \"%s\", \"ul\": \"%s\", \"total\": \"%s\", \"unit\": \"MB\", \"points\": [%s] },\n", tod_dl, tod_ul, tod_tot, p_today;
        printf "  \"days7\": { \"dl\": \"%s\", \"ul\": \"%s\", \"total\": \"%s\", \"unit\": \"MB\", \"points\": [%s] },\n", s7_dl, s7_ul, s7_tot, p_7d;
        printf "  \"7d\": { \"dl\": \"%s\", \"ul\": \"%s\", \"total\": \"%s\", \"unit\": \"MB\", \"points\": [%s] },\n", s7_dl, s7_ul, s7_tot, p_7d;
        printf "  \"month\": { \"dl\": \"%s\", \"ul\": \"%s\", \"total\": \"%s\", \"unit\": \"MB\", \"points\": [%s] },\n", sm_dl, sm_ul, sm_tot, p_m;
        printf "  \"quarter\": { \"dl\": \"%s\", \"ul\": \"%s\", \"total\": \"%s\", \"unit\": \"MB\", \"points\": [%s] },\n", sq_dl, sq_ul, sq_tot, p_q;
        printf "  \"year\": { \"dl\": \"%s\", \"ul\": \"%s\", \"total\": \"%s\", \"unit\": \"MB\", \"points\": [%s] }\n", sy_dl, sy_ul, sy_tot, p_y;
        printf "}";
    }' "$TRAFFIC_HOURLY_DB" "$TRAFFIC_DAILY_DB" 2>/dev/null)

    # Tổng lưu lượng tải / gửi
    eval $(awk -v r="$rx2" -v t="$tx2" 'function fmt(b) {
        if (b >= 1073741824) return sprintf("%.2f GB", b/1073741824);
        if (b >= 1048576) return sprintf("%.1f MB", b/1048576);
        if (b >= 1024) return sprintf("%.1f KB", b/1024);
        return sprintf("%d B", b);
    }
    BEGIN {
        printf "tot_rx_str=\"%s\"; tot_tx_str=\"%s\"; tot_sum_str=\"%s\";", fmt(r), fmt(t), fmt(r+t);
    }')

    [ -z "$traffic_stats_json" ] && traffic_stats_json="{\"today\":{\"dl\":\"${tot_rx_str}\",\"ul\":\"${tot_tx_str}\",\"total\":\"${tot_sum_str}\",\"unit\":\"MB\",\"points\":[]},\"7d\":{\"dl\":\"${tot_rx_str}\",\"ul\":\"${tot_tx_str}\",\"total\":\"${tot_sum_str}\",\"unit\":\"MB\",\"points\":[]},\"days7\":{\"dl\":\"${tot_rx_str}\",\"ul\":\"${tot_tx_str}\",\"total\":\"${tot_sum_str}\",\"unit\":\"MB\",\"points\":[]},\"month\":{\"dl\":\"${tot_rx_str}\",\"ul\":\"${tot_tx_str}\",\"total\":\"${tot_sum_str}\",\"unit\":\"MB\",\"points\":[]},\"quarter\":{\"dl\":\"${tot_rx_str}\",\"ul\":\"${tot_tx_str}\",\"total\":\"${tot_sum_str}\",\"unit\":\"MB\",\"points\":[]},\"year\":{\"dl\":\"${tot_rx_str}\",\"ul\":\"${tot_tx_str}\",\"total\":\"${tot_sum_str}\",\"unit\":\"MB\",\"points\":[]}}"
}

handle_reset_peak_bw() {
    echo "0.0 0.0" > "$PEAK_BW_FILE"
    json_ok '"action":"reset_peak_bw"'
}
