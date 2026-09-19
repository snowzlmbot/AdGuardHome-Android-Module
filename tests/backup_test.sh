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
export AGH_BACKUP_DIR="$AGH_ROOT/backup"
export AGH_DATA_DIR="$AGH_ROOT/data"
mkdir -p "$AGH_CONFIG_DIR" "$AGH_STATE_DIR" "$AGH_RUN_DIR" "$AGH_LOG_DIR" "$AGH_BACKUP_DIR" "$AGH_DATA_DIR"
cp "$ROOT/module/config/default.yaml" "$AGH_CONFIG_DIR/AdGuardHome.yaml"
printf 'mode=2\n' > "$AGH_CONFIG_DIR/mode.conf"
printf 'enabled=false\n' > "$AGH_CONFIG_DIR/proxy-adapter.conf"
printf 'enabled=false\n' > "$AGH_CONFIG_DIR/file-adapter.conf"
printf 'web_port=39873\ndns_port=39910\n' > "$AGH_STATE_DIR/ports.conf"
sh "$ROOT/module/scripts/lifecycle/backup.sh" create >/tmp/agh-backup-test.out
archive=$(sed -n '1p' /tmp/agh-backup-test.out)
[ -f "$archive" ] || fail 'backup archive missing'
rm -f "$AGH_CONFIG_DIR/AdGuardHome.yaml"
sh "$ROOT/module/scripts/lifecycle/backup.sh" restore "$archive" || fail 'backup restore failed'
[ -f "$AGH_CONFIG_DIR/AdGuardHome.yaml" ] || fail 'config was not restored'
rm -f /tmp/agh-backup-test.out
printf '%s\n' 'backup tests passed'
