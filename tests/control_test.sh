#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
cleanup() {
    AGH_ROOT="$fixture/agh" AGH_RUN_DIR="$fixture/agh/run" MODDIR="$ROOT" \
      sh "$ROOT/scripts/lifecycle/supervisor.sh" stop >/dev/null 2>&1 || true
    rm -rf "$fixture"
}
trap cleanup EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
wait_for() {
    wait_file=$1
    wait_count=0
    while [ ! -e "$wait_file" ] && [ "$wait_count" -lt 12 ]; do
        sleep 1
        wait_count=$((wait_count + 1))
    done
    [ -e "$wait_file" ]
}

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
printf 'enabled=false\n' > "$AGH_CONFIG_DIR/proxy-adapter.conf"
printf 'enabled=false\n' > "$AGH_CONFIG_DIR/file-adapter.conf"
printf 'mode=2\n' > "$AGH_CONFIG_DIR/mode.conf"

cat > "$SUPERVISOR_WORKER_DIR/core-worker.sh" <<'EOF'
#!/bin/sh
printf 'state=ready\nfirewall_authorized=1\n' > "$AGH_STATE_DIR/core.state"
EOF
cat > "$SUPERVISOR_WORKER_DIR/network-worker.sh" <<'EOF'
#!/bin/sh
printf 'state=ready\nmode=2\nnetwork=wifi\nvpn=false\n' > "$AGH_STATE_DIR/network.state"
EOF
cat > "$SUPERVISOR_WORKER_DIR/firewall-worker.sh" <<'EOF'
#!/bin/sh
if [ -f "$AGH_RUN_DIR/firewall/request" ]; then
    rm -f "$AGH_RUN_DIR/firewall/request"
    printf 'state=removed\nreason=requested\n' > "$AGH_STATE_DIR/firewall.state"
else
    printf 'state=ready\nreason=ready\n' > "$AGH_STATE_DIR/firewall.state"
fi
EOF
chmod 0755 "$SUPERVISOR_WORKER_DIR"/*.sh

sh "$ROOT/scripts/lifecycle/control.sh" start >/dev/null
wait_for "$AGH_RUN_DIR/supervisor.pid" || fail 'start did not create supervisor pid'
first_pid=$(cat "$AGH_RUN_DIR/supervisor.pid")
kill -0 "$first_pid" 2>/dev/null || fail 'supervisor pid is not alive'
sh "$ROOT/scripts/lifecycle/control.sh" start >/dev/null
sleep 1
second_pid=$(cat "$AGH_RUN_DIR/supervisor.pid")
[ "$first_pid" = "$second_pid" ] || fail 'second start created another supervisor'

sh "$ROOT/scripts/lifecycle/control.sh" pause >/dev/null
wait_for "$AGH_STATE_DIR/paused" || fail 'pause request was not consumed'
sleep 1
grep -F 'state=removed' "$AGH_STATE_DIR/firewall.state" >/dev/null || fail 'pause did not remove firewall rules'
grep -F '已暂停' "$MODULE_PROP_FILE" >/dev/null || fail 'pause status not shown in module.prop'

sh "$ROOT/scripts/lifecycle/control.sh" resume >/dev/null
wait_count=0
while [ -e "$AGH_STATE_DIR/paused" ] && [ "$wait_count" -lt 12 ]; do
    sleep 1
    wait_count=$((wait_count + 1))
done
[ ! -e "$AGH_STATE_DIR/paused" ] || fail 'resume request was not consumed'

sh "$ROOT/scripts/lifecycle/supervisor.sh" stop >/dev/null
wait_count=0
while kill -0 "$first_pid" 2>/dev/null && [ "$wait_count" -lt 12 ]; do
    sleep 1
    wait_count=$((wait_count + 1))
done
kill -0 "$first_pid" 2>/dev/null && fail 'supervisor did not stop'

printf '%s\n' 'control tests passed'
