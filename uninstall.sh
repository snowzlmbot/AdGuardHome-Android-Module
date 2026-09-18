#!/system/bin/sh

MODDIR=${0%/*}
export MODDIR
. "$MODDIR/scripts/lib/common.sh"
. "$MODDIR/scripts/lib/log.sh"

AGH_UNINSTALL_REPORT=${AGH_UNINSTALL_REPORT:-/data/adb/agh-uninstall-report.log}
uninstall_warning=0
mkdir -p "${AGH_UNINSTALL_REPORT%/*}"

if [ -x "$MODDIR/scripts/lifecycle/supervisor.sh" ]; then
    "$MODDIR/scripts/lifecycle/supervisor.sh" stop >/dev/null 2>&1 || uninstall_warning=1
fi
if [ -x "$MODDIR/scripts/core/core-worker.sh" ]; then
    "$MODDIR/scripts/core/core-worker.sh" stop >/dev/null 2>&1 || uninstall_warning=1
fi
if [ -x "$MODDIR/scripts/lifecycle/restore.sh" ]; then
    "$MODDIR/scripts/lifecycle/restore.sh" >/dev/null 2>&1 || uninstall_warning=1
fi

if [ -d "$AGH_ROOT" ]; then
    log_message uninstall "module cleanup started"
    rm -rf "$AGH_ROOT" || uninstall_warning=1
fi
{
    printf 'completed=true\n'
    printf 'warning=%s\n' "$uninstall_warning"
    printf 'data_removed=%s\n' "$( [ ! -e "$AGH_ROOT" ] && printf true || printf false )"
} > "$AGH_UNINSTALL_REPORT"
chmod 0600 "$AGH_UNINSTALL_REPORT"
exit 0
