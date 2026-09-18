#!/system/bin/sh

SCRIPT_DIR=${0%/*}
MODDIR=${MODDIR:-${SCRIPT_DIR%/*}}
export MODDIR
. "$SCRIPT_DIR/lib/common.sh"
. "$SCRIPT_DIR/lib/platform.sh"
. "$SCRIPT_DIR/lib/log.sh"

state_value() {
    diagnostics_file=$1
    diagnostics_key=$2
    sed -n "s/^${diagnostics_key}=//p" "$diagnostics_file" 2>/dev/null | sed -n '1p'
}

detect_arch >/dev/null 2>&1 || AGH_ARCH=unsupported
diagnostics_core="$AGH_STATE_DIR/core.state"
diagnostics_firewall="$AGH_STATE_DIR/firewall.state"
diagnostics_network="$AGH_STATE_DIR/network.state"
diagnostics_proxy="$AGH_STATE_DIR/proxy.state"
diagnostics_file="$AGH_STATE_DIR/file.state"

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
