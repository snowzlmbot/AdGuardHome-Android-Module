#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
cleanup() {
    AGH_ROOT="$fixture/agh" AGH_RUN_DIR="$fixture/agh/run" AGH_STATE_DIR="$fixture/agh/state" AGH_LOG_DIR="$fixture/agh/logs" AGH_CONFIG_DIR="$fixture/agh/config" AGH_DATA_DIR="$fixture/agh/data" AGH_BACKUP_DIR="$fixture/agh/backup" MODDIR="$ROOT" \
      sh "$ROOT/scripts/core/core-worker.sh" stop >/dev/null 2>&1 || true
    rm -rf "$fixture"
}
trap cleanup EXIT INT TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

asset="$fixture/agh.tgz"
curl -LfsS --retry 3 --max-time 180 \
  https://github.com/AdguardTeam/AdGuardHome/releases/download/v0.107.79/AdGuardHome_linux_amd64.tar.gz \
  -o "$asset"
actual=$(sha256sum "$asset" | awk '{print $1}')
[ "$actual" = c48f4a43000665484c5ec28177de11a004759b620dae8f77b2aabefc9ef3687f ] || fail 'native tarball checksum mismatch'
tar -xzf "$asset" -C "$fixture"

export MODDIR="$ROOT"
export AGH_ROOT="$fixture/agh"
export AGH_CONFIG_DIR="$AGH_ROOT/config"
export AGH_STATE_DIR="$AGH_ROOT/state"
export AGH_RUN_DIR="$AGH_ROOT/run"
export AGH_LOG_DIR="$AGH_ROOT/logs"
export AGH_DATA_DIR="$AGH_ROOT/data"
export AGH_BACKUP_DIR="$AGH_ROOT/backup"
mkdir -p "$AGH_ROOT/bin" "$AGH_CONFIG_DIR" "$AGH_STATE_DIR" "$AGH_RUN_DIR" "$AGH_LOG_DIR" "$AGH_DATA_DIR" "$AGH_BACKUP_DIR"
cp "$fixture/AdGuardHome/AdGuardHome" "$AGH_ROOT/bin/AdGuardHome"
chmod 0755 "$AGH_ROOT/bin/AdGuardHome"
cp "$ROOT/config/default.yaml" "$AGH_CONFIG_DIR/AdGuardHome.yaml"
. "$ROOT/scripts/lib/credentials.sh"
ensure_credentials "$AGH_STATE_DIR/credentials.conf" || fail 'credential initialization failed'

CORE_START_WAIT=30 CORE_DNS_WAIT=30 sh "$ROOT/scripts/core/core-worker.sh" once || {
    sed -n '1,120p' "$AGH_LOG_DIR/core-process.log" >&2 || true
    fail 'native core initialization failed'
}
grep -F 'state=ready' "$AGH_STATE_DIR/core.state" >/dev/null || fail 'native core not ready'
if grep -q '^users:[[:space:]]*\[\]' "$AGH_CONFIG_DIR/AdGuardHome.yaml"; then fail 'users were not initialized'; fi
grep -F 'password: $2' "$AGH_CONFIG_DIR/AdGuardHome.yaml" >/dev/null || fail 'bcrypt password hash missing'
web_port=$(sed -n 's/^web_port=//p' "$AGH_STATE_DIR/ports.conf" | sed -n '1p')
curl -fsS --max-time 5 "http://127.0.0.1:$web_port/" >/dev/null || fail 'native Web UI not reachable'
sh "$ROOT/scripts/core/core-worker.sh" stop || fail 'native core stop failed'
printf '%s\n' 'native core tests passed'
