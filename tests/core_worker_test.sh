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
mkdir -p "$AGH_ROOT/bin" "$AGH_CONFIG_DIR"
cp "$ROOT/config/default.yaml" "$AGH_CONFIG_DIR/AdGuardHome.yaml"
printf 'web_port=35001\ndns_port=35002\n' > "$AGH_STATE_DIR.ports.tmp"
mkdir -p "$AGH_STATE_DIR"
mv "$AGH_STATE_DIR.ports.tmp" "$AGH_STATE_DIR/ports.conf"

cat > "$AGH_ROOT/bin/AdGuardHome" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$FAKE_CORE_ARGS"
while :; do sleep 1; done
EOF
chmod 0755 "$AGH_ROOT/bin/AdGuardHome"
export FAKE_CORE_ARGS="$fixture/core-args"
export CORE_PORT_PROBE_CMD="$ROOT/tests/fixtures/probe-success.sh"
export CORE_START_WAIT=0
export CORE_TEST_MODE=1

sh "$ROOT/scripts/core-worker.sh" once || fail 'core did not start'
grep -F -- '--config ' "$FAKE_CORE_ARGS" >/dev/null || fail 'config argument missing'
grep -F -- '--work-dir ' "$FAKE_CORE_ARGS" >/dev/null || fail 'work-dir argument missing'
grep -F -- '--no-check-update' "$FAKE_CORE_ARGS" >/dev/null || fail 'no-check-update argument missing'
grep -F 'state=ready' "$AGH_STATE_DIR/core.state" >/dev/null || fail 'core not ready'
grep -F 'firewall_authorized=1' "$AGH_STATE_DIR/core.state" >/dev/null || fail 'firewall authorization missing'

sh "$ROOT/scripts/core-worker.sh" stop || fail 'core stop failed'
rm -f "$AGH_ROOT/bin/AdGuardHome"
if sh "$ROOT/scripts/core-worker.sh" once; then fail 'missing core accepted'; fi
grep -F 'state=failed' "$AGH_STATE_DIR/core.state" >/dev/null || fail 'missing core state not failed'
if grep -F 'firewall_authorized=1' "$AGH_STATE_DIR/core.state" >/dev/null; then fail 'failed core authorized firewall'; fi

printf '%s\n' 'core worker tests passed'
