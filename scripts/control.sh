#!/system/bin/sh

SCRIPT_DIR=${0%/*}
MODDIR=${MODDIR:-${SCRIPT_DIR%/*}}
export MODDIR
. "$SCRIPT_DIR/lib/common.sh"
. "$SCRIPT_DIR/lib/atomic.sh"
. "$SCRIPT_DIR/lib/log.sh"

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

control_command=${1:-status}
case "$control_command" in
    enable-proxy) control_set_adapter proxy true; printf '%s\n' 'request=enable-proxy' ;;
    disable-proxy) control_set_adapter proxy false; [ -x "$SCRIPT_DIR/adapters/proxy-worker.sh" ] && "$SCRIPT_DIR/adapters/proxy-worker.sh" --clean || true; printf '%s\n' 'request=disable-proxy' ;;
    enable-file) control_set_adapter file true; printf '%s\n' 'request=enable-file' ;;
    disable-file) control_set_adapter file false; [ -x "$SCRIPT_DIR/adapters/file-worker.sh" ] && "$SCRIPT_DIR/adapters/file-worker.sh" --clean || true; printf '%s\n' 'request=disable-file' ;;
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
        printf 'usage: %s {pause|resume|enable|disable|restart-core|status}\n' "$0" >&2
        exit 2
        ;;
esac
