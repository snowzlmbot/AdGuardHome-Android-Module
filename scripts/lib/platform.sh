#!/system/bin/sh

normalize_arch() {
    raw_arch=${1:-}
    case "$raw_arch" in
        arm64|aarch64|arm64-v8a) AGH_ARCH=arm64 ;;
        arm|armv7|armeabi-v7a|armv7l) AGH_ARCH=armv7 ;;
        *) return 1 ;;
    esac
    export AGH_ARCH
    return 0
}

detect_arch() {
    detected_arch=${ARCH:-}
    if [ -z "$detected_arch" ] && command -v getprop >/dev/null 2>&1; then
        detected_arch=$(getprop ro.product.cpu.abi 2>/dev/null || true)
    fi
    if [ -z "$detected_arch" ]; then
        detected_arch=$(uname -m 2>/dev/null || true)
    fi
    normalize_arch "$detected_arch"
}

elf_matches_arch() {
    elf_file=${1:-}
    elf_arch=${2:-}
    [ -f "$elf_file" ] || return 1
    elf_magic=$(od -An -tx1 -N4 "$elf_file" 2>/dev/null | tr -d ' \n')
    [ "$elf_magic" = 7f454c46 ] || return 1
    elf_class=$(od -An -tu1 -j4 -N1 "$elf_file" 2>/dev/null | tr -d ' \n')
    elf_machine_bytes=$(od -An -tu1 -j18 -N2 "$elf_file" 2>/dev/null)
    set -- $elf_machine_bytes
    elf_machine_low=${1:-}
    elf_machine_high=${2:-}
    case "$elf_arch:$elf_class:$elf_machine_low:$elf_machine_high" in
        arm64:2:183:0) return 0 ;;
        armv7:1:40:0) return 0 ;;
    esac
    return 1
}

verify_binary() {
    binary_file=${1:-}
    binary_arch=${2:-}
    checksum_file=${3:-}
    [ -f "$binary_file" ] || return 1
    elf_matches_arch "$binary_file" "$binary_arch" || return 1
    if [ -n "$checksum_file" ]; then
        [ -f "$checksum_file" ] || return 1
        expected_checksum=$(awk 'NR == 1 {print $1}' "$checksum_file")
        actual_checksum=$(sha256sum "$binary_file" 2>/dev/null | awk '{print $1}')
        [ -n "$expected_checksum" ] || return 1
        [ "$expected_checksum" = "$actual_checksum" ] || return 1
    fi
    return 0
}

valid_port() {
    port_value=${1:-}
    case "$port_value" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$port_value" -ge 1024 ] 2>/dev/null && [ "$port_value" -le 65535 ] 2>/dev/null
}

port_is_free() {
    port_value=${1:-}
    valid_port "$port_value" || return 1
    if command -v ss >/dev/null 2>&1; then
        ! ss -lnt 2>/dev/null | grep -Eq "([.:])${port_value}[[:space:]]"
        return $?
    fi
    if command -v netstat >/dev/null 2>&1; then
        ! netstat -lnt 2>/dev/null | grep -Eq "([.:])${port_value}[[:space:]]"
        return $?
    fi
    return 0
}

port_candidate() {
    port_seed=${PORT_SEED:-$(date +%s 2>/dev/null || printf 30000)}
    port_try=${1:-0}
    PORT_CANDIDATE=$((30000 + ((port_seed + (port_try * 37)) % 20000)))
    export PORT_CANDIDATE
}

allocate_port() {
    avoid_port=${1:-}
    allocate_try=0
    while [ "$allocate_try" -lt 500 ]; do
        port_candidate "$allocate_try"
        if [ "$PORT_CANDIDATE" != "$avoid_port" ] && port_is_free "$PORT_CANDIDATE"; then
            ALLOCATED_PORT=$PORT_CANDIDATE
            export ALLOCATED_PORT
            return 0
        fi
        allocate_try=$((allocate_try + 1))
    done
    return 1
}

load_or_allocate_ports() {
    ports_file=${1:-${AGH_STATE_DIR:-/data/adb/agh/state}/ports.conf}
    mkdir -p "${ports_file%/*}" || return 1
    existing_web=$(sed -n 's/^web_port=//p' "$ports_file" 2>/dev/null | sed -n '1p')
    existing_dns=$(sed -n 's/^dns_port=//p' "$ports_file" 2>/dev/null | sed -n '1p')
    if valid_port "$existing_web" && valid_port "$existing_dns" && [ "$existing_web" != "$existing_dns" ]; then
        PORT_WEB=$existing_web
        PORT_DNS=$existing_dns
    else
        allocate_port '' || return 1
        PORT_WEB=$ALLOCATED_PORT
        allocate_port "$PORT_WEB" || return 1
        PORT_DNS=$ALLOCATED_PORT
    fi
    port_tmp="$ports_file.tmp.$$"
    umask 077
    printf 'web_port=%s\ndns_port=%s\n' "$PORT_WEB" "$PORT_DNS" > "$port_tmp" || return 1
    chmod 0600 "$port_tmp"
    sync
    mv -f "$port_tmp" "$ports_file" || return 1
    export PORT_WEB PORT_DNS
    return 0
}
