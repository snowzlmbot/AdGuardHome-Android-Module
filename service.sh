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

if [ -x "$MODDIR/scripts/supervisor.sh" ]; then
    "$MODDIR/scripts/supervisor.sh" start >/dev/null 2>&1 &
else
    log_message service "supervisor.sh is not installed"
fi
