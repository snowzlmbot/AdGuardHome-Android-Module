#!/system/bin/sh

SCRIPT_DIR=${0%/*}
MODULE_SCRIPTS_DIR=${SCRIPT_DIR%/*}
MODDIR=${MODDIR:-${MODULE_SCRIPTS_DIR%/*}}
export MODDIR
. "$MODULE_SCRIPTS_DIR/lib/common.sh"
. "$MODULE_SCRIPTS_DIR/lib/atomic.sh"
. "$MODULE_SCRIPTS_DIR/lib/process.sh"
. "$MODULE_SCRIPTS_DIR/lib/platform.sh"
. "$MODULE_SCRIPTS_DIR/lib/log.sh"

FW_V4_NAT=AGHADM4N
FW_V4_FILTER=AGHADF4
FW_V6_NAT=AGHADM6N
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
        printf 'mode=%s\n' "${FW_NETWORK_MODE:-unknown}"
        printf 'network=%s\n' "${FW_NETWORK_TYPE:-unknown}"
        printf 'vpn=%s\n' "${FW_NETWORK_VPN:-unknown}"
        printf 'v4_redirect=%s\n' "${FW_V4_REDIRECT:-false}"
        printf 'v6_redirect=%s\n' "${FW_V6_REDIRECT:-false}"
        # Legacy status field: IPv6 DNS is never replaced by DROP.
        printf 'v6_dns_block=false\n'
        printf 'dot_block=%s\n' "${FW_DOT_BLOCK:-false}"
        printf 'v6_dot_block=%s\n' "${FW_V6_DOT_BLOCK:-false}"
        printf 'doq_block=%s\n' "${FW_DOQ_BLOCK:-false}"
        printf 'v6_doq_block=%s\n' "${FW_V6_DOQ_BLOCK:-false}"
    } > "$firewall_tmp" || return 1
    chmod 0600 "$firewall_tmp"
    agh_sync
    agh_move "$firewall_tmp" "$AGH_STATE_DIR/firewall.state"
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
    firewall_delete_binary=$1
    firewall_delete_table=$2
    firewall_delete_chain=$3
    firewall_delete_count=0
    while firewall_exec "$firewall_delete_binary" -t "$firewall_delete_table" -C OUTPUT -j "$firewall_delete_chain" >/dev/null 2>&1; do
        firewall_exec "$firewall_delete_binary" -t "$firewall_delete_table" -D OUTPUT -j "$firewall_delete_chain" >/dev/null 2>&1 || return 1
        firewall_delete_count=$((firewall_delete_count + 1))
        # Bound a broken/no-op iptables wrapper rather than claim removal.
        if [ "$firewall_delete_count" -ge 32 ]; then
            if firewall_exec "$firewall_delete_binary" -t "$firewall_delete_table" -C OUTPUT -j "$firewall_delete_chain" >/dev/null 2>&1; then return 1; fi
            return 0
        fi
    done
    return 0
}

firewall_remove_chain() {
    firewall_cleanup_binary=$1
    firewall_cleanup_table=$2
    firewall_cleanup_chain=$3
    firewall_cleanup_failed=0
    firewall_remove_jump_all "$firewall_cleanup_binary" "$firewall_cleanup_table" "$firewall_cleanup_chain" || firewall_cleanup_failed=1
    if firewall_chain_exists "$firewall_cleanup_binary" "$firewall_cleanup_table" "$firewall_cleanup_chain"; then
        firewall_exec "$firewall_cleanup_binary" -t "$firewall_cleanup_table" -F "$firewall_cleanup_chain" >/dev/null 2>&1 || firewall_cleanup_failed=1
        firewall_exec "$firewall_cleanup_binary" -t "$firewall_cleanup_table" -X "$firewall_cleanup_chain" >/dev/null 2>&1 || firewall_cleanup_failed=1
        if firewall_chain_exists "$firewall_cleanup_binary" "$firewall_cleanup_table" "$firewall_cleanup_chain"; then firewall_cleanup_failed=1; fi
    fi
    [ "$firewall_cleanup_failed" = 0 ]
}

firewall_remove_v4() {
    command -v "$firewall_binary_v4" >/dev/null 2>&1 || return 1
    firewall_cleanup_v4_failed=0
    firewall_remove_chain "$firewall_binary_v4" nat "$FW_V4_NAT" || firewall_cleanup_v4_failed=1
    firewall_remove_chain "$firewall_binary_v4" filter "$FW_V4_FILTER" || firewall_cleanup_v4_failed=1
    [ "$firewall_cleanup_v4_failed" = 0 ]
}

firewall_remove_v6() {
    # IPv6 tooling is optional and may not exist on the device at all.
    command -v "$firewall_binary_v6" >/dev/null 2>&1 || return 0
    firewall_cleanup_v6_failed=0
    firewall_remove_chain "$firewall_binary_v6" nat "$FW_V6_NAT" || firewall_cleanup_v6_failed=1
    firewall_remove_chain "$firewall_binary_v6" filter "$FW_V6_FILTER" || firewall_cleanup_v6_failed=1
    [ "$firewall_cleanup_v6_failed" = 0 ]
}

firewall_remove() {
    firewall_binary_v4=${IPTABLES_BIN:-iptables}
    firewall_binary_v6=${IP6TABLES_BIN:-ip6tables}
    FW_V4_REDIRECT=false
    FW_V6_REDIRECT=false
    FW_DOT_BLOCK=false
    FW_V6_DOT_BLOCK=false
    FW_DOQ_BLOCK=false
    FW_V6_DOQ_BLOCK=false
    firewall_cleanup_all_failed=0
    firewall_remove_v4 || firewall_cleanup_all_failed=1
    firewall_remove_v6 || firewall_cleanup_all_failed=1
    if [ "$firewall_cleanup_all_failed" != 0 ]; then
        firewall_state_write degraded remove_failed
        return 1
    fi
    firewall_state_write removed removed
}

firewall_config_value() {
    firewall_config_key=$1
    sed -n "s/^${firewall_config_key}=//p" "$AGH_CONFIG_DIR/mode.conf" 2>/dev/null | sed -n '1p'
}

firewall_option() {
    firewall_option_value=$(firewall_config_value "$1")
    [ -n "$firewall_option_value" ] || firewall_option_value=$2
    case "$firewall_option_value" in true) printf true ;; *) printf false ;; esac
}

firewall_ensure_chain() {
    # -N failing is normal only for an existing chain. Never ignore capability
    # failures or flush/rewrite a built-in or another module's chain.
    firewall_create_binary=$1
    firewall_create_table=$2
    firewall_create_chain=$3
    firewall_exec "$firewall_create_binary" -t "$firewall_create_table" -N "$firewall_create_chain" >/dev/null 2>&1 ||
        firewall_chain_exists "$firewall_create_binary" "$firewall_create_table" "$firewall_create_chain" || return 1
    firewall_exec "$firewall_create_binary" -t "$firewall_create_table" -F "$firewall_create_chain" >/dev/null 2>&1 || return 1
    firewall_chain_exists "$firewall_create_binary" "$firewall_create_table" "$firewall_create_chain"
}

firewall_rule() {
    firewall_rule_binary=$1
    firewall_rule_table=$2
    firewall_rule_chain=$3
    shift 3
    firewall_exec "$firewall_rule_binary" -t "$firewall_rule_table" -A "$firewall_rule_chain" "$@" >/dev/null 2>&1 || return 1
    firewall_exec "$firewall_rule_binary" -t "$firewall_rule_table" -C "$firewall_rule_chain" "$@" >/dev/null 2>&1
}

firewall_insert_jump() {
    firewall_hook_binary=$1
    firewall_hook_table=$2
    firewall_hook_chain=$3
    # Reinsert at head: netd may have prepended an owner reject since the last
    # ensure. Remove duplicates of OUR exact jump; leave foreign rules intact.
    firewall_remove_jump_all "$firewall_hook_binary" "$firewall_hook_table" "$firewall_hook_chain" || return 1
    firewall_exec "$firewall_hook_binary" -t "$firewall_hook_table" -I OUTPUT 1 -j "$firewall_hook_chain" >/dev/null 2>&1 || return 1
    firewall_exec "$firewall_hook_binary" -t "$firewall_hook_table" -C OUTPUT -j "$firewall_hook_chain" >/dev/null 2>&1
}

firewall_add_vpn_bypass() {
    firewall_vpn_binary=$1
    firewall_vpn_table=$2
    firewall_vpn_chain=$3
    for firewall_iface in tun+ tap+ wg+ ppp+ tailscale+; do
        firewall_rule "$firewall_vpn_binary" "$firewall_vpn_table" "$firewall_vpn_chain" -o "$firewall_iface" -j RETURN || return 1
    done
}

firewall_read_core() {
    [ -f "$AGH_STATE_DIR/core.state" ] || return 1
    [ "$(firewall_state_value "$AGH_STATE_DIR/core.state" state)" = ready ] || return 1
    [ "$(firewall_state_value "$AGH_STATE_DIR/core.state" firewall_authorized)" = 1 ] || return 1
    FW_DNS_PORT=$(firewall_state_value "$AGH_STATE_DIR/core.state" dns_port)
    # A dual-loopback configuration alone is not proof that ::1 is listening.
    FW_CORE_IPV6_READY=$(firewall_state_value "$AGH_STATE_DIR/core.state" dns_ipv6_ready)
    valid_port "$FW_DNS_PORT" || return 1
}

firewall_fail() {
    firewall_failure_reason=$1
    firewall_remove || firewall_failure_reason="${firewall_failure_reason}:rollback_failed"
    firewall_state_write degraded "$firewall_failure_reason"
    return 1
}

firewall_apply_family() {
    firewall_apply_binary=$1
    firewall_apply_family=$2
    firewall_apply_nat=$3
    firewall_apply_filter=$4
    firewall_apply_loopback=$5
    firewall_apply_dns=$6
    firewall_apply_dot=$7
    firewall_apply_doq=$8
    [ "$firewall_apply_dns" = true ] || [ "$firewall_apply_dot" = true ] || [ "$firewall_apply_doq" = true ] || return 0
    FW_APPLY_REASON=${firewall_apply_family}_filter_chain
    firewall_ensure_chain "$firewall_apply_binary" filter "$firewall_apply_filter" || return 1
    if [ "$firewall_apply_dns" = true ]; then
        FW_APPLY_REASON=${firewall_apply_family}_nat_chain
        firewall_ensure_chain "$firewall_apply_binary" nat "$firewall_apply_nat" || return 1
        # KSU runs AGH as UID 0. An owner exception covers upstream, bootstrap
        # AND plain fallback in every mode, without whitelisting app destinations.
        FW_APPLY_REASON=${firewall_apply_family}_owner
        firewall_rule "$firewall_apply_binary" nat "$firewall_apply_nat" -m owner --uid-owner 0 -j RETURN || return 1
        if [ "$FW_NETWORK_VPN" = true ] && [ "$FW_BYPASS_VPN_DNS" = true ]; then
            FW_APPLY_REASON=${firewall_apply_family}_vpn_dns
            firewall_add_vpn_bypass "$firewall_apply_binary" nat "$firewall_apply_nat" || return 1
        fi
        # OUTPUT NAT runs before netd's OUTPUT owner-isolation filter. Permit
        # only real DNS DNAT into our loopback listener, not arbitrary loopback
        # access/WebUI, whole user ranges, or connections originally to port 80.
        for firewall_proto in udp tcp; do
            FW_APPLY_REASON=${firewall_apply_family}_dns_allow
            firewall_rule "$firewall_apply_binary" filter "$firewall_apply_filter" -o lo -d "$firewall_apply_loopback" -p "$firewall_proto" --dport "$FW_DNS_PORT" -m conntrack --ctstate DNAT --ctdir ORIGINAL --ctorigdstport 53 -j ACCEPT || return 1
            FW_APPLY_REASON=${firewall_apply_family}_dns_redirect
            if [ "$firewall_apply_family" = v4 ]; then
                firewall_rule "$firewall_apply_binary" nat "$firewall_apply_nat" -p "$firewall_proto" --dport 53 -j REDIRECT --to-ports "$FW_DNS_PORT" || return 1
            else
                firewall_rule "$firewall_apply_binary" nat "$firewall_apply_nat" -p "$firewall_proto" --dport 53 -j DNAT --to-destination "[::1]:$FW_DNS_PORT" || return 1
            fi
        done
    fi
    # Root's own encrypted upstream must not be dropped either. RETURN keeps
    # all subsequent Android/system firewall checks (unlike a blanket ACCEPT).
    FW_APPLY_REASON=${firewall_apply_family}_filter_owner
    firewall_rule "$firewall_apply_binary" filter "$firewall_apply_filter" -m owner --uid-owner 0 -j RETURN || return 1
    if [ "$FW_NETWORK_VPN" = true ] && [ "$FW_BYPASS_VPN_ENCRYPTED" = true ]; then
        FW_APPLY_REASON=${firewall_apply_family}_vpn_encrypted
        firewall_add_vpn_bypass "$firewall_apply_binary" filter "$firewall_apply_filter" || return 1
    fi
    FW_APPLY_REASON=${firewall_apply_family}_encrypted_rules
    if [ "$firewall_apply_dot" = true ]; then
        firewall_rule "$firewall_apply_binary" filter "$firewall_apply_filter" -p tcp --dport 853 -j DROP || return 1
    fi
    if [ "$firewall_apply_doq" = true ]; then
        for firewall_doq_port in 853 784; do
            firewall_rule "$firewall_apply_binary" filter "$firewall_apply_filter" -p udp --dport "$firewall_doq_port" -j DROP || return 1
        done
    fi
    # Publish filter first, NAT last: never expose redirected clone DNS to the
    # rejecting netd chain while its narrowly scoped exemption is absent.
    FW_APPLY_REASON=${firewall_apply_family}_filter_jump
    firewall_insert_jump "$firewall_apply_binary" filter "$firewall_apply_filter" || return 1
    if [ "$firewall_apply_dns" = true ]; then
        FW_APPLY_REASON=${firewall_apply_family}_nat_jump
        firewall_insert_jump "$firewall_apply_binary" nat "$firewall_apply_nat" || return 1
    fi
}

firewall_ensure() {
    firewall_read_core || { firewall_remove || return 1; firewall_state_write degraded core_not_ready; return 0; }
    firewall_binary_v4=${IPTABLES_BIN:-iptables}
    firewall_binary_v6=${IP6TABLES_BIN:-ip6tables}
    FW_V4_REDIRECT=false; FW_V6_REDIRECT=false
    FW_DOT_BLOCK=false; FW_V6_DOT_BLOCK=false
    FW_DOQ_BLOCK=false; FW_V6_DOQ_BLOCK=false
    FW_V6_REASON=
    FW_WANT_V4_DNS=$(firewall_option redirect_ipv4_dns true)
    FW_WANT_V6_DNS=$(firewall_option redirect_ipv6_dns true)
    # Missing keys take safe fresh defaults; explicit persisted choices are
    # read, never overwritten (old default=true is indistinguishable from opt-in).
    FW_WANT_V4_DOT=$(firewall_option block_ipv4_dot false)
    FW_WANT_V6_DOT=$(firewall_option block_ipv6_dot false)
    FW_WANT_V4_DOQ=$(firewall_option block_ipv4_doq false)
    FW_WANT_V6_DOQ=$(firewall_option block_ipv6_doq false)
    FW_NETWORK_STATE=$(firewall_state_value "$AGH_STATE_DIR/network.state" state); [ -n "$FW_NETWORK_STATE" ] || FW_NETWORK_STATE=unknown
    FW_NETWORK_MODE=$(firewall_state_value "$AGH_STATE_DIR/network.state" mode); [ -n "$FW_NETWORK_MODE" ] || FW_NETWORK_MODE=unknown
    FW_NETWORK_TYPE=$(firewall_state_value "$AGH_STATE_DIR/network.state" network); [ -n "$FW_NETWORK_TYPE" ] || FW_NETWORK_TYPE=unknown
    FW_NETWORK_VPN=$(firewall_state_value "$AGH_STATE_DIR/network.state" vpn); [ -n "$FW_NETWORK_VPN" ] || FW_NETWORK_VPN=unknown
    FW_BYPASS_VPN_DNS=$(firewall_config_value bypass_vpn_dns); [ -n "$FW_BYPASS_VPN_DNS" ] || FW_BYPASS_VPN_DNS=true
    FW_BYPASS_VPN_ENCRYPTED=$(firewall_config_value bypass_vpn_encrypted_dns); [ -n "$FW_BYPASS_VPN_ENCRYPTED" ] || FW_BYPASS_VPN_ENCRYPTED=true
    FW_BYPASS_VPN_TRAFFIC=$(firewall_config_value bypass_vpn_traffic); [ -n "$FW_BYPASS_VPN_TRAFFIC" ] || FW_BYPASS_VPN_TRAFFIC=true

    if [ "$FW_NETWORK_STATE" != ready ]; then
        firewall_remove || return 1
        firewall_state_write degraded network_not_ready
        return 0
    fi

    if [ "$FW_NETWORK_VPN" = true ] && [ "$FW_BYPASS_VPN_TRAFFIC" = true ]; then
        firewall_remove || { firewall_state_write degraded vpn_remove_failed; return 1; }
        firewall_state_write bypassed vpn_passthrough
        return 0
    fi
    # Detach old NAT before rebuilding its narrowly scoped filter exemption.
    firewall_remove_v4 || { firewall_fail v4_remove_failed; return 1; }
    FW_V6_CLEANUP_OK=true
    firewall_remove_v6 || { FW_V6_CLEANUP_OK=false; FW_V6_REASON=v6_remove_failed; }

    if ! firewall_apply_family "$firewall_binary_v4" v4 "$FW_V4_NAT" "$FW_V4_FILTER" 127.0.0.1/32 "$FW_WANT_V4_DNS" "$FW_WANT_V4_DOT" "$FW_WANT_V4_DOQ"; then
        firewall_fail "$FW_APPLY_REASON"
        return 1
    fi
    FW_V4_REDIRECT=$FW_WANT_V4_DNS
    FW_DOT_BLOCK=$FW_WANT_V4_DOT
    FW_DOQ_BLOCK=$FW_WANT_V4_DOQ
    if [ "$FW_V6_CLEANUP_OK" = true ]; then
        if [ "$FW_WANT_V6_DNS" = true ] && [ "$FW_CORE_IPV6_READY" != true ]; then
            FW_WANT_V6_DNS=false
            FW_V6_REASON=v6_listener_unready
        fi
        if [ "$FW_WANT_V6_DNS" = true ] || [ "$FW_WANT_V6_DOT" = true ] || [ "$FW_WANT_V6_DOQ" = true ]; then
            if ! command -v "$firewall_binary_v6" >/dev/null 2>&1; then
                FW_V6_REASON=ip6tables_missing
            elif firewall_apply_family "$firewall_binary_v6" v6 "$FW_V6_NAT" "$FW_V6_FILTER" ::1/128 "$FW_WANT_V6_DNS" "$FW_WANT_V6_DOT" "$FW_WANT_V6_DOQ"; then
                FW_V6_REDIRECT=$FW_WANT_V6_DNS
                FW_V6_DOT_BLOCK=$FW_WANT_V6_DOT
                FW_V6_DOQ_BLOCK=$FW_WANT_V6_DOQ
            else
                FW_V6_REASON=$FW_APPLY_REASON
                firewall_remove_v6 || FW_V6_REASON="${FW_V6_REASON}:rollback_failed"
            fi
        fi
    fi
    # IPv6 capability failures MUST NOT remove a working IPv4 redirect, nor
    # replace unfilterable IPv6 DNS with DROP (breaks IPv6-only and Private DNS).
    if [ -n "$FW_V6_REASON" ]; then
        firewall_state_write degraded "$FW_V6_REASON"
    else
        firewall_state_write ready ready
    fi
}

firewall_once() {
    ensure_dirs || return 1
    mkdir -p "$AGH_RUN_DIR/firewall"
    if [ -f "$AGH_RUN_DIR/firewall/request" ] && grep -q '^remove$' "$AGH_RUN_DIR/firewall/request"; then
        rm -f "$AGH_RUN_DIR/firewall/request"
        firewall_remove
        return $?
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
    stop|remove) firewall_remove ;;
    *) printf 'usage: %s {once|daemon|stop}\n' "$0" >&2; exit 2 ;;
esac
