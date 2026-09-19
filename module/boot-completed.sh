#!/system/bin/sh

MODDIR=${0%/*}
export MODDIR

if [ -x "$MODDIR/scripts/lifecycle/supervisor.sh" ]; then
    "$MODDIR/scripts/lifecycle/supervisor.sh" daemon >/dev/null 2>&1 &
fi
