#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
export MODDIR="$ROOT/module"
export AGH_ROOT="$fixture/agh"
export AGH_CONFIG_DIR="$AGH_ROOT/config"
export AGH_STATE_DIR="$AGH_ROOT/state"
export AGH_RUN_DIR="$AGH_ROOT/run"
export AGH_LOG_DIR="$AGH_ROOT/logs"
export AGH_DATA_DIR="$AGH_ROOT/data"
export AGH_BACKUP_DIR="$AGH_ROOT/backup"
mkdir -p "$AGH_CONFIG_DIR" "$AGH_STATE_DIR" "$AGH_RUN_DIR" "$AGH_LOG_DIR"
printf 'state=ready\npid=not-a-secret-pid\nfirewall_authorized=1\n' > "$AGH_STATE_DIR/core.state"
printf 'state=ready\nreason=ready\n' > "$AGH_STATE_DIR/firewall.state"
printf 'state=disabled\n' > "$AGH_STATE_DIR/proxy.state"
printf 'state=disabled\n' > "$AGH_STATE_DIR/file.state"
printf 'password=super-secret\n' > "$AGH_STATE_DIR/credentials.conf"
printf 'serialno=private-device\npassword=super-secret\n' > "$AGH_LOG_DIR/private.log"
printf 'web_port=35001\ndns_port=35002\n' > "$AGH_STATE_DIR/ports.conf"

output=$(sh "$ROOT/module/scripts/diagnostics/diagnostics.sh")
grep -F 'core=ready' <<EOF >/dev/null || fail 'core state missing'
$output
EOF
printf '%s\n' "$output" | grep -F 'super-secret' >/dev/null && fail 'diagnostics leaked password' || true
printf '%s\n' "$output" | grep -F 'private-device' >/dev/null && fail 'diagnostics leaked serial' || true

printf '2026-01-01 [core] password=super-secret token=abc123 safe-message\n' > "$AGH_LOG_DIR/events.log"
log_output=$(sh "$ROOT/module/scripts/diagnostics/diagnostics.sh" logs)
printf '%s\n' "$log_output" | grep -F 'safe-message' >/dev/null || fail 'diagnostic logs missing content'
printf '%s\n' "$log_output" | grep -F 'super-secret' >/dev/null && fail 'diagnostic logs leaked password' || true
printf '%s\n' "$log_output" | grep -F 'abc123' >/dev/null && fail 'diagnostic logs leaked token' || true
printf '%s\n' "$output" | grep -F '35001' >/dev/null || fail 'diagnostics omitted web port'

printf '%s\n' 'diagnostics tests passed'
