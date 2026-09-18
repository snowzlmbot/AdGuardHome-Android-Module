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

command=${1:-status}
if [ -x "$MODDIR/scripts/supervisor.sh" ]; then
    "$MODDIR/scripts/supervisor.sh" "$command"
else
    log_message action "supervisor.sh is not installed"
    exit 1
fi
