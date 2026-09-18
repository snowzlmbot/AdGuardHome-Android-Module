#!/system/bin/sh

SCRIPT_DIR=${0%/*}
MODULE_SCRIPTS_DIR=${SCRIPT_DIR%/*}
MODDIR=${MODDIR:-${MODULE_SCRIPTS_DIR%/*}}
export MODDIR
. "$MODULE_SCRIPTS_DIR/lib/common.sh"
. "$MODULE_SCRIPTS_DIR/lib/atomic.sh"
. "$MODULE_SCRIPTS_DIR/lib/process.sh"
. "$MODULE_SCRIPTS_DIR/lib/log.sh"

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
    printf '%s\n' "$supervisor_action" > "$supervisor_tmp"
    sync
    mv -f "$supervisor_tmp" "$supervisor_request_dir/request"
}

supervisor_enabled() {
    supervisor_config=$1
    [ -f "$supervisor_config" ] || return 1
    grep -q '^enabled=true$' "$supervisor_config"
}

supervisor_run_worker() {
    supervisor_name=$1
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
    [ -x "$supervisor_worker" ] || return 0
    "$supervisor_worker" once >"$AGH_LOG_DIR/$supervisor_name-worker.log" 2>&1
    supervisor_rc=$?
    if [ "$supervisor_rc" -ne 0 ]; then
        log_message supervisor "$supervisor_name worker exited with status $supervisor_rc"
    fi
    return "$supervisor_rc"
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
        supervisor_worker="$SCRIPT_DIR/../core/core-worker.sh"
        [ -x "$supervisor_worker" ] && "$supervisor_worker" stop >/dev/null 2>&1 || true
        rm -f "$supervisor_control_dir/restart-core"
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
    } > "$supervisor_tmp"
    sync
    mv -f "$supervisor_tmp" "$AGH_STATE_DIR/overall.state"
    chmod 0600 "$AGH_STATE_DIR/overall.state"
}

supervisor_once() {
    ensure_dirs || return 1
    supervisor_consume_control
    supervisor_run_worker core || true
    supervisor_core_state=$(supervisor_state_value "$AGH_STATE_DIR/core.state" state || printf 'unknown')
    supervisor_core_authorized=$(supervisor_state_value "$AGH_STATE_DIR/core.state" firewall_authorized || printf '0')
    if [ "$supervisor_core_state" = ready ] && [ "$supervisor_core_authorized" = 1 ]; then
        supervisor_run_worker network || true
        supervisor_run_worker firewall || true
    else
        supervisor_request firewall remove
    fi
    if supervisor_enabled "$AGH_CONFIG_DIR/proxy-adapter.conf"; then
        supervisor_run_worker proxy || true
    fi
    if supervisor_enabled "$AGH_CONFIG_DIR/file-adapter.conf"; then
        supervisor_run_worker file || true
    fi
    supervisor_aggregate
}

supervisor_daemon() {
    while [ ! -f "$AGH_RUN_DIR/stop" ]; do
        supervisor_once || log_message supervisor 'supervisor cycle failed'
        sleep 5
    done
    supervisor_request core stop
    supervisor_request firewall remove
    supervisor_request proxy stop
    supervisor_request file stop
}

case "${1:-daemon}" in
    once|boot-completed) supervisor_once ;;
    daemon) supervisor_daemon ;;
    stop) : > "$AGH_RUN_DIR/stop"; supervisor_request core stop; supervisor_request firewall remove; supervisor_request proxy stop; supervisor_request file stop ;;
    *) printf 'usage: %s {once|daemon|stop}\n' "$0" >&2; exit 2 ;;
esac
