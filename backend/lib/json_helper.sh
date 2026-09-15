#!/bin/sh
# VCRT OS v2.0 - JSON Helper (RFC 8259 POSIX BusyBox Compatible)

json_escape() {
    [ -z "$1" ] && return 0
    printf '%s' "$1" | awk '
    BEGIN {
        ORS = ""
        for (i = 0; i < 32; i++) {
            ctrl[sprintf("%c", i)] = sprintf("\\u%04x", i)
        }
        ctrl["\b"] = "\\b"
        ctrl["\f"] = "\\f"
        ctrl["\n"] = "\\n"
        ctrl["\r"] = "\\r"
        ctrl["\t"] = "\\t"
    }
    {
        len = length($0)
        for (i = 1; i <= len; i++) {
            c = substr($0, i, 1)
            if (c == "\\") printf "\\\\"
            else if (c == "\"") printf "\\\""
            else if (c in ctrl) printf "%s", ctrl[c]
            else printf "%s", c
        }
        if (NR > 1) printf "\\n"
    }'
}

json_str() {
    printf '"%s"' "$(json_escape "$1")"
}

json_bool() {
    case "$1" in
        1|true|TRUE|yes|YES) printf "true" ;;
        *) printf "false" ;;
    esac
}

json_num() {
    case "$1" in
        ''|*[!0-9.-]*) printf "0" ;;
        *) printf "%s" "$1" ;;
    esac
}

json_ok() {
    if [ -n "$1" ]; then
        printf '{"status":"ok",%s}\n' "$1"
    else
        printf '{"status":"ok"}\n'
    fi
}

json_error() {
    printf '{"status":"error","message":"%s"}\n' "$(json_escape "$1")"
}
