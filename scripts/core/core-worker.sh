#!/system/bin/sh

SCRIPT_DIR=${0%/*}
MODULE_SCRIPTS_DIR=${SCRIPT_DIR%/*}
MODDIR=${MODDIR:-${MODULE_SCRIPTS_DIR%/*}}
export MODDIR
. "$MODULE_SCRIPTS_DIR/lib/common.sh"
. "$MODULE_SCRIPTS_DIR/lib/atomic.sh"
. "$MODULE_SCRIPTS_DIR/lib/config.sh"
. "$MODULE_SCRIPTS_DIR/lib/agh-config.sh"
. "$MODULE_SCRIPTS_DIR/lib/platform.sh"
. "$MODULE_SCRIPTS_DIR/lib/credentials.sh"
. "$MODULE_SCRIPTS_DIR/lib/process.sh"
. "$MODULE_SCRIPTS_DIR/lib/log.sh"

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
        printf 'retry_in=%s\n' "${CORE_RETRY_IN:-0}"
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
    core_probe_hex=$(printf '%04X' "$core_probe_port_value" 2>/dev/null) || return 1
    grep -qi ":${core_probe_hex}[[:space:]]" /proc/net/tcp /proc/net/tcp6 2>/dev/null
}

core_wait_for_port() {
    core_wait_port=$1
    core_wait_seconds=${2:-30}
    core_wait_count=0
    while [ "$core_wait_count" -lt "$core_wait_seconds" ]; do
        core_pid_is_ours || return 2
        core_probe_port "$core_wait_port" && return 0
        sleep 1
        core_wait_count=$((core_wait_count + 1))
    done
    return 1
}

core_prepare_runtime_config() {
    core_runtime_config="$AGH_CONFIG_DIR/AdGuardHome.yaml"
    core_config_tmp="$AGH_CONFIG_DIR/.AdGuardHome.yaml.$$"
    cp "$core_runtime_config" "$core_config_tmp" || return 1
    sed -i "/^http:/,/^[^[:space:]]/ s#^[[:space:]]*address: 127.0.0.1:[0-9][0-9]*#  address: 127.0.0.1:$PORT_WEB#" "$core_config_tmp" || { rm -f "$core_config_tmp"; return 1; }
    sed -i "/^dns:/,/^[^[:space:]]/ s#^[[:space:]]*port: [0-9][0-9]*#  port: $PORT_DNS#" "$core_config_tmp" || { rm -f "$core_config_tmp"; return 1; }
    chmod 0600 "$core_config_tmp"
    sync
    mv -f "$core_config_tmp" "$core_runtime_config" || return 1
    CORE_RUNTIME_CONFIG=$core_runtime_config
}

core_needs_initial_setup() {
    [ ! -f "$AGH_CONFIG_DIR/AdGuardHome.yaml" ] && return 0
    grep -q '^users:[[:space:]]*\[\][[:space:]]*$' "$AGH_CONFIG_DIR/AdGuardHome.yaml"
}

core_apply_initial_config() {
    core_username=$(credential_value username)
    core_password=$(credential_value password)
    [ -n "$core_username" ] && [ -n "$core_password" ] || return 1
    if [ -n "${CORE_INSTALL_CMD:-}" ]; then
        "$CORE_INSTALL_CMD" "$PORT_WEB" "$PORT_DNS" "$core_username" "$core_password" "$AGH_CONFIG_DIR/AdGuardHome.yaml"
        return $?
    fi
    core_auth_json=$(printf '{"web":{"ip":"127.0.0.1","port":%s},"dns":{"ip":"127.0.0.1","port":%s},"username":"%s","password":"%s"}' "$PORT_WEB" "$PORT_DNS" "$core_username" "$core_password")
    if command -v curl >/dev/null 2>&1; then
        printf '%s' "$core_auth_json" | curl -fsS --max-time 15 -H 'Content-Type: application/json' -X POST --data-binary @- "http://127.0.0.1:$PORT_WEB/control/install/configure" >/dev/null 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- --timeout=15 --header='Content-Type: application/json' --post-data="$core_auth_json" "http://127.0.0.1:$PORT_WEB/control/install/configure" >/dev/null 2>&1
    else
        return 1
    fi
}

core_restore_initial_template() {
    core_initial_backup="$AGH_BACKUP_DIR/pre-initial-setup.yaml"
    [ -f "$core_initial_backup" ] || return 0
    if [ ! -f "$AGH_CONFIG_DIR/AdGuardHome.yaml" ] || grep -q '^users:[[:space:]]*\[\][[:space:]]*$' "$AGH_CONFIG_DIR/AdGuardHome.yaml"; then
        atomic_copy "$core_initial_backup" "$AGH_CONFIG_DIR/AdGuardHome.yaml" || return 1
    fi
}

core_apply_selected_mode() {
    core_selected_mode=$(sed -n 's/^mode=//p' "$AGH_CONFIG_DIR/mode.conf" 2>/dev/null | sed -n '1p')
    case "$core_selected_mode" in 1|2|3) ;; *) return 1 ;; esac
    core_mode_backup="$AGH_BACKUP_DIR/pre-mode-config.yaml"
    cp -f "$AGH_CONFIG_DIR/AdGuardHome.yaml" "$core_mode_backup" || return 1
    if ! agh_apply_mode "$core_selected_mode" "$AGH_CONFIG_DIR/AdGuardHome.yaml" "$AGH_CONFIG_DIR/mode.conf"; then
        atomic_copy "$core_mode_backup" "$AGH_CONFIG_DIR/AdGuardHome.yaml" || true
        return 1
    fi
    if ! "$CORE_BINARY" --config "$AGH_CONFIG_DIR/AdGuardHome.yaml" --work-dir "$AGH_DATA_DIR" --check-config >/dev/null 2>&1; then
        atomic_copy "$core_mode_backup" "$AGH_CONFIG_DIR/AdGuardHome.yaml" || true
        return 1
    fi
    rm -f "$core_mode_backup"
    printf 'version=1\nmode=%s\n' "$core_selected_mode" > "$AGH_STATE_DIR/upstream-policy.conf"
    chmod 0600 "$AGH_STATE_DIR/upstream-policy.conf"
}

core_start_process() {
    core_log="$AGH_LOG_DIR/core-process.log"
    if [ "${CORE_INITIAL_SETUP:-0}" = 1 ]; then
        "$CORE_BINARY" --config "$AGH_CONFIG_DIR/AdGuardHome.yaml" --work-dir "$AGH_DATA_DIR" --web-addr "127.0.0.1:$PORT_WEB" --no-check-update >"$core_log" 2>&1 &
    else
        "$CORE_BINARY" --config "$CORE_RUNTIME_CONFIG" --work-dir "$AGH_DATA_DIR" --no-check-update >"$core_log" 2>&1 &
    fi
    CORE_PID=$!
    printf '%s\n' "$CORE_PID" > "$AGH_RUN_DIR/core.pid"
    chmod 0600 "$AGH_RUN_DIR/core.pid"
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
    CORE_INITIAL_SETUP=0
    if core_needs_initial_setup; then
        CORE_INITIAL_SETUP=1
        cp -f "$AGH_CONFIG_DIR/AdGuardHome.yaml" "$AGH_BACKUP_DIR/pre-initial-setup.yaml" || { core_state_write failed config_backup; return 1; }
        rm -f "$AGH_CONFIG_DIR/AdGuardHome.yaml"
    else
        if [ ! -f "$AGH_STATE_DIR/upstream-policy.conf" ]; then
            if grep -q 'dns10.quad9.net' "$AGH_CONFIG_DIR/AdGuardHome.yaml"; then
                core_apply_selected_mode || { core_state_write failed mode_configuration; return 1; }
            else
                printf 'version=1\nmode=custom\n' > "$AGH_STATE_DIR/upstream-policy.conf"
                chmod 0600 "$AGH_STATE_DIR/upstream-policy.conf"
            fi
        fi
        core_prepare_runtime_config || { core_state_write failed runtime_config; return 1; }
    fi
    export SSL_CERT_DIR=${SSL_CERT_DIR:-/system/etc/security/cacerts/}
    core_start_process
    CORE_FIREWALL_AUTHORIZED=0
    if ! core_wait_for_port "$PORT_WEB" "${CORE_START_WAIT:-30}"; then
        core_stop
        [ "$CORE_INITIAL_SETUP" = 1 ] && core_restore_initial_template || true
        core_state_write failed web_port_timeout
        return 1
    fi
    if [ "$CORE_INITIAL_SETUP" = 1 ]; then
        if ! core_apply_initial_config; then
            core_stop
            core_restore_initial_template || true
            core_state_write failed initial_configuration
            return 1
        fi
        if ! core_wait_for_port "$PORT_DNS" "${CORE_DNS_WAIT:-30}"; then
            core_stop
            core_restore_initial_template || true
            core_state_write failed dns_port_timeout
            return 1
        fi
        core_stop
        if ! core_apply_selected_mode; then
            core_restore_initial_template || true
            core_state_write failed mode_configuration
            return 1
        fi
        CORE_INITIAL_SETUP=0
        core_prepare_runtime_config || { core_state_write failed runtime_config; return 1; }
        core_start_process
        if ! core_wait_for_port "$PORT_WEB" "${CORE_START_WAIT:-30}" || ! core_wait_for_port "$PORT_DNS" "${CORE_DNS_WAIT:-30}"; then
            core_stop
            core_state_write failed mode_restart_timeout
            return 1
        fi
    elif ! core_wait_for_port "$PORT_DNS" "${CORE_DNS_WAIT:-30}"; then
        core_stop
        core_state_write failed dns_port_timeout
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
            core_failure_reason=$(sed -n 's/^reason=//p' "$AGH_STATE_DIR/core.state" 2>/dev/null | sed -n '1p')
            [ -n "$core_failure_reason" ] || core_failure_reason=unknown_failure
            CORE_RETRY_IN=$core_delay
            core_state_write failed "$core_failure_reason" || true
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
