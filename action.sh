#!/system/bin/sh

MODDIR=${0%/*}
export MODDIR

. "$MODDIR/scripts/lib/common.sh"
. "$MODDIR/scripts/lib/platform.sh"
. "$MODDIR/scripts/lib/log.sh"
ensure_dirs || exit 1

command=${1:-status}
control="$MODDIR/scripts/control.sh"

case "$command" in
    status|pause|resume|enable|disable|restart-core|enable-proxy|disable-proxy|enable-file|disable-file)
        exec "$control" "$command"
        ;;
    open)
        action_web_port=$(sed -n 's/^web_port=//p' "$AGH_STATE_DIR/ports.conf" 2>/dev/null | sed -n '1p')
        valid_port "$action_web_port" 2>/dev/null || { printf '%s\n' 'Web UI port is unavailable' >&2; exit 1; }
        if command -v am >/dev/null 2>&1; then
            am start -a android.intent.action.VIEW -d "http://127.0.0.1:$action_web_port"
        else
            printf 'http://127.0.0.1:%s\n' "$action_web_port"
        fi
        ;;
    *)
        printf 'usage: %s {status|open|pause|resume|enable|disable|restart-core|enable-proxy|disable-proxy|enable-file|disable-file}\n' "$0" >&2
        exit 2
        ;;
esac
