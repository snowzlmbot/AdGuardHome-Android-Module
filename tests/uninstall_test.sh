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
export AGH_UNINSTALL_REPORT="$fixture/uninstall-report.log"
mkdir -p "$AGH_CONFIG_DIR" "$AGH_STATE_DIR" "$AGH_RUN_DIR" "$AGH_LOG_DIR"
printf 'state=ready\nfirewall_authorized=1\n' > "$AGH_STATE_DIR/core.state"
printf 'password=super-secret\n' > "$AGH_STATE_DIR/credentials.conf"
printf 'serialno=private-device\n' > "$AGH_LOG_DIR/private.log"

sh "$ROOT/uninstall.sh" || fail 'first uninstall failed'
[ -f "$AGH_UNINSTALL_REPORT" ] || fail 'uninstall report missing'
[ ! -d "$AGH_ROOT" ] || fail 'clean uninstall left data directory'
sh "$ROOT/uninstall.sh" || fail 'repeated uninstall failed'
grep -F 'completed=true' "$AGH_UNINSTALL_REPORT" >/dev/null || fail 'uninstall completion missing'

printf '%s\n' 'uninstall tests passed'
