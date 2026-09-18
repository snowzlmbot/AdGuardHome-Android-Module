#!/system/bin/sh

pid_is_alive() {
    pid_value=${1:-}
    [ -n "$pid_value" ] || return 1
    kill -0 "$pid_value" 2>/dev/null
}

pid_is_ours() {
    pid_value=${1:-}
    expected_path=${2:-}
    [ -n "$pid_value" ] || return 1
    [ -n "$expected_path" ] || return 1
    pid_is_alive "$pid_value" || return 1
    proc_exe=$(readlink "/proc/$pid_value/exe" 2>/dev/null || true)
    [ "$proc_exe" = "$expected_path" ] && return 0
    proc_cmdline=$(tr '\000' ' ' < "/proc/$pid_value/cmdline" 2>/dev/null || true)
    case "$proc_cmdline" in
        "$expected_path"*) return 0 ;;
    esac
    return 1
}

stop_pid_bounded() {
    stop_pid=${1:-}
    stop_seconds=${2:-10}
    [ -n "$stop_pid" ] || return 0
    pid_is_alive "$stop_pid" || return 0
    kill "$stop_pid" 2>/dev/null || true
    stop_count=0
    while pid_is_alive "$stop_pid" && [ "$stop_count" -lt "$stop_seconds" ]; do
        sleep 1
        stop_count=$((stop_count + 1))
    done
    if pid_is_alive "$stop_pid"; then
        kill -9 "$stop_pid" 2>/dev/null || true
        return 1
    fi
    return 0
}

wait_for_file() {
    wait_file=${1:-}
    wait_seconds=${2:-10}
    wait_count=0
    while [ ! -f "$wait_file" ] && [ "$wait_count" -lt "$wait_seconds" ]; do
        sleep 1
        wait_count=$((wait_count + 1))
    done
    [ -f "$wait_file" ]
}
