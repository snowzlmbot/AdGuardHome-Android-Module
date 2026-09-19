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
mkdir -p "$AGH_CONFIG_DIR" "$AGH_STATE_DIR" "$AGH_RUN_DIR" "$fixture/cache"
if grep -v '^[[:space:]]*#' "$ROOT/targets/file-ad-targets.conf" | grep -E '/data/system/ifw|/databases/|/shared_prefs/' >/dev/null; then fail 'unsafe bundled target found'; fi
if grep -v '^[[:space:]]*#' "$ROOT/targets/file-ad-targets.conf" | awk -F'|' '$2 ~ /\/files$/ { found=1 } END { exit found ? 0 : 1 }'; then fail 'application files root bundled'; fi
printf 'ad-image\n' > "$fixture/ad.txt"
printf 'keep-image\n' > "$fixture/cache/keep.txt"
printf 'safe-file|%s|file|low|if-unchanged\nsafe-dir|%s|directory|medium|if-unchanged\nbad-ifw|/data/system/ifw|directory|high|if-unchanged\n' "$fixture/ad.txt" "$fixture/cache" > "$fixture/targets.conf"
printf 'enabled=true\nmax_backup_bytes=10485760\ntarget_manifest=%s\n' "$fixture/targets.conf" > "$AGH_CONFIG_DIR/file-adapter.conf"

sh "$ROOT/scripts/adapters/file-worker.sh" once || true
[ ! -s "$fixture/ad.txt" ] || fail 'file target was not cleared'
[ ! -e "$fixture/cache/keep.txt" ] || fail 'directory target was not cleared'
[ -s "$AGH_BACKUP_DIR/file/manifest.tsv" ] || fail 'file backup manifest missing'
grep -F 'state=failed' "$AGH_STATE_DIR/file.state" >/dev/null || fail 'protected target did not fail adapter'

sh "$ROOT/scripts/adapters/file-worker.sh" --clean || fail 'file clean failed'
grep -F 'ad-image' "$fixture/ad.txt" >/dev/null || fail 'file target was not restored'
grep -F 'keep-image' "$fixture/cache/keep.txt" >/dev/null || fail 'directory target was not restored'

sh "$ROOT/scripts/adapters/file-worker.sh" once || true
printf 'user-edit\n' >> "$fixture/ad.txt"
sh "$ROOT/scripts/adapters/file-worker.sh" --clean || fail 'changed file clean failed'
grep -F 'user-edit' "$fixture/ad.txt" >/dev/null || fail 'changed file was overwritten'
grep -F 'state=warning' "$AGH_STATE_DIR/file.state" >/dev/null || fail 'file warning state missing'

printf '%s\n' 'file adapter tests passed'
