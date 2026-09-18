#!/system/bin/sh

MODDIR=${0%/*}
export MODDIR

if [ -f "$MODDIR/scripts/lib/common.sh" ]; then
    . "$MODDIR/scripts/lib/common.sh"
fi
if [ -f "$MODDIR/scripts/lib/log.sh" ]; then
    . "$MODDIR/scripts/lib/log.sh"
fi

if [ -x "$MODDIR/scripts/supervisor.sh" ]; then
    "$MODDIR/scripts/supervisor.sh" stop >/dev/null 2>&1
fi
if [ -x "$MODDIR/scripts/firewall-worker.sh" ]; then
    "$MODDIR/scripts/firewall-worker.sh" remove >/dev/null 2>&1
fi
if [ -x "$MODDIR/scripts/adapters/proxy-worker.sh" ]; then
    "$MODDIR/scripts/adapters/proxy-worker.sh" restore >/dev/null 2>&1
fi
if [ -x "$MODDIR/scripts/adapters/file-worker.sh" ]; then
    "$MODDIR/scripts/adapters/file-worker.sh" restore >/dev/null 2>&1
fi

log_message uninstall "module cleanup requested"
