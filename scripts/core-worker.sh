#!/system/bin/sh

SCRIPT_DIR=${0%/*}
MODDIR=${MODDIR:-${SCRIPT_DIR%/*}}
export MODDIR
. "$SCRIPT_DIR/lib/common.sh"
. "$SCRIPT_DIR/lib/atomic.sh"
. "$SCRIPT_DIR/lib/config.sh"
. "$SCRIPT_DIR/lib/platform.sh"
. "$SCRIPT_DIR/lib/credentials.sh"
. "$SCRIPT_DIR/lib/process.sh"
. "$SCRIPT_DIR/lib/log.sh"

core_state_write() {
    core_state_value=$1
    core_state_reason=${2:-}
    core_state_tmp="$AGH_STATE_DIR/.core.state.$$"
    mkdir -p "$AGH_STATE_DIR"
    {
        printf 'state=%s\n' "$core_state_value"
        printf 'pid=%s\n' "${CORE_PID:-}"
        printf 'web_port=%s\n' "${PORT_WEB:-}"
        printf 'dns_port=%s\n' "${PORT_DNS:-}"
        printf 'firewall_authorized=%s\n' "${CORE_FIREWALL_AUTHORIZED:-0}"
        printf 'reason=%s\n' "$core_state_reason"
    } > "$core_state_tmp" || return 1
    chmod 0600 "$core_state_tmp"
    sync
    mv -f "$core_state_tmp" "$AGH_STATE_DIR/core.state"
}

core_probe_port() {
    core_probe_port_value=$1
    if [ -n "${CORE_PORT_PROBE_CMD:-}" ]; then
        "$CORE_PORT_PROBE_CMD" "$core_probe_port_value"
        return $?
    fi
    if command -v ss >/dev/null 2>&1; then
        ss -lnt 2>/dev/null | grep -Eq "([.:])${core_probe_port_value}[[:space:]]"
        return $?
    fi
    if command -v netstat >/dev/null 2>&1; then
        netstat -lnt 2>/dev/null | grep -Eq "([.:])${core_probe_port_value}[[:space:]]"
        return $?
    fi
    return 1
}

core_prepare_runtime_config() {
    core_runtime_config="$AGH_RUN_DIR/runtime.yaml"
    mkdir -p "$AGH_RUN_DIR"
    cp "$AGH_CONFIG_DIR/AdGuardHome.yaml" "$core_runtime_config" || return 1
    sed -i "/^http:/,/^[^[:space:]]/ s#^[[:space:]]*address: 127.0.0.1:[0-9][0-9]*#  address: 127.0.0.1:$PORT_WEB#" "$core_runtime_config" || return 1
    sed -i "/^dns:/,/^[^[:space:]]/ s#^[[:space:]]*port: [0-9][0-9]*#  port: $PORT_DNS#" "$core_runtime_config" || return 1
    chmod 0600 "$core_runtime_config"
    CORE_RUNTIME_CONFIG=$core_runtime_config
}

core_initialize_auth() {
    [ "${CORE_TEST_MODE:-0}" = 1 ] && return 0
    grep -q '^users:[[:space:]]*\[\][[:space:]]*$' "$AGH_CONFIG_DIR/AdGuardHome.yaml" || return 0
    core_username=$(credential_value username)
    core_password=$(credential_value password)
    [ -n "$core_username" ] && [ -n "$core_password" ] || return 1
    core_auth_json=$(printf '{"web":{"ip":"127.0.0.1","port":%s},"dns":{"ip":"127.0.0.1","port":%s},"username":"%s","password":"%s"}' "$PORT_WEB" "$PORT_DNS" "$core_username" "$core_password")
    if command -v curl >/dev/null 2>&1; then
        printf '%s' "$core_auth_json" | curl -fsS --max-time 15 -H 'Content-Type: application/json' -X POST --data-binary @- "http://127.0.0.1:$PORT_WEB/control/install/configure" >/dev/null 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- --timeout=15 --header='Content-Type: application/json' --post-data="$core_auth_json" "http://127.0.0.1:$PORT_WEB/control/install/configure" >/dev/null 2>&1
    else
        return 1
    fi
}

core_pid_is_ours() {
    if [ "${CORE_TEST_MODE:-0}" = 1 ]; then
        pid_is_alive "$CORE_PID"
        return $?
    fi
    pid_is_ours "$CORE_PID" "$AGH_ROOT/bin/AdGuardHome"
}

core_stop() {
    CORE_PID=
    [ -f "$AGH_RUN_DIR/core.pid" ] && CORE_PID=$(cat "$AGH_RUN_DIR/core.pid")
    if [ -n "$CORE_PID" ]; then
        if [ "${CORE_TEST_MODE:-0}" = 1 ]; then
            stop_pid_bounded "$CORE_PID" "${CORE_STOP_WAIT:-1}" || true
        elif pid_is_ours "$CORE_PID" "$AGH_ROOT/bin/AdGuardHome"; then
            stop_pid_bounded "$CORE_PID" "${CORE_STOP_WAIT:-10}" || true
        fi
    fi
    rm -f "$AGH_RUN_DIR/core.pid"
    CORE_FIREWALL_AUTHORIZED=0
    core_state_write stopped stopped || true
}

core_start() {
    CORE_BINARY="$AGH_ROOT/bin/AdGuardHome"
    [ -x "$CORE_BINARY" ] || { core_state_write failed missing_binary; return 1; }
    [ -f "$AGH_CONFIG_DIR/AdGuardHome.yaml" ] || { core_state_write failed missing_config; return 1; }
    validate_agh_yaml "$AGH_CONFIG_DIR/AdGuardHome.yaml" || { core_state_write failed invalid_config; return 1; }
    load_or_allocate_ports "$AGH_STATE_DIR/ports.conf" || { core_state_write failed invalid_ports; return 1; }
    core_prepare_runtime_config || { core_state_write failed runtime_config; return 1; }
    export SSL_CERT_DIR=${SSL_CERT_DIR:-/system/etc/security/cacerts/}
    "$CORE_BINARY" --config "$CORE_RUNTIME_CONFIG" --work-dir "$AGH_DATA_DIR" --no-check-update >"$AGH_LOG_DIR/core-process.log" 2>&1 &
    CORE_PID=$!
    CORE_FIREWALL_AUTHORIZED=0
    printf '%s\n' "$CORE_PID" > "$AGH_RUN_DIR/core.pid"
    chmod 0600 "$AGH_RUN_DIR/core.pid"
    sleep "${CORE_START_WAIT:-1}"
    if ! core_pid_is_ours || ! core_probe_port "$PORT_WEB" || ! core_probe_port "$PORT_DNS"; then
        core_stop
        core_state_write failed health_probe
        return 1
    fi
    if ! core_initialize_auth; then
        core_stop
        core_state_write failed credential_initialization
        return 1
    fi
    CORE_FIREWALL_AUTHORIZED=1
    core_state_write ready ready
}

core_once() {
    ensure_dirs || return 1
    if [ -f "$AGH_STATE_DIR/core.disabled" ]; then
        core_stop
        core_state_write disabled disabled
        return 0
    fi
    if [ -f "$AGH_RUN_DIR/core.pid" ]; then
        CORE_PID=$(cat "$AGH_RUN_DIR/core.pid")
        if core_pid_is_ours && load_or_allocate_ports "$AGH_STATE_DIR/ports.conf" && core_probe_port "$PORT_WEB" && core_probe_port "$PORT_DNS"; then
            CORE_FIREWALL_AUTHORIZED=1
            core_state_write ready existing
            return 0
        fi
        core_stop
    fi
    core_start
}

core_daemon() {
    core_delay=1
    while [ ! -f "$AGH_RUN_DIR/stop" ]; do
        if core_once; then
            core_delay=1
            sleep 5
        else
            core_state_write degraded "retry_in_${core_delay}s" || true
            sleep "$core_delay"
            [ "$core_delay" -lt 60 ] && core_delay=$((core_delay * 2))
            [ "$core_delay" -gt 60 ] && core_delay=60
        fi
    done
    core_stop
}

case "${1:-once}" in
    once) core_once ;;
    daemon) core_daemon ;;
    stop) core_stop ;;
    *) printf 'usage: %s {once|daemon|stop}\n' "$0" >&2; exit 2 ;;
esac
