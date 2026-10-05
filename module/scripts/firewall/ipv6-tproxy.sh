#!/system/bin/sh
# IPv6-only DNS fallback. The main firewall owns the enable/VPN policy.
SCRIPT_DIR=${0%/*}
MODULE_SCRIPTS_DIR=${SCRIPT_DIR%/*}
MODDIR=${MODDIR:-${MODULE_SCRIPTS_DIR%/*}}
export MODDIR
. "$MODULE_SCRIPTS_DIR/lib/common.sh"
. "$MODULE_SCRIPTS_DIR/lib/process.sh"
. "$MODULE_SCRIPTS_DIR/lib/platform.sh"
. "$MODULE_SCRIPTS_DIR/lib/lock.sh"

TP_MARK=0x20000000/0x20000000
TP_TABLE=20535
TP_PREF=105
TP_BINARY="$AGH_ROOT/bin/agh-dns-tproxy"
TP_OWNER="$AGH_STATE_DIR/ipv6-tproxy.owner"
TP_STATE="$AGH_STATE_DIR/ipv6-tproxy.state"
TP_READY="$AGH_RUN_DIR/ipv6-tproxy.ready"
TP_PIDFILE="$AGH_RUN_DIR/ipv6-tproxy.pid"
# Android's manager BusyBox ip cannot address arbitrary numeric route tables.
# Absolute paths bypass ASH_STANDALONE's applet interception.
if [ -n "${TPROXY_IP_BIN:-}" ]; then TP_IP=$TPROXY_IP_BIN
elif [ -x /system/bin/ip ]; then TP_IP=/system/bin/ip
else TP_IP=$(/bin/sh -c 'command -v ip'); fi
TP_IP6=${IP6TABLES_BIN:-ip6tables}

# Test/tool paths are root-only, just like the core worker's injection seams.
[ "$(id -u)" = 0 ] || exit 1

 tp_value() { read_key_value "$2" "$1"; }
 tp_state() {
    umask 077
    tp_tmp="$TP_STATE.$$"
    printf 'state=%s\nreason=%s\npid=%s\nlisten_port=%s\nupstream_port=%s\nlinklocal_tcp=false\n' \
        "$1" "$2" "${TP_PID:-}" "${TP_LISTEN:-}" "${TP_UPSTREAM:-}" > "$tp_tmp" || return 1
    agh_move "$tp_tmp" "$TP_STATE"
}
 tp_exec() { "$TP_IP6" -w 2 "$@"; }
 tp_inspect() {
    TP_MANGLE=$(tp_exec -t mangle -S 2>/dev/null) || return 1
    TP_FILTER=$(tp_exec -t filter -S 2>/dev/null) || return 1
    TP_RULES=$("$TP_IP" -6 rule show 2>/dev/null) || return 1
    TP_ROUTES=$("$TP_IP" -6 route show table "$TP_TABLE" 2>&1)
    tp_route_rc=$?
    if [ "$tp_route_rc" = 2 ] && [ "$TP_ROUTES" = "$(printf 'Error: ipv6: FIB table does not exist.\nDump terminated')" ]; then
        TP_ROUTES=
    else
        [ "$tp_route_rc" = 0 ] || return 1
    fi
}
 tp_core() {
    [ "$(tp_value "$AGH_STATE_DIR/core.state" state)" = ready ] || return 1
    [ "$(tp_value "$AGH_STATE_DIR/core.state" firewall_authorized)" = 1 ] || return 1
    TP_UPSTREAM=$(tp_value "$AGH_STATE_DIR/core.state" dns_port)
    TP_ROUTE_IFACE=$(tp_value "$AGH_STATE_DIR/network.state" interface)
    case "$TP_ROUTE_IFACE" in ''|lo|unknown) TP_ROUTE_IFACE= ;; *[!A-Za-z0-9_.-]*) return 1 ;; esac
    TP_VPN_DNS_BYPASS=false
    tp_bypass_dns=$(tp_value "$AGH_CONFIG_DIR/mode.conf" bypass_vpn_dns)
    [ -n "$tp_bypass_dns" ] || tp_bypass_dns=true
    if [ "$(tp_value "$AGH_STATE_DIR/network.state" vpn)" = true ] && [ "$tp_bypass_dns" = true ]; then
        TP_VPN_DNS_BYPASS=true
    fi
    valid_port "$TP_UPSTREAM"
}
 tp_load() {
    TP_PID=$(sed -n '1p' "$TP_PIDFILE" 2>/dev/null)
    TP_LISTEN=$(tp_value "$AGH_STATE_DIR/tproxy-ports.conf" relay_port)
}
 tp_owner() { [ "$(tp_value "$TP_OWNER" scope)" = ipv6-dns-v1 ]; }
 tp_owner_bypass() {
    # v1 journals predating selective bypass always owned the four-rule body.
    tp_saved_bypass=$(tp_value "$TP_OWNER" vpn_dns_bypass)
    case "$tp_saved_bypass" in '') printf 'false\n' ;; true|false) printf '%s\n' "$tp_saved_bypass" ;; *) return 1 ;; esac
}
 tp_owner_load() {
    tp_owner || return 1
    TP_LISTEN=$(tp_value "$TP_OWNER" listen_port)
    TP_UPSTREAM=$(tp_value "$TP_OWNER" upstream_port)
    valid_port "$TP_LISTEN" && valid_port "$TP_UPSTREAM" || return 1
    TP_OWN_O=$(tp_value "$TP_OWNER" chain_o)
    TP_OWN_P=$(tp_value "$TP_OWNER" chain_p)
    TP_OWN_T=$(tp_value "$TP_OWNER" chain_t)
    TP_OWN_RULE=$(tp_value "$TP_OWNER" rule)
    TP_OWN_ROUTE=$(tp_value "$TP_OWNER" route)
    TP_ROUTE_IFACE=$(tp_value "$TP_OWNER" linklocal_interface)
    TP_OWN_LINK=$(tp_value "$TP_OWNER" linklocal_route)
    TP_VPN_DNS_BYPASS=$(tp_owner_bypass) || return 1
    case "$TP_ROUTE_IFACE" in *[!A-Za-z0-9_.-]*) return 1 ;; esac
}
 tp_owner_write() {
    umask 077
    tp_owner_tmp="$TP_OWNER.$$"
    printf 'scope=ipv6-dns-v1\nlisten_port=%s\nupstream_port=%s\nchain_o=%s\nchain_p=%s\nchain_t=%s\nrule=%s\nroute=%s\nlinklocal_interface=%s\nlinklocal_route=%s\nvpn_dns_bypass=%s\n' \
        "$TP_LISTEN" "$TP_UPSTREAM" "${TP_OWN_O:-0}" "${TP_OWN_P:-0}" "${TP_OWN_T:-0}" \
        "${TP_OWN_RULE:-0}" "${TP_OWN_ROUTE:-0}" "${TP_ROUTE_IFACE:-}" "${TP_OWN_LINK:-0}" "${TP_VPN_DNS_BYPASS:-false}" > "$tp_owner_tmp" || return 1
    agh_move "$tp_owner_tmp" "$TP_OWNER"
}
 tp_socket() {
    # Prove both listeners belong to the verified helper, not an unrelated
    # socket on the same port. ::1 only; wildcard/public bindings never qualify.
    tp_hex=$(printf '%04X' "$TP_LISTEN") || return 1
    for tp_proto in tcp6 udp6; do
        tp_inode=$(awk -v address="00000000000000000000000001000000:$tp_hex" -v proto="$tp_proto" \
            '$2 == address && (proto != "tcp6" || $4 == "0A") {print $10}' "/proc/net/$tp_proto" 2>/dev/null)
        [ -n "$tp_inode" ] || return 1
        tp_found=false
        for tp_fd in "/proc/$TP_PID/fd/"*; do
            tp_link=$(readlink "$tp_fd" 2>/dev/null)
            for tp_one in $tp_inode; do [ "$tp_link" = "socket:[$tp_one]" ] && tp_found=true; done
        done
        [ "$tp_found" = true ] || return 1
    done
}
 tp_process_ready() {
    valid_port "$TP_LISTEN" && valid_port "$TP_UPSTREAM" || return 1
    case "$TP_PID" in ''|*[!0-9]*) return 1 ;; esac
    pid_is_ours "$TP_PID" "$TP_BINARY" || return 1
    [ -f "$TP_READY" ] && [ ! -L "$TP_READY" ] || return 1
    [ "$(cat "$TP_READY" 2>/dev/null)" = "$TP_PID" ] || return 1
    tp_args=$(tr '\000' '\n' < "/proc/$TP_PID/cmdline" 2>/dev/null) || return 1
    [ "$tp_args" = "$(printf '%s\n' "$TP_BINARY" --listen-port "$TP_LISTEN" --upstream-port "$TP_UPSTREAM" --ready-file "$TP_READY")" ] || return 1
    tp_socket
}
 tp_expected() {
    TP_EXPECT_O_COUNT=4
    [ "${TP_VPN_DNS_BYPASS:-false}" != true ] || TP_EXPECT_O_COUNT=9
    TP_EXPECT_O=$(
        printf '%s\n' '-m owner --uid-owner 0 -j RETURN' '-p tcp -d fe80::/10 -j RETURN'
        if [ "${TP_VPN_DNS_BYPASS:-false}" = true ]; then
            for tp_iface in tun+ tap+ wg+ ppp+ tailscale+; do
                printf '%s\n' "-o $tp_iface -j RETURN"
            done
        fi
        printf '%s\n' "-p udp --dport 53 -j MARK --set-xmark $TP_MARK" \
            "-p tcp --dport 53 -j MARK --set-xmark $TP_MARK")
    TP_EXPECT_P=$(printf '%s\n' \
        "-i lo -m mark --mark $TP_MARK -p udp --dport 53 -j TPROXY --on-ip ::1 --on-port $TP_LISTEN --tproxy-mark $TP_MARK" \
        "-i lo -m mark --mark $TP_MARK -p tcp --dport 53 -j TPROXY --on-ip ::1 --on-port $TP_LISTEN --tproxy-mark $TP_MARK")
    TP_EXPECT_T=$(printf '%s\n' \
        "-m mark --mark $TP_MARK -p udp --dport 53 -j ACCEPT" \
        "-m mark --mark $TP_MARK -p tcp --dport 53 -j ACCEPT")
}
 tp_chain_lines() {
    # iptables-save inserts protocol match modules automatically.
    printf '%s\n' "$1" | sed -n "s/^-A $2 //p" | sed \
        -e 's/ -m udp / /g' -e 's/ -m tcp / /g' \
        -e 's/-d fe80::\/10 -p tcp/-p tcp -d fe80::\/10/g' \
        -e 's/-p udp -m mark --mark \([^ ]*\)/-m mark --mark \1 -p udp/g' \
        -e 's/-p tcp -m mark --mark \([^ ]*\)/-m mark --mark \1 -p tcp/g' \
        -e 's/--on-port \([0-9]*\) --on-ip ::1/--on-ip ::1 --on-port \1/g'
}
 tp_route_exact() {
    printf '%s\n' "$TP_ROUTES" | awk -v iface="${TP_ROUTE_IFACE:-}" -v partial="${1:-false}" '
        NF { n++;
            if ($1 != "local" || $3 != "dev") bad=1
            if (($2 == "::/0" || $2 == "default") && $4 == "lo") main++
            else if ($2 == "fe80::/10" && iface != "" && $4 == iface) scoped++
            else bad=1
            for(i=5;i<=NF;i+=2) {
                if (($i == "metric" && $(i+1) == "1024") || ($i == "pref" && $(i+1) == "medium") ||
                    ($i == "proto" && $(i+1) == "boot") || ($i == "table" && $(i+1) == "20535")) continue
                bad=1
            }
        } END {exit !(!bad && main <= 1 && scoped <= 1 &&
            (partial == "true" || (main == 1 && scoped == (iface != ""))))}'
}
 tp_rule_exact() {
    TP_AT_PREF=$(printf '%s\n' "$TP_RULES" | awk '$1 == "105:" {$1=$1; print}' | \
        sed 's/536870912/0x20000000/g')
    [ "$TP_AT_PREF" = "105: from all fwmark $TP_MARK lookup $TP_TABLE" ]
}
 tp_chain_ready() {
    tp_rtable=$1; tp_rchain=$2; tp_rlisting=$3; tp_expected_text=$4; tp_expected_count=$5
    [ "$(printf '%s\n' "$tp_rlisting" | grep -c -- "^-A $tp_rchain ")" = "$tp_expected_count" ] || return 1
    printf '%s\n' "$tp_expected_text" | while IFS= read -r tp_line; do
        set -- $tp_line
        tp_exec -t "$tp_rtable" -C "$tp_rchain" "$@" >/dev/null 2>&1 || exit 1
    done
}
 tp_filter_prefix_ready() {
    tp_filter_output=$(printf '%s\n' "$TP_FILTER" | sed -n '/^-A OUTPUT /p')
    if printf '%s\n' "$tp_filter_output" | grep -Fx -- '-A OUTPUT -j AGHADF6' >/dev/null; then
        # The encrypted policy may be immediately before OR after our DNS
        # allowance. Never accept a foreign/netd rule between either hook.
        printf '%s\n' "$tp_filter_output" | awk '
            $0 == "-A OUTPUT -j AGHADF6" { f++; if (NR > 2) bad=1 }
            $0 == "-A OUTPUT -j AGHAD6T" { t++; if (NR > 2) bad=1 }
            NR <= 2 && $0 != "-A OUTPUT -j AGHADF6" && $0 != "-A OUTPUT -j AGHAD6T" { bad=1 }
            END { exit !(!bad && f == 1 && t == 1) }' || return 1
        # Only the root/VPN returns and encrypted-port drops are safe ahead
        # of marked port-53 DNS. A named chain alone is not authorization.
        tp_policy=$(tp_chain_lines "$TP_FILTER" AGHADF6)
        [ "$(printf '%s\n' "$tp_policy" | sed -n '1p')" = '-m owner --uid-owner 0 -j RETURN' ] || return 1
        printf '%s\n' "$tp_policy" | while IFS= read -r tp_policy_line; do
            case "$tp_policy_line" in
                '-m owner --uid-owner 0 -j RETURN'|\
                '-o tun+ -j RETURN'|'-o tap+ -j RETURN'|'-o wg+ -j RETURN'|'-o ppp+ -j RETURN'|'-o tailscale+ -j RETURN'|\
                '-p tcp --dport 853 -j DROP'|'-p udp --dport 853 -j DROP'|'-p udp --dport 784 -j DROP') ;;
                *) exit 1 ;;
            esac
        done || return 1
    else
        [ "$(printf '%s\n' "$tp_filter_output" | sed -n '1p')" = '-A OUTPUT -j AGHAD6T' ] || return 1
    fi
}
 tp_rules_ready() {
    tp_prepublication=${1:-false}
    tp_inspect || return 1
    tp_expected
    tp_chain_ready mangle AGHAD6O "$TP_MANGLE" "$TP_EXPECT_O" "$TP_EXPECT_O_COUNT" || return 1
    [ "$(tp_chain_lines "$TP_MANGLE" AGHAD6O | sed -n '1p')" = '-m owner --uid-owner 0 -j RETURN' ] || return 1
    if [ "${TP_VPN_DNS_BYPASS:-false}" = true ]; then
        # A RETURN after MARK is present but ineffective: require bypass order.
        [ "$(tp_chain_lines "$TP_MANGLE" AGHAD6O)" = "$TP_EXPECT_O" ] || return 1
    fi
    tp_chain_ready mangle AGHAD6P "$TP_MANGLE" "$TP_EXPECT_P" 2 || return 1
    tp_chain_ready filter AGHAD6T "$TP_FILTER" "$TP_EXPECT_T" 2 || return 1
    for tp_spec in 'mangle OUTPUT AGHAD6O' 'mangle PREROUTING AGHAD6P' 'filter OUTPUT AGHAD6T'; do
        set -- $tp_spec
        [ "$tp_prepublication" = true ] && [ "$3" = AGHAD6O ] && continue
        if [ "$1" = mangle ]; then tp_listing=$TP_MANGLE; else tp_listing=$TP_FILTER; fi
        [ "$(printf '%s\n' "$tp_listing" | grep -Fx -- "-A $2 -j $3" | wc -l | tr -d ' ')" = 1 ] || return 1
        # Must precede netd rejects, not merely exist later in OUTPUT.
        if [ "$1" = filter ]; then tp_filter_prefix_ready || return 1; continue; fi
        [ "$(printf '%s\n' "$tp_listing" | sed -n "/^-A $2 /p" | sed -n '1p')" = "-A $2 -j $3" ] || return 1
    done
    tp_rule_exact && tp_route_exact
}
 tp_check() {
    tp_core && tp_load && tp_owner &&
        [ "$(tp_value "$TP_OWNER" linklocal_interface)" = "${TP_ROUTE_IFACE:-}" ] &&
        [ "$(tp_owner_bypass)" = "$TP_VPN_DNS_BYPASS" ] &&
        tp_process_ready && tp_rules_ready
}
 tp_scope_free() {
    tp_inspect || return 1
    ! printf '%s\n%s\n' "$TP_MANGLE" "$TP_FILTER" | grep -E '(^-N AGHAD6[OPT]$| AGHAD6[OPT]( |$))' >/dev/null || return 1
    ! printf '%s\n' "$TP_RULES" | grep -E '^105:|fwmark 0x20000000(/| )' >/dev/null || return 1
    [ -z "$TP_ROUTES" ]
}
 tp_allocate() {
    TP_LISTEN=$(tp_value "$AGH_STATE_DIR/tproxy-ports.conf" relay_port)
    tp_web=$(tp_value "$AGH_STATE_DIR/core.state" web_port)
    tp_saved_web=$(tp_value "$AGH_STATE_DIR/ports.conf" web_port)
    tp_saved_dns=$(tp_value "$AGH_STATE_DIR/ports.conf" dns_port)
    tp_try=0
    while :; do
        if valid_port "$TP_LISTEN" && [ "$TP_LISTEN" != "$TP_UPSTREAM" ] && [ "$TP_LISTEN" != "$tp_web" ] &&
           [ "$TP_LISTEN" != "$tp_saved_web" ] && [ "$TP_LISTEN" != "$tp_saved_dns" ] && port_is_free "$TP_LISTEN"; then break; fi
        [ "$tp_try" -lt 500 ] || return 1
        port_candidate "$tp_try"
        TP_LISTEN=$PORT_CANDIDATE
        tp_try=$((tp_try + 1))
    done
    umask 077
    printf 'relay_port=%s\n' "$TP_LISTEN" > "$AGH_STATE_DIR/.tproxy-ports.$$" || return 1
    agh_move "$AGH_STATE_DIR/.tproxy-ports.$$" "$AGH_STATE_DIR/tproxy-ports.conf"
}
 tp_start() {
    [ -x "$TP_BINARY" ] || return 1
    rm -f "$TP_READY"
    "$TP_BINARY" --listen-port "$TP_LISTEN" --upstream-port "$TP_UPSTREAM" --ready-file "$TP_READY" \
        >> "$AGH_LOG_DIR/ipv6-tproxy.log" 2>&1 &
    TP_PID=$!
    printf '%s\n' "$TP_PID" > "$TP_PIDFILE" || return 1
    tp_wait=0
    while [ "$tp_wait" -lt "${TPROXY_READY_WAIT:-10}" ]; do
        tp_process_ready && return 0
        pid_is_alive "$TP_PID" || return 1
        sleep 1
        tp_wait=$((tp_wait + 1))
    done
    tp_process_ready
}
 tp_add_rules() {
    tp_expected
    tp_exec -t mangle -N AGHAD6O || return 1
    TP_OWN_O=1; tp_owner_write || return 1
    tp_exec -t mangle -N AGHAD6P || return 1
    TP_OWN_P=1; tp_owner_write || return 1
    tp_exec -t filter -N AGHAD6T || return 1
    TP_OWN_T=1; tp_owner_write || return 1
    for tp_chain in AGHAD6O AGHAD6P AGHAD6T; do
        case "$tp_chain" in AGHAD6O) tp_text=$TP_EXPECT_O; tp_table=mangle ;; AGHAD6P) tp_text=$TP_EXPECT_P; tp_table=mangle ;; *) tp_text=$TP_EXPECT_T; tp_table=filter ;; esac
        printf '%s\n' "$tp_text" | while IFS= read -r tp_line; do
            # All words are fixed literals or validated numeric ports.
            set -- $tp_line
            tp_exec -t "$tp_table" -A "$tp_chain" "$@" || exit 1
        done || return 1
    done
    "$TP_IP" -6 route add 'local' ::/0 dev lo table "$TP_TABLE" || return 1
    TP_OWN_ROUTE=1; tp_owner_write || return 1
    # Scoped link-local lookups specify an outgoing interface and ignore the
    # generic dev-lo route. A marked local route on that interface preserves
    # its scope while delivering the DNS packet locally (including on Xiaomi).
    if [ -n "$TP_ROUTE_IFACE" ]; then
        "$TP_IP" -6 route add 'local' fe80::/10 dev "$TP_ROUTE_IFACE" table "$TP_TABLE" || return 1
        TP_OWN_LINK=1; tp_owner_write || return 1
    fi
    "$TP_IP" -6 rule add pref "$TP_PREF" fwmark "$TP_MARK" table "$TP_TABLE" || return 1
    TP_OWN_RULE=1; tp_owner_write || return 1
    tp_exec -t mangle -I PREROUTING 1 -j AGHAD6P || return 1
    tp_exec -t filter -I OUTPUT 1 -j AGHAD6T || return 1
    # OUTPUT marking is the final publication operation. Read back every
    # dependency first; command success alone is not proof of installation.
    tp_rules_ready true || return 1
    tp_process_ready || return 1
    tp_exec -t mangle -I OUTPUT 1 -j AGHAD6O || return 1
    tp_rules_ready
}
 tp_detach() {
    tp_dtable=$1; tp_hook=$2; tp_chain=$3; tp_count=0
    while :; do
        tp_inspect || return 1
        if [ "$tp_dtable" = mangle ]; then tp_listing=$TP_MANGLE; else tp_listing=$TP_FILTER; fi
        printf '%s\n' "$tp_listing" | grep -Fx -- "-A $tp_hook -j $tp_chain" >/dev/null || return 0
        [ "$tp_count" -lt 32 ] || return 1
        tp_exec -t "$tp_dtable" -D "$tp_hook" -j "$tp_chain" || return 1
        tp_count=$((tp_count + 1))
    done
}
 tp_drop_chain() {
    tp_ctable=$1; tp_cname=$2; tp_owned=$3; tp_allowed=$4
    tp_inspect || return 1
    if [ "$tp_ctable" = mangle ]; then tp_clisting=$TP_MANGLE; else tp_clisting=$TP_FILTER; fi
    printf '%s\n' "$tp_clisting" | grep -Fx -- "-N $tp_cname" >/dev/null || return 0
    [ "$tp_owned" = 1 ] || return 1
    # Never flush foreign additions even inside our named chain. No incoming
    # references can survive; an unknown/conditional hook requires intervention.
    ! printf '%s\n' "$tp_clisting" | grep -E " (-j|-g) $tp_cname( |$)" >/dev/null || return 1
    tp_actual=$(tp_chain_lines "$tp_clisting" "$tp_cname")
    printf '%s\n' "$tp_actual" | while IFS= read -r tp_line; do
        [ -n "$tp_line" ] || continue
        printf '%s\n' "$tp_allowed" | grep -Fx -- "$tp_line" >/dev/null || exit 1
    done || return 1
    printf '%s\n' "$tp_actual" | while IFS= read -r tp_line; do
        [ -n "$tp_line" ] || continue
        set -- $tp_line
        tp_exec -t "$tp_ctable" -D "$tp_cname" "$@" || exit 1
    done || return 1
    tp_exec -t "$tp_ctable" -X "$tp_cname"
}
 tp_stop() {
    if pid_is_ours "$TP_PID" "$TP_BINARY"; then
        kill "$TP_PID" 2>/dev/null || return 1
        tp_wait=0
        while pid_is_ours "$TP_PID" "$TP_BINARY"; do
            [ "$(awk '{print $3}' "/proc/$TP_PID/stat" 2>/dev/null)" = Z ] && break
            if [ "$tp_wait" -ge "${TPROXY_STOP_WAIT:-10}" ]; then
                pid_is_ours "$TP_PID" "$TP_BINARY" && kill -9 "$TP_PID" 2>/dev/null
                break
            fi
            sleep 1; tp_wait=$((tp_wait + 1))
        done
    fi
    rm -f "$TP_PIDFILE" "$TP_READY"
    TP_PID=
}
 tp_remove_inner() {
    tp_load
    if tp_owner; then tp_owner_load || return 1; fi
    tp_inspect || return 1
    if ! tp_owner; then
        # Lack of a journal never grants permission to remove foreign scope.
        tp_scope_free || return 1
        [ ! -f "$TP_PIDFILE" ] || return 1
        return 0
    fi
    tp_owner_load || return 1
    # Reconstruct only the published body. Current policy cannot authorize
    # deleting a newly allowed rule that was foreign to the previous journal.
    tp_expected
    # The redirect publication hook always disappears before any dependency.
    if [ "$TP_OWN_O" = 1 ]; then tp_detach mangle OUTPUT AGHAD6O || return 1; fi
    if [ "$TP_OWN_P" = 1 ]; then tp_detach mangle PREROUTING AGHAD6P || return 1; fi
    if [ "$TP_OWN_T" = 1 ]; then tp_detach filter OUTPUT AGHAD6T || return 1; fi
    tp_drop_chain mangle AGHAD6O "$TP_OWN_O" "$TP_EXPECT_O" || return 1
    tp_drop_chain mangle AGHAD6P "$TP_OWN_P" "$TP_EXPECT_P" || return 1
    tp_drop_chain filter AGHAD6T "$TP_OWN_T" "$TP_EXPECT_T" || return 1
    tp_inspect || return 1
    ! printf '%s\n%s\n' "$TP_MANGLE" "$TP_FILTER" | grep -E '(^-N AGHAD6[OPT]$| AGHAD6[OPT]( |$))' >/dev/null || return 1
    TP_AT_PREF=$(printf '%s\n' "$TP_RULES" | awk '$1 == "105:" {$1=$1; print}' | \
        sed 's/536870912/0x20000000/g')
    if [ -n "$TP_AT_PREF" ]; then
        [ "$TP_OWN_RULE" = 1 ] && tp_rule_exact || return 1
        "$TP_IP" -6 rule del pref "$TP_PREF" fwmark "$TP_MARK" table "$TP_TABLE" || return 1
    fi
    if [ -n "$TP_ROUTES" ]; then
        tp_route_exact true || return 1
        if printf '%s\n' "$TP_ROUTES" | grep -E '^local fe80::/10 ' >/dev/null; then
            [ "$TP_OWN_LINK" = 1 ] && [ -n "$TP_ROUTE_IFACE" ] || return 1
            "$TP_IP" -6 route del 'local' fe80::/10 dev "$TP_ROUTE_IFACE" table "$TP_TABLE" || return 1
        fi
        if printf '%s\n' "$TP_ROUTES" | grep -E '^local (default|::/0) ' >/dev/null; then
            [ "$TP_OWN_ROUTE" = 1 ] || return 1
            "$TP_IP" -6 route del 'local' ::/0 dev lo table "$TP_TABLE" || return 1
        fi
    fi
    # Read back all exact targets. Failed inspection is unknown, never absent.
    tp_scope_free || return 1
    tp_stop || return 1
    rm -f "$TP_OWNER"
}
 tp_remove() {
    tp_remove_inner || { tp_state degraded remove_failed; return 1; }
    tp_state removed removed
}
 tp_fail() {
    tp_reason=$1
    tp_remove_inner || tp_reason="${tp_reason}:rollback_failed"
    tp_state degraded "$tp_reason"
    return 1
}
 tp_once() {
    if tp_check; then
        [ "$(tp_value "$TP_STATE" state)" = ready ] || tp_state ready existing
        return 0
    fi
    tp_core || { tp_fail core_not_ready; return 1; }
    if [ -e "$TP_OWNER" ]; then
        tp_remove_inner || { tp_state degraded remove_failed; return 1; }
        # Cleanup uses the old owner ports; recover the authorized new port.
        tp_core || { tp_state degraded core_not_ready; return 1; }
    fi
    tp_load
    tp_scope_free || { tp_state degraded scope_collision_or_inspection; return 1; }
    tp_allocate || { tp_state degraded port_allocation; return 1; }
    TP_OWN_O=0; TP_OWN_P=0; TP_OWN_T=0; TP_OWN_RULE=0; TP_OWN_ROUTE=0; TP_OWN_LINK=0
    tp_owner_write || return 1
    tp_start || { tp_fail relay_unready; return 1; }
    tp_add_rules || { tp_fail setup_failed; return 1; }
    tp_state ready ready
}

case "${1:-once}" in
    check-ready) tp_check ;;
    once|remove)
        ensure_dirs || exit 1
        agh_lock_acquire "$AGH_RUN_DIR/ipv6-tproxy.lock" 2 || exit 1
        trap 'agh_lock_release' EXIT
        if [ "${1:-once}" = remove ]; then tp_remove; else tp_once; fi
        ;;
    *) printf 'usage: %s {once|remove|check-ready}\n' "$0" >&2; exit 2 ;;
esac
