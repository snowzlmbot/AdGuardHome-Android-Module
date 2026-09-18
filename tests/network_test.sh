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
mkdir -p "$AGH_CONFIG_DIR" "$AGH_STATE_DIR" "$AGH_RUN_DIR"
cp "$ROOT/config/mode.conf" "$AGH_CONFIG_DIR/mode.conf"

run_snapshot() {
    printf '%s\n' "$1" > "$fixture/network.snapshot"
    NETWORK_SNAPSHOT_FILE="$fixture/network.snapshot" sh "$ROOT/scripts/network/network-worker.sh" once
}

run_snapshot 'network=wifi
vpn=false
dns4=192.0.2.1,192.0.2.2
dns6=2001:db8::1'
grep -F 'state=ready' "$AGH_STATE_DIR/network.state" >/dev/null || fail 'wifi state not ready'
grep -F 'mode=1' "$AGH_STATE_DIR/network.state" >/dev/null || fail 'mode missing'
grep -F 'network=wifi' "$AGH_STATE_DIR/network.state" >/dev/null || fail 'wifi not parsed'
grep -F 'dns4=192.0.2.1,192.0.2.2' "$AGH_STATE_DIR/network.state" >/dev/null || fail 'dns4 not parsed'

sed -i 's/^mode=.*/mode=2/' "$AGH_CONFIG_DIR/mode.conf"
run_snapshot 'network=mobile
vpn=true
dns4=198.51.100.1
dns6='
grep -F 'network=mobile' "$AGH_STATE_DIR/network.state" >/dev/null || fail 'mobile not parsed'
grep -F 'vpn=true' "$AGH_STATE_DIR/network.state" >/dev/null || fail 'vpn not parsed'

sed -i 's/^mode=.*/mode=3/' "$AGH_CONFIG_DIR/mode.conf"
run_snapshot 'network=ethernet
vpn=false
dns4=
dns6=2001:db8::53'
grep -F 'state=ready' "$AGH_STATE_DIR/network.state" >/dev/null || fail 'IPv6-only state not ready'
grep -F 'dns4=' "$AGH_STATE_DIR/network.state" >/dev/null || fail 'empty dns4 not represented'

run_snapshot 'network=unknown
vpn=maybe
dns4=not-an-ip' || true
grep -F 'state=degraded' "$AGH_STATE_DIR/network.state" >/dev/null || fail 'invalid snapshot accepted'
grep -F 'network=ethernet' "$AGH_STATE_DIR/network.lastgood" >/dev/null || fail 'last known good state not retained'

printf '%s\n' 'network tests passed'
