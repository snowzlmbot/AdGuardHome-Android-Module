#!/system/bin/sh

SCRIPT_DIR=${0%/*}
MODULE_SCRIPTS_DIR=${SCRIPT_DIR%/*}
MODDIR=${MODDIR:-${MODULE_SCRIPTS_DIR%/*}}
export MODDIR
. "$MODULE_SCRIPTS_DIR/lib/common.sh"
. "$MODULE_SCRIPTS_DIR/lib/platform.sh"
. "$MODULE_SCRIPTS_DIR/lib/log.sh"
. "$MODULE_SCRIPTS_DIR/lib/i18n.sh"

state_value() {
    diagnostics_file=$1
    diagnostics_key=$2
    sed -n "s/^${diagnostics_key}=//p" "$diagnostics_file" 2>/dev/null | sed -n '1p'
}

detect_arch >/dev/null 2>&1 || AGH_ARCH=unsupported
module_detect_language || MODULE_LANG=en
diagnostics_core="$AGH_STATE_DIR/core.state"
diagnostics_firewall="$AGH_STATE_DIR/firewall.state"
diagnostics_network="$AGH_STATE_DIR/network.state"
diagnostics_proxy="$AGH_STATE_DIR/proxy.state"
diagnostics_file="$AGH_STATE_DIR/file.state"
diagnostics_mode=$(sed -n 's/^mode=//p' "$AGH_CONFIG_DIR/mode.conf" 2>/dev/null | sed -n '1p')
case "$diagnostics_mode" in
    1) diagnostics_mode_name='内网兼容' ;;
    2) diagnostics_mode_name='纯加密上游' ;;
    3) diagnostics_mode_name='Bootstrap' ;;
    *) diagnostics_mode_name='未知' ;;
esac
diagnostics_core_state=$(state_value "$diagnostics_core" state || printf unknown)
diagnostics_firewall_state=$(state_value "$diagnostics_firewall" state || printf unknown)
if [ -f "$AGH_STATE_DIR/paused" ]; then
    diagnostics_status=paused
elif [ -f "$AGH_STATE_DIR/core.disabled" ]; then
    diagnostics_status=stopped
elif [ "$diagnostics_core_state" = ready ] && [ "$diagnostics_firewall_state" = ready ]; then
    diagnostics_status=running
elif [ "$diagnostics_core_state" = ready ]; then
    diagnostics_status=degraded
else
    diagnostics_status=failed
fi
diagnostics_web_port=$(sed -n 's/^web_port=//p' "$AGH_STATE_DIR/ports.conf" 2>/dev/null | sed -n '1p')
diagnostics_filter_dir="$AGH_DATA_DIR/data/filters"
diagnostics_filter_count=0
diagnostics_filter_bytes=0
if [ -d "$diagnostics_filter_dir" ]; then
    for diagnostics_filter in "$diagnostics_filter_dir"/[0-9]*.txt; do
        [ -s "$diagnostics_filter" ] || continue
        diagnostics_filter_count=$((diagnostics_filter_count + 1))
        diagnostics_filter_size=$(wc -c < "$diagnostics_filter" 2>/dev/null || printf 0)
        diagnostics_filter_bytes=$((diagnostics_filter_bytes + diagnostics_filter_size))
    done
fi
if [ "$diagnostics_filter_count" -gt 0 ]; then diagnostics_filter_state=ready
elif [ "$diagnostics_core_state" = ready ]; then diagnostics_filter_state=loading
else diagnostics_filter_state=unavailable; fi

printf 'status=%s\n' "$diagnostics_status"
printf 'language=%s\n' "$MODULE_LANG"
printf 'mode=%s\n' "$diagnostics_mode"
printf 'mode_name=%s\n' "$diagnostics_mode_name"
printf 'paused=%s\n' "$( [ -f "$AGH_STATE_DIR/paused" ] && printf true || printf false )"
printf 'proxy_enabled=%s\n' "$( grep -q '^enabled=true$' "$AGH_CONFIG_DIR/proxy-adapter.conf" 2>/dev/null && printf true || printf false )"
printf 'file_enabled=%s\n' "$( grep -q '^enabled=true$' "$AGH_CONFIG_DIR/file-adapter.conf" 2>/dev/null && printf true || printf false )"
printf 'web_url=%s\n' "$( [ "$diagnostics_core_state" = ready ] && [ -n "$diagnostics_web_port" ] && printf 'http://127.0.0.1:%s' "$diagnostics_web_port" || printf unavailable )"
printf 'username=admin\n'
printf 'filters=%s\n' "$diagnostics_filter_state"
printf 'filter_count=%s\n' "$diagnostics_filter_count"
printf 'filter_bytes=%s\n' "$diagnostics_filter_bytes"

printf 'arch=%s\n' "$AGH_ARCH"
printf 'core=%s\n' "$(state_value "$diagnostics_core" state || printf unknown)"
printf 'core_pid_present=%s\n' "$( [ -f "$AGH_RUN_DIR/core.pid" ] && printf true || printf false )"
printf 'firewall=%s\n' "$(state_value "$diagnostics_firewall" state || printf unknown)"
printf 'network=%s\n' "$(state_value "$diagnostics_network" state || printf unknown)"
printf 'proxy=%s\n' "$(state_value "$diagnostics_proxy" state || printf disabled)"
printf 'file_adapter=%s\n' "$(state_value "$diagnostics_file" state || printf disabled)"
printf 'web_port=%s\n' "$(sed -n 's/^web_port=//p' "$AGH_STATE_DIR/ports.conf" 2>/dev/null | sed -n '1p')"
printf 'dns_port=%s\n' "$(sed -n 's/^dns_port=//p' "$AGH_STATE_DIR/ports.conf" 2>/dev/null | sed -n '1p')"
printf 'firewall_reason=%s\n' "$(state_value "$diagnostics_firewall" reason || printf unknown)"
printf 'core_reason=%s\n' "$(state_value "$diagnostics_core" reason || printf unknown)"
printf 'core_retry_in=%s\n' "$(state_value "$diagnostics_core" retry_in || printf 0)"
printf 'network_reason=%s\n' "$(state_value "$diagnostics_network" reason || printf unknown)"
printf 'proxy_reason=%s\n' "$(state_value "$diagnostics_proxy" reason || printf unknown)"
printf 'file_reason=%s\n' "$(state_value "$diagnostics_file" reason || printf unknown)"
