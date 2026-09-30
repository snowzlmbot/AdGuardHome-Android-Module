#!/system/bin/sh

MODDIR=${0%/*}
export MODDIR

if [ -f "$MODDIR/scripts/lib/common.sh" ]; then
    . "$MODDIR/scripts/lib/common.sh"
fi

if [ -f "$MODDIR/scripts/lib/log.sh" ]; then
    . "$MODDIR/scripts/lib/log.sh"
fi

if command -v ensure_dirs >/dev/null 2>&1; then
    ensure_dirs
fi

if [ -f "$MODDIR/scripts/lifecycle/supervisor.sh" ]; then
    agh_run_script "$MODDIR/scripts/lifecycle/supervisor.sh" daemon >>"$AGH_LOG_DIR/supervisor.log" 2>&1 &
else
    log_message service "supervisor.sh is not installed"
fi
