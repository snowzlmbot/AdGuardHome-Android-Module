#!/system/bin/sh

MODDIR=${0%/*}
export MODDIR

if [ -x "$MODDIR/scripts/supervisor.sh" ]; then
    "$MODDIR/scripts/supervisor.sh" boot-completed >/dev/null 2>&1 &
fi
