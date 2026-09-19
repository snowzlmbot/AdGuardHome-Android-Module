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
export SUPERVISOR_WORKER_DIR="$fixture/workers"
export MODULE_PROP_FILE="$fixture/module.prop"
mkdir -p "$AGH_CONFIG_DIR" "$AGH_STATE_DIR" "$AGH_RUN_DIR" "$SUPERVISOR_WORKER_DIR"
printf 'description=initial\n' > "$MODULE_PROP_FILE"
printf 'language=zh\n' > "$AGH_STATE_DIR/language.conf"

cat > "$SUPERVISOR_WORKER_DIR/core-worker.sh" <<'EOF'
#!/bin/sh
if [ "${FAKE_CORE_STATE:-ready}" = failed ]; then printf 'state=failed\n' > "$AGH_STATE_DIR/core.state"; exit 1; fi
printf 'state=ready\nfirewall_authorized=1\n' > "$AGH_STATE_DIR/core.state"
EOF
cat > "$SUPERVISOR_WORKER_DIR/firewall-worker.sh" <<'EOF'
#!/bin/sh
printf 'state=%s\n' "${FAKE_FIREWALL_STATE:-ready}" > "$AGH_STATE_DIR/firewall.state"
[ "${FAKE_FIREWALL_STATE:-ready}" = failed ] && exit 1
EOF
cat > "$SUPERVISOR_WORKER_DIR/network-worker.sh" <<'EOF'
#!/bin/sh
printf 'state=ready\nmode=2\nnetwork=wifi\nvpn=false\n' > "$AGH_STATE_DIR/network.state"
EOF
cat > "$SUPERVISOR_WORKER_DIR/proxy-worker.sh" <<'EOF'
#!/bin/sh
printf 'state=%s\n' "${FAKE_PROXY_STATE:-ready}" > "$AGH_STATE_DIR/proxy.state"
[ "${FAKE_PROXY_STATE:-ready}" = failed ] && exit 1
EOF
cat > "$SUPERVISOR_WORKER_DIR/file-worker.sh" <<'EOF'
#!/bin/sh
printf 'state=%s\n' "${FAKE_FILE_STATE:-ready}" > "$AGH_STATE_DIR/file.state"
[ "${FAKE_FILE_STATE:-ready}" = failed ] && exit 1
EOF
chmod 0755 "$SUPERVISOR_WORKER_DIR"/*.sh
printf 'enabled=true\n' > "$AGH_CONFIG_DIR/proxy-adapter.conf"
printf 'enabled=true\n' > "$AGH_CONFIG_DIR/file-adapter.conf"
printf 'mode=2\n' > "$AGH_CONFIG_DIR/mode.conf"

export FAKE_CORE_STATE=ready
export FAKE_FIREWALL_STATE=failed
export FAKE_PROXY_STATE=failed
export FAKE_FILE_STATE=failed
sh "$ROOT/scripts/lifecycle/supervisor.sh" once || true
grep -F 'state=ready' "$AGH_STATE_DIR/core.state" >/dev/null || fail 'optional failure changed core'
grep -F 'state=failed' "$AGH_STATE_DIR/proxy.state" >/dev/null || fail 'proxy failure not isolated'
grep -F 'state=failed' "$AGH_STATE_DIR/file.state" >/dev/null || fail 'file failure not isolated'
grep -F '纯加密上游' "$MODULE_PROP_FILE" >/dev/null || fail 'module mode description missing'

rm -f "$AGH_STATE_DIR/proxy.state" "$AGH_STATE_DIR/file.state" "$AGH_RUN_DIR/firewall/request"
touch "$AGH_STATE_DIR/paused"
export FAKE_CORE_STATE=ready
sh "$ROOT/scripts/lifecycle/supervisor.sh" once || true
[ -f "$AGH_RUN_DIR/firewall/request" ] || fail 'pause did not request firewall removal'
grep -F 'state=paused' "$AGH_STATE_DIR/proxy.state" >/dev/null || fail 'proxy pause state missing'
grep -F 'state=paused' "$AGH_STATE_DIR/file.state" >/dev/null || fail 'file pause state missing'
grep -F '已暂停' "$MODULE_PROP_FILE" >/dev/null || fail 'paused module description missing'
rm -f "$AGH_STATE_DIR/paused" "$AGH_RUN_DIR/firewall/request"

export FAKE_CORE_STATE=failed
sh "$ROOT/scripts/lifecycle/supervisor.sh" once || true
[ -f "$AGH_RUN_DIR/firewall/request" ] || fail 'core failure did not request firewall removal'
grep -F 'remove' "$AGH_RUN_DIR/firewall/request" >/dev/null || fail 'firewall removal request malformed'

printf '%s\n' 'supervisor isolation tests passed'
