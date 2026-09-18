#!/system/bin/sh

SCRIPT_DIR=${0%/*}
MODULE_SCRIPTS_DIR=${SCRIPT_DIR%/*}
MODDIR=${MODDIR:-${MODULE_SCRIPTS_DIR%/*}}
export MODDIR
. "$MODULE_SCRIPTS_DIR/lib/common.sh"
. "$MODULE_SCRIPTS_DIR/lib/atomic.sh"
. "$MODULE_SCRIPTS_DIR/lib/log.sh"

restore_all() {
    RESTORE_WARNING=0
    [ -x "$SCRIPT_DIR/../adapters/proxy-worker.sh" ] && "$SCRIPT_DIR/../adapters/proxy-worker.sh" --clean >/dev/null 2>&1 || true
    [ -x "$SCRIPT_DIR/../adapters/file-worker.sh" ] && "$SCRIPT_DIR/../adapters/file-worker.sh" --clean >/dev/null 2>&1 || true
    [ "$(sed -n 's/^state=//p' "$AGH_STATE_DIR/proxy.state" 2>/dev/null | sed -n '1p')" = warning ] && RESTORE_WARNING=1
    [ "$(sed -n 's/^state=//p' "$AGH_STATE_DIR/file.state" 2>/dev/null | sed -n '1p')" = warning ] && RESTORE_WARNING=1
    [ -x "$SCRIPT_DIR/../firewall/firewall-worker.sh" ] && "$SCRIPT_DIR/../firewall/firewall-worker.sh" stop >/dev/null 2>&1 || true
    return 0
}

restore_all
