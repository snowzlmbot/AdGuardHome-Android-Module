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
mkdir -p "$AGH_CONFIG_DIR" "$AGH_STATE_DIR" "$AGH_RUN_DIR"

sh "$ROOT/module/scripts/adapters/file-rules.sh" validate "$ROOT/module/targets/file-ad-targets.conf" || fail 'maintainer manifest rejected'
if printf '%s\n' 'bad|/data/data/com.example/files|directory|medium|if-unchanged|com.example|active' > "$fixture/bad.conf"; then
    if sh "$ROOT/module/scripts/adapters/file-rules.sh" validate "$fixture/bad.conf"; then fail 'unsafe manifest accepted'; fi
fi

printf '%s\n' 'file rules tests passed'
