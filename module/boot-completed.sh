#!/system/bin/sh

MODDIR=${0%/*}
export MODDIR
. "$MODDIR/scripts/lib/common.sh"
ensure_dirs || exit 1

if [ -f "$MODDIR/scripts/lifecycle/supervisor.sh" ]; then
    agh_run_script "$MODDIR/scripts/lifecycle/supervisor.sh" daemon >>"$AGH_LOG_DIR/supervisor.log" 2>&1 &
fi
