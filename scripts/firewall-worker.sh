#!/system/bin/sh

SCRIPT_DIR=${0%/*}
MODDIR=${MODDIR:-${SCRIPT_DIR%/*}}
export MODDIR
. "$SCRIPT_DIR/lib/common.sh"
. "$SCRIPT_DIR/lib/atomic.sh"
. "$SCRIPT_DIR/lib/process.sh"
. "$SCRIPT_DIR/lib/platform.sh"
. "$SCRIPT_DIR/lib/log.sh"

FW_V4_NAT=AGHADM4N
FW_V4_FILTER=AGHADF4
FW_V6_FILTER=AGHADF6

firewall_state_value() {
    firewall_state_file=$1
    firewall_state_key=$2
    sed -n "s/^${firewall_state_key}=//p" "$firewall_state_file" | sed -n '1p'
}

firewall_state_write() {
    firewall_state_value_name=$1
    firewall_reason=${2:-}
    firewall_tmp="$AGH_STATE_DIR/.firewall.state.$$"
    {
        printf 'state=%s\n' "$firewall_state_value_name"
        printf 'reason=%s\n' "$firewall_reason"
        printf 'v4_redirect=%s\n' "${FW_V4_REDIRECT:-false}"
        printf 'v6_dns_block=%s\n' "${FW_V6_DNS_BLOCK:-false}"
        printf 'dot_block=%s\n' "${FW_DOT_BLOCK:-false}"
    } > "$firewall_tmp"
    chmod 0600 "$firewall_tmp"
    sync
    mv -f "$firewall_tmp" "$AGH_STATE_DIR/firewall.state"
}

firewall_exec() {
    firewall_binary=$1
    shift
    if [ "${FIREWALL_NO_WAIT:-0}" = 1 ]; then
        "$firewall_binary" "$@"
    else
        "$firewall_binary" -w 2 "$@"
    fi
}

firewall_chain_exists() {
    firewall_binary=$1
    firewall_table=$2
    firewall_chain=$3
    firewall_exec "$firewall_binary" -t "$firewall_table" -L "$firewall_chain" >/dev/null 2>&1
}

firewall_remove_jump_all() {
    firewall_binary=$1
    firewall_table=$2
    firewall_chain=$3
    firewall_count=0
    while firewall_exec "$firewall_binary" -t "$firewall_table" -C OUTPUT -j "$firewall_chain" >/dev/null 2>&1; do
        firewall_exec "$firewall_binary" -t "$firewall_table" -D OUTPUT -j "$firewall_chain" >/dev/null 2>&1 || break
        firewall_count=$((firewall_count + 1))
        [ "$firewall_count" -lt 32 ] || break
    done
}

firewall_remove_chain() {
    firewall_binary=$1
    firewall_table=$2
    firewall_chain=$3
    firewall_remove_jump_all "$firewall_binary" "$firewall_table" "$firewall_chain"
    firewall_exec "$firewall_binary" -t "$firewall_table" -F "$firewall_chain" >/dev/null 2>&1 || true
    firewall_exec "$firewall_binary" -t "$firewall_table" -X "$firewall_chain" >/dev/null 2>&1 || true
}

firewall_remove() {
    firewall_binary_v4=${IPTABLES_BIN:-iptables}
    firewall_binary_v6=${IP6TABLES_BIN:-ip6tables}
    firewall_remove_chain "$firewall_binary_v4" nat "$FW_V4_NAT"
    firewall_remove_chain "$firewall_binary_v4" filter "$FW_V4_FILTER"
    firewall_remove_chain "$firewall_binary_v6" filter "$FW_V6_FILTER"
    firewall_state_write removed removed
}

firewall_config_value() {
    firewall_config_key=$1
    sed -n "s/^${firewall_config_key}=//p" "$AGH_CONFIG_DIR/mode.conf" 2>/dev/null | sed -n '1p'
}

firewall_ensure_chain() {
    firewall_binary=$1
    firewall_table=$2
    firewall_chain=$3
    firewall_exec "$firewall_binary" -t "$firewall_table" -N "$firewall_chain" >/dev/null 2>&1 || true
    firewall_exec "$firewall_binary" -t "$firewall_table" -F "$firewall_chain" >/dev/null 2>&1 || return 1
}

firewall_insert_jump() {
    firewall_binary=$1
    firewall_table=$2
    firewall_chain=$3
    if ! firewall_exec "$firewall_binary" -t "$firewall_table" -C OUTPUT -j "$firewall_chain" >/dev/null 2>&1; then
        firewall_exec "$firewall_binary" -t "$firewall_table" -I OUTPUT 1 -j "$firewall_chain" >/dev/null 2>&1 || return 1
    fi
}

firewall_read_core() {
    [ -f "$AGH_STATE_DIR/core.state" ] || return 1
    [ "$(firewall_state_value "$AGH_STATE_DIR/core.state" state)" = ready ] || return 1
    [ "$(firewall_state_value "$AGH_STATE_DIR/core.state" firewall_authorized)" = 1 ] || return 1
    FW_DNS_PORT=$(firewall_state_value "$AGH_STATE_DIR/core.state" dns_port)
    valid_port "$FW_DNS_PORT" || return 1
}

firewall_ensure() {
    firewall_read_core || { firewall_remove; firewall_state_write degraded core_not_ready; return 0; }
    firewall_binary_v4=${IPTABLES_BIN:-iptables}
    firewall_binary_v6=${IP6TABLES_BIN:-ip6tables}
    FW_V4_REDIRECT=$(firewall_config_value redirect_ipv4_dns); [ -n "$FW_V4_REDIRECT" ] || FW_V4_REDIRECT=true
    FW_V6_DNS_BLOCK=$(firewall_config_value redirect_ipv6_dns); [ -n "$FW_V6_DNS_BLOCK" ] || FW_V6_DNS_BLOCK=true
    FW_DOT_BLOCK=$(firewall_config_value block_ipv4_dot); [ -n "$FW_DOT_BLOCK" ] || FW_DOT_BLOCK=true
    FW_V6_DOT_BLOCK=$(firewall_config_value block_ipv6_dot); [ -n "$FW_V6_DOT_BLOCK" ] || FW_V6_DOT_BLOCK=true
    FW_V4_DOQ_BLOCK=$(firewall_config_value block_ipv4_doq); [ -n "$FW_V4_DOQ_BLOCK" ] || FW_V4_DOQ_BLOCK=true
    FW_V6_DOQ_BLOCK=$(firewall_config_value block_ipv6_doq); [ -n "$FW_V6_DOQ_BLOCK" ] || FW_V6_DOQ_BLOCK=true

    firewall_remove_jump_all "$firewall_binary_v4" nat "$FW_V4_NAT"
    firewall_remove_jump_all "$firewall_binary_v4" filter "$FW_V4_FILTER"
    firewall_remove_jump_all "$firewall_binary_v6" filter "$FW_V6_FILTER"
    firewall_ensure_chain "$firewall_binary_v4" nat "$FW_V4_NAT" || { firewall_remove; firewall_state_write degraded v4_nat_chain; return 1; }
    firewall_ensure_chain "$firewall_binary_v4" filter "$FW_V4_FILTER" || { firewall_remove; firewall_state_write degraded v4_filter_chain; return 1; }
    firewall_ensure_chain "$firewall_binary_v6" filter "$FW_V6_FILTER" || { firewall_remove; firewall_state_write degraded v6_filter_chain; return 1; }

    if [ "$FW_V4_REDIRECT" = true ]; then
        firewall_exec "$firewall_binary_v4" -t nat -A "$FW_V4_NAT" -p udp --dport 53 -j REDIRECT --to-ports "$FW_DNS_PORT" || { firewall_remove; firewall_state_write degraded v4_redirect; return 1; }
        firewall_exec "$firewall_binary_v4" -t nat -A "$FW_V4_NAT" -p tcp --dport 53 -j REDIRECT --to-ports "$FW_DNS_PORT" || { firewall_remove; firewall_state_write degraded v4_redirect; return 1; }
        firewall_insert_jump "$firewall_binary_v4" nat "$FW_V4_NAT" || { firewall_remove; firewall_state_write degraded v4_jump; return 1; }
    fi
    if [ "$FW_DOT_BLOCK" = true ] || [ "$FW_V4_DOQ_BLOCK" = true ]; then
        [ "$FW_DOT_BLOCK" = true ] && firewall_exec "$firewall_binary_v4" filter -A "$FW_V4_FILTER" -p tcp --dport 853 -j DROP
        [ "$FW_DOT_BLOCK" = true ] && firewall_exec "$firewall_binary_v4" filter -A "$FW_V4_FILTER" -p udp --dport 853 -j DROP
        [ "$FW_V4_DOQ_BLOCK" = true ] && firewall_exec "$firewall_binary_v4" filter -A "$FW_V4_FILTER" -p udp --dport 784 -j DROP
        firewall_insert_jump "$firewall_binary_v4" filter "$FW_V4_FILTER" || { firewall_remove; firewall_state_write degraded v4_filter_jump; return 1; }
    fi
    if [ "$FW_V6_DNS_BLOCK" = true ] || [ "$FW_V6_DOT_BLOCK" = true ] || [ "$FW_V6_DOQ_BLOCK" = true ]; then
        [ "$FW_V6_DNS_BLOCK" = true ] && firewall_exec "$firewall_binary_v6" filter -A "$FW_V6_FILTER" -p tcp --dport 53 -j DROP
        [ "$FW_V6_DNS_BLOCK" = true ] && firewall_exec "$firewall_binary_v6" filter -A "$FW_V6_FILTER" -p udp --dport 53 -j DROP
        [ "$FW_V6_DOT_BLOCK" = true ] && firewall_exec "$firewall_binary_v6" filter -A "$FW_V6_FILTER" -p tcp --dport 853 -j DROP
        [ "$FW_V6_DOT_BLOCK" = true ] && firewall_exec "$firewall_binary_v6" filter -A "$FW_V6_FILTER" -p udp --dport 853 -j DROP
        [ "$FW_V6_DOQ_BLOCK" = true ] && firewall_exec "$firewall_binary_v6" filter -A "$FW_V6_FILTER" -p udp --dport 784 -j DROP
        firewall_insert_jump "$firewall_binary_v6" filter "$FW_V6_FILTER" || { firewall_remove; firewall_state_write degraded v6_filter_jump; return 1; }
    fi
    firewall_state_write ready ready
}

firewall_once() {
    ensure_dirs || return 1
    mkdir -p "$AGH_RUN_DIR/firewall"
    if [ -f "$AGH_RUN_DIR/firewall/request" ] && grep -q '^remove$' "$AGH_RUN_DIR/firewall/request"; then
        rm -f "$AGH_RUN_DIR/firewall/request"
        firewall_remove
        return 0
    fi
    firewall_ensure
}

firewall_daemon() {
    while [ ! -f "$AGH_RUN_DIR/stop" ]; do
        firewall_once || log_message firewall 'firewall cycle failed'
        sleep 5
    done
    firewall_remove
}

case "${1:-once}" in
    once) firewall_once ;;
    daemon) firewall_daemon ;;
    stop) firewall_remove ;;
    *) printf 'usage: %s {once|daemon|stop}\n' "$0" >&2; exit 2 ;;
esac
