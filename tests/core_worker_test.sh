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
. "$ROOT/scripts/lib/credentials.sh"
ensure_credentials "$AGH_STATE_DIR/credentials.conf" || fail 'test credentials missing'

cat > "$AGH_ROOT/bin/AdGuardHome" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$FAKE_CORE_ARGS"
while :; do sleep 1; done
EOF
chmod 0755 "$AGH_ROOT/bin/AdGuardHome"
cat > "$fixture/install-config.sh" <<'EOF'
#!/bin/sh
web_port=$1
dns_port=$2
config_file=$5
cat > "$config_file" <<YAML
http:
  address: 127.0.0.1:$web_port
users:
  - name: admin
    password: mock-hash
dns:
  bind_hosts:
    - 127.0.0.1
  port: $dns_port
  upstream_dns:
    - https://dns10.quad9.net/dns-query
filters: []
schema_version: 34
YAML
EOF
chmod 0755 "$fixture/install-config.sh"
export FAKE_CORE_ARGS="$fixture/core-args"
export CORE_PORT_PROBE_CMD="$ROOT/tests/fixtures/probe-success.sh"
export CORE_INSTALL_CMD="$fixture/install-config.sh"
export CORE_START_WAIT=1
export CORE_DNS_WAIT=1
export CORE_TEST_MODE=1

sh "$ROOT/scripts/core/core-worker.sh" once || {
    sed -n '1,120p' "$AGH_STATE_DIR/core.state" >&2 || true
    sed -n '1,120p' "$AGH_LOG_DIR/core-process.log" >&2 || true
    fail 'core did not start'
}
grep -F -- '--config ' "$FAKE_CORE_ARGS" >/dev/null || fail 'config argument missing'
grep -F -- "$AGH_CONFIG_DIR/AdGuardHome.yaml" "$FAKE_CORE_ARGS" >/dev/null || fail 'persistent config path not used'
grep -F -- '--work-dir ' "$FAKE_CORE_ARGS" >/dev/null || fail 'work-dir argument missing'
grep -F -- '--no-check-update' "$FAKE_CORE_ARGS" >/dev/null || fail 'no-check-update argument missing'
grep -F -- '--web-addr 127.0.0.1:35001' "$FAKE_CORE_ARGS" >/dev/null || fail 'initial web address argument missing'
grep -F 'password: mock-hash' "$AGH_CONFIG_DIR/AdGuardHome.yaml" >/dev/null || fail 'initial configuration was not persisted'
grep -F 'state=ready' "$AGH_STATE_DIR/core.state" >/dev/null || fail 'core not ready'
grep -F 'firewall_authorized=1' "$AGH_STATE_DIR/core.state" >/dev/null || fail 'firewall authorization missing'

sh "$ROOT/scripts/core/core-worker.sh" stop || fail 'core stop failed'
rm -f "$AGH_ROOT/bin/AdGuardHome"
if sh "$ROOT/scripts/core/core-worker.sh" once; then fail 'missing core accepted'; fi
grep -F 'state=failed' "$AGH_STATE_DIR/core.state" >/dev/null || fail 'missing core state not failed'
if grep -F 'firewall_authorized=1' "$AGH_STATE_DIR/core.state" >/dev/null; then fail 'failed core authorized firewall'; fi

printf '%s\n' 'core worker tests passed'
