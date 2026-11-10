#!/bin/sh
# VCRT OS v2.0 - System Update Module
# Endpoints: check_update, do_update, set_auto_update
# Hỗ trợ SHA-256 Checksum Verification & latest.json Manifest từ GitHub

UPDATE_MANIFEST_URL="https://raw.githubusercontent.com/lecuong2512/vcrt/main/latest.json"
UPDATE_VERSION_FALLBACK_URL="https://raw.githubusercontent.com/lecuong2512/vcrt/main/version"
DEFAULT_PACKAGE_URL="https://raw.githubusercontent.com/lecuong2512/vcrt/main/deploy_vcrt.tar.gz"

_norm_ver() {
    printf '%s' "$1" | tr -d ' \r\n"' | sed 's/^[vV]//'
}

_ver_gt() {
    awk -v a="$1" -v b="$2" '
    BEGIN {
        na = split(a, va, ".");
        nb = split(b, vb, ".");
        n = (na > nb ? na : nb);
        for (i = 1; i <= n; i++) {
            xa = (i <= na ? int(va[i]) : 0);
            xb = (i <= nb ? int(vb[i]) : 0);
            if (xa > xb) exit 0;
            if (xa < xb) exit 1;
        }
        exit 1;
    }'
}

handle_check_update() {
    local cur_ver="2.2.0"
    [ -f "$VERSION_FILE" ] && cur_ver=$(_norm_ver "$(cat "$VERSION_FILE" 2>/dev/null)")
    [ -z "$cur_ver" ] && cur_ver="2.2.0"

    local cb
    cb=$(date +%s 2>/dev/null || echo 1)

    # Tải latest.json manifest (kèm cache-buster tránh CDN cache cũ)
    local manifest_raw rem_ver="" pkg_url="" pkg_sha256="" changelog=""
    manifest_raw=$(curl -4 --tlsv1.2 --tls-max 1.2 -s --max-time 6 "${UPDATE_MANIFEST_URL}?_=${cb}" 2>/dev/null)

    if [ -n "$manifest_raw" ] && echo "$manifest_raw" | grep -q '"version"'; then
        rem_ver=$(_norm_ver "$(echo "$manifest_raw" | grep -o '"version"[ ]*:[ ]*"[^"]*"' | head -n1 | cut -d'"' -f4)")
        pkg_url=$(echo "$manifest_raw" | grep -o '"url"[ ]*:[ ]*"[^"]*"' | head -n1 | cut -d'"' -f4)
        pkg_sha256=$(echo "$manifest_raw" | grep -o '"sha256"[ ]*:[ ]*"[^"]*"' | head -n1 | cut -d'"' -f4)
        changelog=$(echo "$manifest_raw" | grep -o '"changelog"[ ]*:[ ]*"[^"]*"' | head -n1 | cut -d'"' -f4)
        echo "$manifest_raw" > /tmp/vcrt_latest.json
    else
        # Fallback đọc version file đơn giản
        rem_ver=$(_norm_ver "$(curl -4 --tlsv1.2 --tls-max 1.2 -s --max-time 6 "${UPDATE_VERSION_FALLBACK_URL}?_=${cb}" 2>/dev/null)")
    fi

    local has_up="false" valid_rem="false"
    if [ -n "$rem_ver" ] && echo "$rem_ver" | grep -qE '^[0-9]+(\.[0-9]+)+$'; then
        valid_rem="true"
        if _ver_gt "$rem_ver" "$cur_ver"; then
            has_up="true"
        fi
    fi

    local auto_up="false"
    if [ -f "$TELEGRAM_CONF" ] && grep -q '^AUTO_UPDATE=1' "$TELEGRAM_CONF" 2>/dev/null; then
        auto_up="true"
    fi

    cat << EOF
{
  "status": "ok",
  "current_version": "$(json_escape "$cur_ver")",
  "remote_version": "$([ "$valid_rem" = "true" ] && json_escape "$rem_ver" || json_escape "$cur_ver")",
  "has_update": ${has_up},
  "auto_update": ${auto_up},
  "sha256": "$(json_escape "$pkg_sha256")",
  "changelog": "$(json_escape "$changelog")"
}
EOF
}

handle_do_update() {
    local target_url="$DEFAULT_PACKAGE_URL"
    local expected_sha256=""

    if [ -f /tmp/vcrt_latest.json ]; then
        local u s
        u=$(grep -o '"url"[ ]*:[ ]*"[^"]*"' /tmp/vcrt_latest.json | head -n1 | cut -d'"' -f4)
        s=$(grep -o '"sha256"[ ]*:[ ]*"[^"]*"' /tmp/vcrt_latest.json | head -n1 | cut -d'"' -f4)
        [ -n "$u" ] && target_url="$u"
        [ -n "$s" ] && expected_sha256="$s"
    fi

    # Tạo script nâng cấp độc lập để không bị kill khi restart uhttpd / vcrt_bot
    cat << EOF > /tmp/vcrt_self_update.sh
#!/bin/sh
pkg_file="/tmp/deploy_vcrt.tar.gz"
work_dir="/tmp/vcrt_deploy"
rm -rf "\$pkg_file" "\$work_dir" /tmp/vcrt_update_status.txt 2>/dev/null

echo "downloading" > /tmp/vcrt_update_status.txt
if ! curl -4 --tlsv1.2 --tls-max 1.2 -s -L -k --max-time 60 -o "\$pkg_file" "${target_url}?_=\$(date +%s)"; then
    echo "download_failed" > /tmp/vcrt_update_status.txt
    exit 1
fi

if [ ! -s "\$pkg_file" ]; then
    echo "download_failed" > /tmp/vcrt_update_status.txt
    rm -f "\$pkg_file"
    exit 1
fi

if [ -n "${expected_sha256}" ]; then
    echo "verifying_checksum" > /tmp/vcrt_update_status.txt
    actual_sha256=""
    if command -v sha256sum >/dev/null 2>&1; then
        actual_sha256=\$(sha256sum "\$pkg_file" 2>/dev/null | awk '{print \$1}')
    elif command -v openssl >/dev/null 2>&1; then
        actual_sha256=\$(openssl dgst -sha256 "\$pkg_file" 2>/dev/null | awk '{print \$NF}')
    fi
    if [ -n "\$actual_sha256" ] && [ "\$actual_sha256" != "${expected_sha256}" ]; then
        echo "sha256_mismatch" > /tmp/vcrt_update_status.txt
        rm -f "\$pkg_file"
        exit 1
    fi
fi

echo "installing" > /tmp/vcrt_update_status.txt
mkdir -p "\$work_dir"
if tar -xzf "\$pkg_file" -C "\$work_dir" 2>/dev/null && [ -f "\$work_dir/install.sh" ]; then
    sh "\$work_dir/install.sh" >/tmp/vcrt_update.log 2>&1
    echo "success" > /tmp/vcrt_update_status.txt
else
    echo "extract_failed" > /tmp/vcrt_update_status.txt
fi
rm -rf "\$pkg_file" "\$work_dir" /tmp/vcrt_self_update.sh 2>/dev/null
EOF
    chmod +x /tmp/vcrt_self_update.sh
    if command -v setsid >/dev/null 2>&1; then
        setsid sh /tmp/vcrt_self_update.sh </dev/null >/dev/null 2>&1 &
    else
        sh /tmp/vcrt_self_update.sh </dev/null >/dev/null 2>&1 &
    fi

    json_ok '"message":"update_started"'
}

handle_set_auto_update() {
    local val="${PARAM_ENABLED:-0}"
    mkdir -p "$CONFIG_DIR" 2>/dev/null

    if [ -f "$TELEGRAM_CONF" ]; then
        if grep -q '^AUTO_UPDATE=' "$TELEGRAM_CONF"; then
            sed -i "s/^AUTO_UPDATE=.*/AUTO_UPDATE=${val}/" "$TELEGRAM_CONF"
        else
            echo "AUTO_UPDATE=${val}" >> "$TELEGRAM_CONF"
        fi
    else
        echo "AUTO_UPDATE=${val}" > "$TELEGRAM_CONF"
    fi

    local au_res="false"
    [ "$val" = "1" ] && au_res="true"
    printf '{"status":"ok","auto_update":%s}\n' "$au_res"
}
