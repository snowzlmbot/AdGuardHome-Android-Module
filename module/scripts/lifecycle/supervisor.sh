#!/system/bin/sh

SCRIPT_DIR=${0%/*}
MODULE_SCRIPTS_DIR=${SCRIPT_DIR%/*}
MODDIR=${MODDIR:-${MODULE_SCRIPTS_DIR%/*}}
export MODDIR
. "$MODULE_SCRIPTS_DIR/lib/common.sh"
. "$MODULE_SCRIPTS_DIR/lib/atomic.sh"
. "$MODULE_SCRIPTS_DIR/lib/process.sh"
. "$MODULE_SCRIPTS_DIR/lib/log.sh"
. "$MODULE_SCRIPTS_DIR/lib/i18n.sh"

supervisor_worker_dir=${SUPERVISOR_WORKER_DIR:-$MODDIR}

supervisor_state_value() {
    supervisor_state_file=$1
    supervisor_state_key=$2
    [ -f "$supervisor_state_file" ] || return 1
    sed -n "s/^${supervisor_state_key}=//p" "$supervisor_state_file" | sed -n '1p'
}

supervisor_request() {
    supervisor_component=$1
    supervisor_action=$2
    supervisor_request_dir="$AGH_RUN_DIR/$supervisor_component"
    mkdir -p "$supervisor_request_dir"
    supervisor_tmp="$supervisor_request_dir/.request.$$"
    printf '%s\n' "$supervisor_action" > "$supervisor_tmp" || return 1
    agh_sync
    agh_move "$supervisor_tmp" "$supervisor_request_dir/request"
}

supervisor_enabled() {
    supervisor_config=$1
    [ -f "$supervisor_config" ] || return 1
    grep -q '^enabled=true$' "$supervisor_config"
}

supervisor_run_worker() {
    supervisor_name=$1
    supervisor_worker_action=${2:-once}
    supervisor_worker="$supervisor_worker_dir/$supervisor_name-worker.sh"
    if [ ! -x "$supervisor_worker" ]; then
        case "$supervisor_name" in
            core) supervisor_worker="$SCRIPT_DIR/../core/core-worker.sh" ;;
            network) supervisor_worker="$SCRIPT_DIR/../network/network-worker.sh" ;;
            firewall) supervisor_worker="$SCRIPT_DIR/../firewall/firewall-worker.sh" ;;
            proxy|file) supervisor_worker="$SCRIPT_DIR/../adapters/$supervisor_name-worker.sh" ;;
            *) supervisor_worker="$SCRIPT_DIR/$supervisor_name-worker.sh" ;;
        esac
    fi
    [ -f "$supervisor_worker" ] || { log_message supervisor "$supervisor_name worker missing"; return 1; }
    supervisor_worker_log="$AGH_LOG_DIR/$supervisor_name-worker.log"
    log_rotate_file "$supervisor_worker_log"
    agh_run_script "$supervisor_worker" "$supervisor_worker_action" >>"$supervisor_worker_log" 2>&1
    supervisor_rc=$?
    if [ "$supervisor_rc" -ne 0 ]; then
        log_message supervisor "$supervisor_name worker exited with status $supervisor_rc"
    fi
    return "$supervisor_rc"
}

# Finish removal before changing the DNS listener: a queued request alone
# leaves traffic pointed at a stopped core until the next successful cycle.
supervisor_detach_dns() {
    supervisor_request firewall remove || return 1
    supervisor_run_worker firewall || return 1
    [ "$(supervisor_state_value "$AGH_STATE_DIR/firewall.state" state)" = removed ]
}

supervisor_stop_components() {
    supervisor_detach_dns || return 1
    supervisor_stop_warning=0
    supervisor_run_worker core stop || supervisor_stop_warning=1
    if supervisor_enabled "$AGH_CONFIG_DIR/proxy-adapter.conf" || [ -s "$AGH_BACKUP_DIR/proxy/manifest.tsv" ]; then
        supervisor_run_worker proxy stop || supervisor_stop_warning=1
    fi
    if supervisor_enabled "$AGH_CONFIG_DIR/file-adapter.conf" || [ -s "$AGH_BACKUP_DIR/file/manifest.tsv" ]; then
        supervisor_run_worker file stop || supervisor_stop_warning=1
    fi
    return "$supervisor_stop_warning"
}

supervisor_consume_control() {
    supervisor_control_dir="$AGH_RUN_DIR/control"
    [ -d "$supervisor_control_dir" ] || return 0
    if [ -f "$supervisor_control_dir/pause" ]; then
        : > "$AGH_STATE_DIR/paused"
        supervisor_request firewall remove
        rm -f "$supervisor_control_dir/pause"
    fi
    if [ -f "$supervisor_control_dir/resume" ]; then
        rm -f "$AGH_STATE_DIR/paused"
        rm -f "$supervisor_control_dir/resume"
    fi
    if [ -f "$supervisor_control_dir/disable" ]; then
        : > "$AGH_STATE_DIR/core.disabled"
        supervisor_request firewall remove
        rm -f "$supervisor_control_dir/disable"
    fi
    if [ -f "$supervisor_control_dir/enable" ]; then
        rm -f "$AGH_STATE_DIR/core.disabled"
        rm -f "$supervisor_control_dir/enable"
    fi
    if [ -f "$supervisor_control_dir/restart-core" ]; then
        supervisor_detach_dns || return 1
        supervisor_run_worker core stop || return 1
        rm -f "$supervisor_control_dir/restart-core"
    fi
}

supervisor_update_module_description() {
    supervisor_mode=$(supervisor_state_value "$AGH_STATE_DIR/network.state" mode || sed -n 's/^mode=//p' "$AGH_CONFIG_DIR/mode.conf" 2>/dev/null | sed -n '1p')
    if [ "$MODULE_LANG" = zh ]; then
        case "$supervisor_mode" in
            1) supervisor_mode_name='内网兼容' ;;
            2) supervisor_mode_name='纯加密上游' ;;
            3) supervisor_mode_name='Bootstrap' ;;
            *) supervisor_mode_name='未知模式' ;;
        esac
    else
        case "$supervisor_mode" in
            1) supervisor_mode_name='LAN compatible' ;;
            2) supervisor_mode_name='Encrypted upstreams' ;;
            3) supervisor_mode_name='Bootstrap' ;;
            *) supervisor_mode_name='Unknown mode' ;;
        esac
    fi
    supervisor_core=$(supervisor_state_value "$AGH_STATE_DIR/core.state" state || printf 'unknown')
    supervisor_firewall=$(supervisor_state_value "$AGH_STATE_DIR/firewall.state" state || printf 'unknown')
    if [ "$MODULE_LANG" = zh ]; then
        if [ -f "$AGH_STATE_DIR/paused" ]; then supervisor_status_name='已暂停'
        elif [ -f "$AGH_STATE_DIR/core.disabled" ]; then supervisor_status_name='已停止'
        elif [ "$supervisor_core" = ready ] && [ "$supervisor_firewall" = ready ]; then supervisor_status_name='运行中'
        elif [ "$supervisor_core" = ready ]; then supervisor_status_name='核心运行，过滤未生效'
        else supervisor_status_name='异常'; fi
    else
        if [ -f "$AGH_STATE_DIR/paused" ]; then supervisor_status_name='Paused'
        elif [ -f "$AGH_STATE_DIR/core.disabled" ]; then supervisor_status_name='Stopped'
        elif [ "$supervisor_core" = ready ] && [ "$supervisor_firewall" = ready ]; then supervisor_status_name='Running'
        elif [ "$supervisor_core" = ready ]; then supervisor_status_name='Core running, filtering inactive'
        else supervisor_status_name='Error'; fi
    fi
    supervisor_description="[$supervisor_status_name | $supervisor_mode_name] AdGuard Home DNS filtering for Magisk and KernelSU"
    supervisor_module_prop=${MODULE_PROP_FILE:-$MODDIR/module.prop}
    if [ -f "$supervisor_module_prop" ]; then
        supervisor_tmp_prop="${supervisor_module_prop%/*}/.module.prop.$$"
        sed "s#^description=.*#description=$supervisor_description#" "$supervisor_module_prop" > "$supervisor_tmp_prop" && agh_move "$supervisor_tmp_prop" "$supervisor_module_prop"
        chmod 0644 "$supervisor_module_prop" 2>/dev/null || true
    fi
}

supervisor_aggregate() {
    supervisor_tmp="$AGH_STATE_DIR/.overall.state.$$"
    {
        printf 'core=%s\n' "$(supervisor_state_value "$AGH_STATE_DIR/core.state" state || printf 'unknown')"
        printf 'firewall=%s\n' "$(supervisor_state_value "$AGH_STATE_DIR/firewall.state" state || printf 'unknown')"
        printf 'network=%s\n' "$(supervisor_state_value "$AGH_STATE_DIR/network.state" state || printf 'unknown')"
        printf 'proxy=%s\n' "$(supervisor_state_value "$AGH_STATE_DIR/proxy.state" state || printf 'disabled')"
        printf 'file_adapter=%s\n' "$(supervisor_state_value "$AGH_STATE_DIR/file.state" state || printf 'disabled')"
        printf 'paused=%s\n' "$( [ -f "$AGH_STATE_DIR/paused" ] && printf true || printf false )"
    } > "$supervisor_tmp" || return 1
    agh_sync
    agh_move "$supervisor_tmp" "$AGH_STATE_DIR/overall.state"
    chmod 0600 "$AGH_STATE_DIR/overall.state"
    supervisor_update_module_description
}

supervisor_acquire_cycle_lock() {
    supervisor_lock_dir="$AGH_RUN_DIR/supervisor.lock"
    if ! mkdir "$supervisor_lock_dir" 2>/dev/null; then
        supervisor_lock_pid=$(sed -n '1p' "$supervisor_lock_dir/pid" 2>/dev/null)
        if pid_is_ours "$supervisor_lock_pid" "$SCRIPT_DIR/supervisor.sh"; then return 1; fi
        # An ownerless lock may be in its mkdir-to-PID window. Recheck once.
        if [ -z "$supervisor_lock_pid" ]; then
            sleep 1
            supervisor_lock_pid=$(sed -n '1p' "$supervisor_lock_dir/pid" 2>/dev/null)
            pid_is_ours "$supervisor_lock_pid" "$SCRIPT_DIR/supervisor.sh" && return 1
        fi
        rm -f "$supervisor_lock_dir/pid"
        rmdir "$supervisor_lock_dir" 2>/dev/null || return 1
        mkdir "$supervisor_lock_dir" 2>/dev/null || return 1
    fi
    printf '%s\n' "$$" > "$supervisor_lock_dir/pid"
}

supervisor_release_cycle_lock() {
    if [ "$(sed -n '1p' "$AGH_RUN_DIR/supervisor.lock/pid" 2>/dev/null)" = "$$" ]; then
        rm -f "$AGH_RUN_DIR/supervisor.lock/pid"
        rmdir "$AGH_RUN_DIR/supervisor.lock" 2>/dev/null || true
    fi
}

supervisor_once() {
    ensure_dirs || return 1
    supervisor_acquire_cycle_lock || return 0
    if [ -f "$AGH_RUN_DIR/stop" ]; then
        supervisor_stop_components
        supervisor_stop_rc=$?
        supervisor_release_cycle_lock
        return "$supervisor_stop_rc"
    fi
    SUPERVISOR_CYCLE=$(( ${SUPERVISOR_CYCLE:-0} + 1 ))
    module_detect_language || MODULE_LANG=en
    if ! supervisor_consume_control; then
        supervisor_release_cycle_lock
        return 1
    fi
    supervisor_run_worker network || true
    if [ -f "$AGH_STATE_DIR/core.disabled" ] || ! supervisor_run_worker core check-ready; then
        if ! supervisor_detach_dns; then
            supervisor_release_cycle_lock
            return 1
        fi
    fi
    supervisor_run_worker core || true
    supervisor_core_state=$(supervisor_state_value "$AGH_STATE_DIR/core.state" state || printf 'unknown')
    supervisor_core_authorized=$(supervisor_state_value "$AGH_STATE_DIR/core.state" firewall_authorized || printf '0')
    if [ -f "$AGH_STATE_DIR/paused" ]; then
        supervisor_request firewall remove
        supervisor_run_worker firewall || true
    elif [ "$supervisor_core_state" = ready ] && [ "$supervisor_core_authorized" = 1 ]; then
        supervisor_run_worker firewall || true
    else
        supervisor_request firewall remove
        supervisor_run_worker firewall || true
    fi
    if { [ "${SUPERVISOR_DAEMON_MODE:-0}" != 1 ] || [ "$((SUPERVISOR_CYCLE % 3))" -eq 0 ]; } && supervisor_enabled "$AGH_CONFIG_DIR/proxy-adapter.conf"; then
        if [ -f "$AGH_STATE_DIR/paused" ]; then
            printf 'state=paused\nreason=module_paused\n' > "$AGH_STATE_DIR/proxy.state"
        elif [ "$supervisor_core_state" = ready ]; then
            supervisor_run_worker proxy || true
        else
            printf 'state=blocked\nreason=core_not_ready\n' > "$AGH_STATE_DIR/proxy.state"
        fi
        chmod 0600 "$AGH_STATE_DIR/proxy.state"
    fi
    if { [ "${SUPERVISOR_DAEMON_MODE:-0}" != 1 ] || [ "$((SUPERVISOR_CYCLE % 3))" -eq 0 ]; } && supervisor_enabled "$AGH_CONFIG_DIR/file-adapter.conf"; then
        if [ -f "$AGH_STATE_DIR/paused" ]; then
            printf 'state=paused\nreason=module_paused\n' > "$AGH_STATE_DIR/file.state"
            chmod 0600 "$AGH_STATE_DIR/file.state"
        else
            supervisor_run_worker file || true
        fi
    fi
    supervisor_aggregate
    supervisor_release_cycle_lock
}

supervisor_wait_cycle_lock() {
    supervisor_stop_wait=0
    until supervisor_acquire_cycle_lock; do
        [ "$supervisor_stop_wait" -lt "${SUPERVISOR_STOP_WAIT:-70}" ] || return 1
        sleep 1
        supervisor_stop_wait=$((supervisor_stop_wait + 1))
    done
}

supervisor_suspend_core() {
    ensure_dirs || return 1
    supervisor_wait_cycle_lock || return 1
    supervisor_suspend_rc=1
    if supervisor_detach_dns; then
        supervisor_run_worker core stop
        supervisor_suspend_rc=$?
    fi
    supervisor_release_cycle_lock
    return "$supervisor_suspend_rc"
}

supervisor_stop() {
    ensure_dirs || return 1
    : > "$AGH_RUN_DIR/stop" || return 1
    supervisor_wait_cycle_lock || return 1
    supervisor_stop_components
    supervisor_stop_rc=$?
    supervisor_release_cycle_lock
    return "$supervisor_stop_rc"
}

supervisor_daemon_cleanup() {
    supervisor_pid_file="$AGH_RUN_DIR/supervisor.pid"
    if [ -f "$supervisor_pid_file" ] && [ "$(sed -n '1p' "$supervisor_pid_file")" = "$$" ]; then
        rm -f "$supervisor_pid_file"
    fi
    supervisor_release_cycle_lock
}

supervisor_daemon() {
    ensure_dirs || return 1
    supervisor_pid_file="$AGH_RUN_DIR/supervisor.pid"
    supervisor_old_pid=$(sed -n '1p' "$supervisor_pid_file" 2>/dev/null || true)
    if pid_is_ours "$supervisor_old_pid" "$SCRIPT_DIR/supervisor.sh"; then
        return 0
    fi
    rm -f "$AGH_RUN_DIR/stop"
    atomic_write "$supervisor_pid_file" "$$" || return 1
    SUPERVISOR_DAEMON_MODE=1
    export SUPERVISOR_DAEMON_MODE
    trap supervisor_daemon_cleanup EXIT
    trap 'supervisor_daemon_cleanup; exit 0' INT TERM
    while [ ! -f "$AGH_RUN_DIR/stop" ]; do
        supervisor_once || log_message supervisor 'supervisor cycle failed'
        [ ! -f "$AGH_RUN_DIR/stop" ] || break
        sleep "${SUPERVISOR_INTERVAL:-10}"
    done
    supervisor_stop
}

case "${1:-daemon}" in
    once|boot-completed) supervisor_once ;;
    daemon) supervisor_daemon ;;
    suspend-core) supervisor_suspend_core ;;
    stop) supervisor_stop ;;
    *) printf 'usage: %s {once|daemon|stop|suspend-core}\n' "$0" >&2; exit 2 ;;
esac
