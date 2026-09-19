#!/system/bin/sh

SCRIPT_DIR=${0%/*}
MODULE_SCRIPTS_DIR=${SCRIPT_DIR%/*}
MODDIR=${MODDIR:-${MODULE_SCRIPTS_DIR%/*}}
export MODDIR
. "$MODULE_SCRIPTS_DIR/lib/common.sh"
. "$MODULE_SCRIPTS_DIR/lib/atomic.sh"
. "$MODULE_SCRIPTS_DIR/lib/log.sh"
. "$MODULE_SCRIPTS_DIR/lib/agh-config.sh"

control_set_adapter() {
    control_adapter_name=$1
    control_adapter_value=$2
    control_adapter_config="$AGH_CONFIG_DIR/$control_adapter_name-adapter.conf"
    [ -f "$control_adapter_config" ] || return 1
    control_adapter_tmp="$control_adapter_config.tmp.$$"
    if grep -q '^enabled=' "$control_adapter_config"; then
        sed "s/^enabled=.*/enabled=$control_adapter_value/" "$control_adapter_config" > "$control_adapter_tmp"
    else
        cat "$control_adapter_config" > "$control_adapter_tmp"
        printf 'enabled=%s\n' "$control_adapter_value" >> "$control_adapter_tmp"
    fi
    sync
    mv -f "$control_adapter_tmp" "$control_adapter_config"
}

control_set_mode() {
    control_mode=$1
    case "$control_mode" in 1|2|3) ;; *) return 1 ;; esac
    control_mode_file="$AGH_CONFIG_DIR/mode.conf"
    control_yaml="$AGH_CONFIG_DIR/AdGuardHome.yaml"
    control_binary="$AGH_ROOT/bin/AdGuardHome"
    [ -f "$control_mode_file" ] && [ -f "$control_yaml" ] && [ -x "$control_binary" ] || return 1
    control_yaml_backup="$AGH_BACKUP_DIR/control-mode.yaml"
    control_mode_backup="$AGH_BACKUP_DIR/control-mode.conf"
    cp -f "$control_yaml" "$control_yaml_backup" || return 1
    cp -f "$control_mode_file" "$control_mode_backup" || return 1
    control_was_disabled=false
    [ -f "$AGH_STATE_DIR/core.disabled" ] && control_was_disabled=true
    : > "$AGH_STATE_DIR/core.disabled"
    sh "$SCRIPT_DIR/../core/core-worker.sh" stop >/dev/null 2>&1 || true
    if ! agh_apply_mode "$control_mode" "$control_yaml" "$control_mode_file" || ! "$control_binary" --config "$control_yaml" --work-dir "$AGH_DATA_DIR" --check-config >/dev/null 2>&1; then
        atomic_copy "$control_yaml_backup" "$control_yaml" || true
        atomic_copy "$control_mode_backup" "$control_mode_file" || true
        [ "$control_was_disabled" = true ] || rm -f "$AGH_STATE_DIR/core.disabled"
        return 1
    fi
    printf 'version=1\nmode=%s\n' "$control_mode" > "$AGH_STATE_DIR/upstream-policy.conf"
    chmod 0600 "$AGH_STATE_DIR/upstream-policy.conf"
    rm -f "$control_yaml_backup" "$control_mode_backup"
    [ "$control_was_disabled" = true ] || rm -f "$AGH_STATE_DIR/core.disabled"
    mkdir -p "$AGH_RUN_DIR/firewall"
    printf 'remove\n' > "$AGH_RUN_DIR/firewall/request"
    sh "$SCRIPT_DIR/supervisor.sh" daemon >/dev/null 2>&1 &
}

control_command=${1:-status}
control_argument=${2:-}
case "$control_command" in
    start)
        ensure_dirs || exit 1
        rm -f "$AGH_STATE_DIR/core.disabled" "$AGH_STATE_DIR/paused" "$AGH_RUN_DIR/stop"
        sh "$SCRIPT_DIR/supervisor.sh" daemon >/dev/null 2>&1 &
        printf '%s\n' 'request=start'
        ;;
    set-mode) control_set_mode "$control_argument"; printf 'mode=%s\n' "$control_argument" ;;
    enable-proxy) control_set_adapter proxy true; printf '%s\n' 'request=enable-proxy' ;;
    disable-proxy) control_set_adapter proxy false; [ -x "$SCRIPT_DIR/../adapters/proxy-worker.sh" ] && "$SCRIPT_DIR/../adapters/proxy-worker.sh" --clean || true; printf '%s\n' 'request=disable-proxy' ;;
    enable-file) control_set_adapter file true; printf '%s\n' 'request=enable-file' ;;
    disable-file) control_set_adapter file false; [ -x "$SCRIPT_DIR/../adapters/file-worker.sh" ] && "$SCRIPT_DIR/../adapters/file-worker.sh" --clean || true; printf '%s\n' 'request=disable-file' ;;
    pause|resume|enable|disable|restart-core)
        ensure_dirs || exit 1
        control_request_dir="$AGH_RUN_DIR/control"
        mkdir -p "$control_request_dir"
        control_tmp="$control_request_dir/.$control_command.$$"
        printf '%s\n' "$control_command" > "$control_tmp"
        sync
        mv -f "$control_tmp" "$control_request_dir/$control_command"
        printf '%s\n' "request=$control_command"
        ;;
    status)
        if [ -f "$AGH_STATE_DIR/overall.state" ]; then
            cat "$AGH_STATE_DIR/overall.state"
        else
            printf '%s\n' 'overall=unknown'
        fi
        ;;
    *)
        printf 'usage: %s {start|pause|resume|enable|disable|restart-core|set-mode 1|2|3|status|enable-proxy|disable-proxy|enable-file|disable-file}\n' "$0" >&2
        exit 2
        ;;
esac
