#!/system/bin/sh

SCRIPT_DIR=${0%/*}
MODDIR=${MODDIR:-${SCRIPT_DIR%/*}}
export MODDIR
. "$SCRIPT_DIR/lib/common.sh"
. "$SCRIPT_DIR/lib/atomic.sh"
. "$SCRIPT_DIR/lib/log.sh"

control_command=${1:-status}
case "$control_command" in
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
