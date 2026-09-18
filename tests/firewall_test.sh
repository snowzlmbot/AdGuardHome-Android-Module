#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
export MODDIR="$ROOT"
export AGH_ROOT="$fixture/agh"
export AGH_CONFIG_DIR="$AGH_ROOT/config"
export AGH_STATE_DIR="$AGH_ROOT/state"
export AGH_RUN_DIR="$AGH_ROOT/run"
export AGH_LOG_DIR="$AGH_ROOT/logs"
export AGH_DATA_DIR="$AGH_ROOT/data"
export AGH_BACKUP_DIR="$AGH_ROOT/backup"
export FIREWALL_NO_WAIT=1
export IPTABLES_RECORD_FILE="$fixture/iptables.log"
export IP6TABLES_RECORD_FILE="$fixture/ip6tables.log"
mkdir -p "$AGH_CONFIG_DIR" "$AGH_STATE_DIR" "$AGH_RUN_DIR"
cp "$ROOT/config/mode.conf" "$AGH_CONFIG_DIR/mode.conf"
printf 'state=ready\nfirewall_authorized=1\ndns_port=35002\n' > "$AGH_STATE_DIR/core.state"
printf 'state=ready\nnetwork=wifi\nvpn=false\ndns4=192.0.2.1\ndns6=2001:db8::1\n' > "$AGH_STATE_DIR/network.state"
mkdir -p "$ROOT/tests/fixtures/iptables-recording-bin"

IPTABLES_BIN="$ROOT/tests/fixtures/iptables-recording-bin/iptables" IP6TABLES_BIN="$ROOT/tests/fixtures/iptables-recording-bin/ip6tables" sh "$ROOT/scripts/firewall-worker.sh" once || fail 'initial ensure failed'
[ -f "$fixture/iptables.log" ] || fail 'iptables was not called'
grep -F -- 'AGHADM4N' "$fixture/iptables.log" >/dev/null || fail 'owned NAT chain missing'
grep -F -- 'AGHADF4' "$fixture/iptables.log" >/dev/null || fail 'owned v4 filter chain missing'
grep -F -- 'AGHADF6' "$fixture/ip6tables.log" >/dev/null || fail 'owned v6 filter chain missing'
! grep -F -- 'FOREIGN' "$fixture/iptables.log" >/dev/null || fail 'foreign chain touched'

before=$(wc -l < "$fixture/iptables.log")
IPTABLES_BIN="$ROOT/tests/fixtures/iptables-recording-bin/iptables" IP6TABLES_BIN="$ROOT/tests/fixtures/iptables-recording-bin/ip6tables" sh "$ROOT/scripts/firewall-worker.sh" once || fail 'repeat ensure failed'
after=$(wc -l < "$fixture/iptables.log")
[ "$after" -gt "$before" ] || fail 'repeat ensure did not verify rules'

sed -i 's/^lan_dns_target=.*/lan_dns_target=192.0.2.53:53/' "$AGH_CONFIG_DIR/mode.conf"
printf 'state=ready\nmode=1\nnetwork=wifi\nvpn=false\ndns4=192.0.2.1\ndns6=2001:db8::1\n' > "$AGH_STATE_DIR/network.state"
IPTABLES_BIN="$ROOT/tests/fixtures/iptables-recording-bin/iptables" IP6TABLES_BIN="$ROOT/tests/fixtures/iptables-recording-bin/ip6tables" sh "$ROOT/scripts/firewall-worker.sh" once || fail 'mode exception ensure failed'
grep -F -- '192.0.2.53' "$fixture/iptables.log" >/dev/null || fail 'mode exception missing'

echo remove > "$AGH_RUN_DIR/firewall/request"
IPTABLES_BIN="$ROOT/tests/fixtures/iptables-recording-bin/iptables" IP6TABLES_BIN="$ROOT/tests/fixtures/iptables-recording-bin/ip6tables" sh "$ROOT/scripts/firewall-worker.sh" once || fail 'remove failed'
grep -F 'state=removed' "$AGH_STATE_DIR/firewall.state" >/dev/null || fail 'firewall removal state missing'

printf 'state=failed\nfirewall_authorized=0\n' > "$AGH_STATE_DIR/core.state"
IPTABLES_BIN="$ROOT/tests/fixtures/iptables-recording-bin/iptables" IP6TABLES_BIN="$ROOT/tests/fixtures/iptables-recording-bin/ip6tables" sh "$ROOT/scripts/firewall-worker.sh" once || fail 'unsafe core state caused worker failure'
grep -F 'reason=core_not_ready' "$AGH_STATE_DIR/firewall.state" >/dev/null || fail 'core safety gate missing'

printf '%s\n' 'firewall tests passed'
