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
mkdir -p "$AGH_CONFIG_DIR" "$AGH_STATE_DIR" "$AGH_RUN_DIR" "$fixture/proxy"
proxy_file="$fixture/proxy/config.yaml"
cat > "$proxy_file" <<'EOF'
dns:
  enhanced-mode: fake-ip
  nameserver:
    - https://dns.example/dns-query
EOF
cat > "$AGH_CONFIG_DIR/proxy-adapter.conf" <<EOF
enabled=true
max_file_bytes=1048576
allowed_prefix=$fixture/proxy
file=$proxy_file
EOF

sh "$ROOT/scripts/adapters/proxy-worker.sh" once || fail 'proxy adapter failed'
grep -F 'enhanced-mode: redir-host' "$proxy_file" >/dev/null || fail 'proxy YAML was not changed'
[ -s "$AGH_BACKUP_DIR/proxy/manifest.tsv" ] || fail 'proxy backup manifest missing'
sh "$ROOT/scripts/adapters/proxy-worker.sh" --clean || fail 'proxy clean failed'
grep -F 'enhanced-mode: fake-ip' "$proxy_file" >/dev/null || fail 'proxy original was not restored'

sh "$ROOT/scripts/adapters/proxy-worker.sh" once || fail 'second proxy enable failed'
printf '%s\n' '# user edit' >> "$proxy_file"
sh "$ROOT/scripts/adapters/proxy-worker.sh" --clean || fail 'proxy clean should report but not fail'
grep -F '# user edit' "$proxy_file" >/dev/null || fail 'user edit was overwritten'
grep -F 'state=warning' "$AGH_STATE_DIR/proxy.state" >/dev/null || fail 'proxy warning state missing'

cat > "$proxy_file" <<'EOF'
not: valid proxy config
EOF
if sh "$ROOT/scripts/adapters/proxy-worker.sh" once; then fail 'malformed proxy YAML accepted'; fi

cat > "$AGH_CONFIG_DIR/proxy-adapter.conf" <<EOF
enabled=true
allowed_prefix=$fixture/proxy/allowed
file=$fixture/proxy/config.yaml
EOF
if sh "$ROOT/scripts/adapters/proxy-worker.sh" once; then fail 'unknown proxy path accepted'; fi

printf '%s\n' 'proxy adapter tests passed'
