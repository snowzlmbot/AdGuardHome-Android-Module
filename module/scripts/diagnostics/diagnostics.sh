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

diagnostics_config_value() {
    diagnostics_key=$1
    [ -f "$AGH_CONFIG_DIR/file-adapter.conf" ] || return 0
    sed -n "s/^${diagnostics_key}=//p" "$AGH_CONFIG_DIR/file-adapter.conf" 2>/dev/null | sed -n '1p'
}

diagnostics_redact() {
    sed -E \
        -e 's/(password|passwd|token|authorization|cookie|secret)([=:[:space:]]+)[^[:space:]]+/\1\2[REDACTED]/Ig' \
        -e 's#(https?://)[^/@[:space:]]+:[^/@[:space:]]+@#\1[REDACTED]@#g'
}

diagnostics_logs() {
    diagnostics_lines=${DIAGNOSTICS_LOG_LINES:-80}
    for diagnostics_log in core-process.log events.log supervisor.log network-worker.log firewall-worker.log proxy-worker.log file-worker.log; do
        diagnostics_path="$AGH_LOG_DIR/$diagnostics_log"
        [ -f "$diagnostics_path" ] || continue
        printf '\n===== %s =====\n' "$diagnostics_log"
        tail -n "$diagnostics_lines" "$diagnostics_path" 2>/dev/null | diagnostics_redact
    done
}

if [ "${1:-status}" = logs ]; then
    diagnostics_logs
    exit 0
fi

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
diagnostics_querylog_file="$AGH_DATA_DIR/data/querylog.json"
diagnostics_querylog_bytes=0
diagnostics_querylog_age=-1
if [ -f "$diagnostics_querylog_file" ]; then
    diagnostics_querylog_bytes=$(wc -c < "$diagnostics_querylog_file" 2>/dev/null || printf 0)
    diagnostics_querylog_mtime=$(stat -c '%Y' "$diagnostics_querylog_file" 2>/dev/null || stat -f '%m' "$diagnostics_querylog_file" 2>/dev/null || printf 0)
    diagnostics_querylog_now=$(date +%s 2>/dev/null || printf 0)
    case "$diagnostics_querylog_mtime:$diagnostics_querylog_now" in
        *[!0-9:]*|:*) diagnostics_querylog_age=-1 ;;
        *) diagnostics_querylog_age=$((diagnostics_querylog_now - diagnostics_querylog_mtime)); [ "$diagnostics_querylog_age" -lt 0 ] && diagnostics_querylog_age=0 ;;
    esac
fi
if [ "$diagnostics_querylog_bytes" -gt 0 ] && [ "$diagnostics_querylog_age" -ge 0 ] && [ "$diagnostics_querylog_age" -le 600 ]; then
    diagnostics_querylog_state=ready
elif [ "$diagnostics_querylog_bytes" -gt 0 ]; then
    diagnostics_querylog_state=stale
else
    diagnostics_querylog_state=empty
fi

printf 'status=%s\n' "$diagnostics_status"
printf 'language=%s\n' "$MODULE_LANG"
printf 'mode=%s\n' "$diagnostics_mode"
printf 'mode_name=%s\n' "$diagnostics_mode_name"
printf 'paused=%s\n' "$( [ -f "$AGH_STATE_DIR/paused" ] && printf true || printf false )"
printf 'proxy_enabled=%s\n' "$( grep -q '^enabled=true$' "$AGH_CONFIG_DIR/proxy-adapter.conf" 2>/dev/null && printf true || printf false )"
printf 'file_enabled=%s\n' "$( grep -q '^enabled=true$' "$AGH_CONFIG_DIR/file-adapter.conf" 2>/dev/null && printf true || printf false )"
printf 'ipv6_dns_block=%s\n' "$( sed -n 's/^redirect_ipv6_dns=//p' "$AGH_CONFIG_DIR/mode.conf" 2>/dev/null | sed -n '1p' )"
printf 'dot_block=%s\n' "$( sed -n 's/^block_ipv4_dot=//p' "$AGH_CONFIG_DIR/mode.conf" 2>/dev/null | sed -n '1p' )"
printf 'doq_block=%s\n' "$( sed -n 's/^block_ipv4_doq=//p' "$AGH_CONFIG_DIR/mode.conf" 2>/dev/null | sed -n '1p' )"
printf 'vpn_passthrough=%s\n' "$( sed -n 's/^bypass_vpn_traffic=//p' "$AGH_CONFIG_DIR/mode.conf" 2>/dev/null | sed -n '1p' )"
printf 'web_url=%s\n' "$( [ "$diagnostics_core_state" = ready ] && [ -n "$diagnostics_web_port" ] && printf 'http://127.0.0.1:%s' "$diagnostics_web_port" || printf unavailable )"
printf 'username=admin\n'
printf 'filters=%s\n' "$diagnostics_filter_state"
printf 'filter_count=%s\n' "$diagnostics_filter_count"
printf 'filter_bytes=%s\n' "$diagnostics_filter_bytes"
printf 'querylog=%s\n' "$diagnostics_querylog_state"
printf 'querylog_bytes=%s\n' "$diagnostics_querylog_bytes"
printf 'querylog_age=%s\n' "$diagnostics_querylog_age"

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
diagnostics_file_rules_url=$(state_value "$diagnostics_file" url)
[ -n "$diagnostics_file_rules_url" ] || diagnostics_file_rules_url=$(diagnostics_config_value rules_url)
[ -n "$diagnostics_file_rules_url" ] || diagnostics_file_rules_url='https://raw.githubusercontent.com/snowzlmbot/AdGuardHome-Android-Module/main/module/targets/file-ad-targets.conf'
diagnostics_file_rules_sha_url=$(state_value "$diagnostics_file" sha256_url)
[ -n "$diagnostics_file_rules_sha_url" ] || diagnostics_file_rules_sha_url=$(diagnostics_config_value rules_sha256_url)
[ -n "$diagnostics_file_rules_sha_url" ] || diagnostics_file_rules_sha_url='https://raw.githubusercontent.com/snowzlmbot/AdGuardHome-Android-Module/main/module/targets/file-ad-targets.conf.sha256'
diagnostics_file_rules_view_url=$(state_value "$diagnostics_file" view_url)
[ -n "$diagnostics_file_rules_view_url" ] || diagnostics_file_rules_view_url="$diagnostics_file_rules_url"
printf 'file_reason=%s\n' "$(state_value "$diagnostics_file" reason || printf unknown)"
printf 'file_rules_state=%s\n' "$(state_value "$diagnostics_file" rules_state || printf unknown)"
printf 'file_rules_sha256=%s\n' "$(state_value "$diagnostics_file" rules_sha256 || printf unknown)"
printf 'file_rules_url=%s\n' "$diagnostics_file_rules_url"
printf 'file_rules_sha256_url=%s\n' "$diagnostics_file_rules_sha_url"
printf 'file_rules_view_url=%s\n' "$diagnostics_file_rules_view_url"
printf 'file_package_filter=%s\n' "$(state_value "$diagnostics_file" package_filter || printf all)"
printf 'file_targets_total=%s\n' "$(state_value "$diagnostics_file" targets_total || printf 0)"
printf 'file_targets_installed=%s\n' "$(state_value "$diagnostics_file" targets_installed || printf 0)"
printf 'file_targets_applied=%s\n' "$(state_value "$diagnostics_file" targets_applied || printf 0)"
printf 'file_targets_missing=%s\n' "$(state_value "$diagnostics_file" targets_missing || printf 0)"
printf 'file_targets_changed=%s\n' "$(state_value "$diagnostics_file" targets_changed || printf 0)"
printf 'file_targets_blocked=%s\n' "$(state_value "$diagnostics_file" targets_blocked || printf 0)"
