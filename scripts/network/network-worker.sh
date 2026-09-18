#!/system/bin/sh

SCRIPT_DIR=${0%/*}
MODULE_SCRIPTS_DIR=${SCRIPT_DIR%/*}
MODDIR=${MODDIR:-${MODULE_SCRIPTS_DIR%/*}}
export MODDIR
. "$MODULE_SCRIPTS_DIR/lib/common.sh"
. "$MODULE_SCRIPTS_DIR/lib/atomic.sh"
. "$MODULE_SCRIPTS_DIR/lib/log.sh"

network_state_write() {
    network_state_value=$1
    network_reason=${2:-}
    network_tmp="$AGH_STATE_DIR/.network.state.$$"
    {
        printf 'state=%s\n' "$network_state_value"
        printf 'mode=%s\n' "${NETWORK_MODE:-2}"
        printf 'network=%s\n' "${NETWORK_TYPE:-none}"
        printf 'vpn=%s\n' "${NETWORK_VPN:-false}"
        printf 'dns4=%s\n' "${NETWORK_DNS4:-}"
        printf 'dns6=%s\n' "${NETWORK_DNS6:-}"
        printf 'reason=%s\n' "$network_reason"
    } > "$network_tmp"
    chmod 0600 "$network_tmp"
    sync
    mv -f "$network_tmp" "$AGH_STATE_DIR/network.state"
}

network_value() {
    network_file=$1
    network_key=$2
    sed -n "s/^${network_key}=//p" "$network_file" | sed -n '1p'
}

network_valid_ip_list() {
    network_list=$1
    [ -z "$network_list" ] && return 0
    network_old_ifs=$IFS
    IFS=,
    for network_address in $network_list; do
        [ -n "$network_address" ] || { IFS=$network_old_ifs; return 1; }
        case "$network_address" in
            *[!0-9a-fA-F:.]*) IFS=$network_old_ifs; return 1 ;;
            *[.:]*) ;;
            *) IFS=$network_old_ifs; return 1 ;;
        esac
    done
    IFS=$network_old_ifs
    return 0
}

network_read_android() {
    network_connectivity=$(dumpsys connectivity 2>/dev/null) || return 1
    if printf '%s\n' "$network_connectivity" | grep -q 'type: WIFI'; then
        NETWORK_TYPE=wifi
    elif printf '%s\n' "$network_connectivity" | grep -q 'type: MOBILE'; then
        NETWORK_TYPE=mobile
    elif printf '%s\n' "$network_connectivity" | grep -q 'type: ETHERNET'; then
        NETWORK_TYPE=ethernet
    else
        NETWORK_TYPE=none
    fi
    if printf '%s\n' "$network_connectivity" | grep -q 'type: VPN'; then
        NETWORK_VPN=true
    else
        NETWORK_VPN=false
    fi
    network_dns_line=$(printf '%s\n' "$network_connectivity" | sed -n 's/.*DnsAddresses: \[\([^]]*\)\].*/\1/p' | sed -n '1p' | tr -d ' ')
    network_dns_tokens=$(printf '%s\n' "$network_dns_line" | tr ',' '\n')
    NETWORK_DNS4=$(printf '%s\n' "$network_dns_tokens" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | awk 'BEGIN{first=1}{if(!first)printf ","; printf "%s",$0; first=0}END{if(!first)printf "\n"}')
    NETWORK_DNS6=$(printf '%s\n' "$network_dns_tokens" | grep ':' | awk 'BEGIN{first=1}{if(!first)printf ","; printf "%s",$0; first=0}END{if(!first)printf "\n"}')
}

network_read_snapshot() {
    network_snapshot=${NETWORK_SNAPSHOT_FILE:-}
    network_tmp="$AGH_RUN_DIR/network.snapshot.$$"
    if [ -n "$network_snapshot" ] && [ -f "$network_snapshot" ]; then
        cp "$network_snapshot" "$network_tmp" || return 1
    elif [ -n "${NETWORK_DISCOVERY_CMD:-}" ]; then
        sh -c "$NETWORK_DISCOVERY_CMD" > "$network_tmp" 2>/dev/null || return 1
    elif command -v dumpsys >/dev/null 2>&1; then
        network_read_android || return 1
        rm -f "$network_tmp"
        return 0
    else
        return 1
    fi
    NETWORK_TYPE=$(network_value "$network_tmp" network)
    NETWORK_VPN=$(network_value "$network_tmp" vpn)
    NETWORK_DNS4=$(network_value "$network_tmp" dns4)
    NETWORK_DNS6=$(network_value "$network_tmp" dns6)
    rm -f "$network_tmp"
}

network_load_mode() {
    NETWORK_MODE=$(sed -n 's/^mode=//p' "$AGH_CONFIG_DIR/mode.conf" 2>/dev/null | sed -n '1p')
    [ -n "$NETWORK_MODE" ] || NETWORK_MODE=2
    case "$NETWORK_MODE" in 1|2|3) return 0 ;; *) return 1 ;; esac
}

network_once() {
    ensure_dirs || return 1
    network_load_mode || { network_state_write degraded invalid_mode; return 1; }
    if ! network_read_snapshot; then
        network_state_write degraded discovery_failed
        return 1
    fi
    case "$NETWORK_TYPE" in wifi|mobile|ethernet|none) ;; *) network_state_write degraded invalid_network_type; return 1 ;; esac
    case "$NETWORK_VPN" in true|false) ;; *) network_state_write degraded invalid_vpn; return 1 ;; esac
    network_valid_ip_list "$NETWORK_DNS4" || { network_state_write degraded invalid_dns4; return 1; }
    network_valid_ip_list "$NETWORK_DNS6" || { network_state_write degraded invalid_dns6; return 1; }
    if [ "$NETWORK_TYPE" = none ]; then
        network_state_write degraded no_network
        return 1
    fi
    network_state_write ready ready
    cp "$AGH_STATE_DIR/network.state" "$AGH_STATE_DIR/network.lastgood"
    chmod 0600 "$AGH_STATE_DIR/network.lastgood"
}

network_daemon() {
    while [ ! -f "$AGH_RUN_DIR/stop" ]; do
        network_once || log_message network 'network state degraded'
        sleep 5
    done
}

case "${1:-once}" in
    once) network_once ;;
    daemon) network_daemon ;;
    stop) rm -f "$AGH_STATE_DIR/network.state" ;;
    *) printf 'usage: %s {once|daemon|stop}\n' "$0" >&2; exit 2 ;;
esac
