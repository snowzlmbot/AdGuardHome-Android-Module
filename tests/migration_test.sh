#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export MODDIR="$ROOT"
. "$ROOT/scripts/lib/common.sh"
. "$ROOT/scripts/lib/atomic.sh"
. "$ROOT/scripts/lib/config.sh"
. "$ROOT/scripts/lifecycle/migrate.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_file_contains() { grep -F "$2" "$1" >/dev/null 2>&1 || fail "$3"; }

fixture_root=$(mktemp -d)
trap 'rm -rf "$fixture_root"' EXIT
export AGH_ROOT="$fixture_root/agh"
export AGH_CONFIG_DIR="$AGH_ROOT/config"
export AGH_STATE_DIR="$AGH_ROOT/state"
export AGH_RUN_DIR="$AGH_ROOT/run"
export AGH_LOG_DIR="$AGH_ROOT/logs"
export AGH_BACKUP_DIR="$AGH_ROOT/backup"
export AGH_DATA_DIR="$AGH_ROOT/data"
export LEGACY_MODULES_DIR="$fixture_root/modules"
mkdir -p "$LEGACY_MODULES_DIR"

migrate_configs || fail 'first install did not create defaults'
[ -f "$AGH_CONFIG_DIR/AdGuardHome.yaml" ] || fail 'default YAML missing'
[ -f "$AGH_CONFIG_DIR/mode.conf" ] || fail 'default mode missing'

rm -rf "$AGH_ROOT"
mkdir -p "$LEGACY_MODULES_DIR/AdGuardHome/data/filters"
cp "$ROOT/tests/fixtures/legacy-a/AdGuardHome.yaml" "$LEGACY_MODULES_DIR/AdGuardHome/AdGuardHome.yaml"
cp "$ROOT/tests/fixtures/legacy-a/mode.conf" "$LEGACY_MODULES_DIR/AdGuardHome/mode.conf"
printf 'filter-a\n' > "$LEGACY_MODULES_DIR/AdGuardHome/data/filters/a.txt"
migrate_configs || fail 'legacy A migration failed'
assert_file_contains "$AGH_CONFIG_DIR/AdGuardHome.yaml" 'upstream-a.example' 'legacy A YAML not migrated'
assert_file_contains "$AGH_CONFIG_DIR/mode.conf" 'mode=1' 'legacy A mode not migrated'
[ -f "$AGH_DATA_DIR/filters/a.txt" ] || fail 'legacy A filter not migrated'
[ -f "$LEGACY_MODULES_DIR/AdGuardHome/AdGuardHome.yaml" ] || fail 'legacy A source changed'

rm -rf "$AGH_ROOT" "$LEGACY_MODULES_DIR/AdGuardHome"
mkdir -p "$AGH_ROOT/bin/data/filters" "$AGH_ROOT/scripts"
cp "$ROOT/tests/fixtures/legacy-b/bin/AdGuardHome.yaml" "$AGH_ROOT/bin/AdGuardHome.yaml"
cp "$ROOT/tests/fixtures/legacy-b/scripts/config.prop" "$AGH_ROOT/scripts/config.prop"
printf 'filter-b\n' > "$AGH_ROOT/bin/data/filters/b.txt"
migrate_configs || fail 'legacy B migration failed'
assert_file_contains "$AGH_CONFIG_DIR/AdGuardHome.yaml" 'upstream-b.example' 'legacy B YAML not migrated'
assert_file_contains "$AGH_CONFIG_DIR/mode.conf" 'mode=2' 'legacy B mode not translated'
assert_file_contains "$AGH_CONFIG_DIR/proxy-adapter.conf" 'PROXY_URL=https://proxy.example' 'legacy B proxy not translated'
[ -f "$AGH_DATA_DIR/filters/b.txt" ] || fail 'legacy B filter not migrated'

rm -rf "$AGH_ROOT" "$LEGACY_MODULES_DIR/AdGuardHome"
mkdir -p "$LEGACY_MODULES_DIR/AdGuardHome" "$AGH_ROOT/bin" "$AGH_ROOT/scripts"
cp "$ROOT/tests/fixtures/legacy-a/AdGuardHome.yaml" "$LEGACY_MODULES_DIR/AdGuardHome/AdGuardHome.yaml"
cp "$ROOT/tests/fixtures/legacy-b/bin/AdGuardHome.yaml" "$AGH_ROOT/bin/AdGuardHome.yaml"
touch -t 202001010000 "$LEGACY_MODULES_DIR/AdGuardHome/AdGuardHome.yaml"
touch -t 202501010000 "$AGH_ROOT/bin/AdGuardHome.yaml"
migrate_configs || fail 'newest source migration failed'
assert_file_contains "$AGH_CONFIG_DIR/AdGuardHome.yaml" 'upstream-b.example' 'newest valid source was not selected'

rm -rf "$AGH_ROOT" "$LEGACY_MODULES_DIR/AdGuardHome"
mkdir -p "$AGH_CONFIG_DIR" "$LEGACY_MODULES_DIR/AdGuardHome"
printf 'sentinel\n' > "$AGH_CONFIG_DIR/AdGuardHome.yaml"
printf 'http:\nnot-yaml\n' > "$LEGACY_MODULES_DIR/AdGuardHome/AdGuardHome.yaml"
if migrate_configs; then fail 'malformed YAML accepted'; fi
assert_file_contains "$AGH_CONFIG_DIR/AdGuardHome.yaml" 'sentinel' 'destination changed after failed migration'

rm -rf "$AGH_ROOT" "$LEGACY_MODULES_DIR/AdGuardHome"
mkdir -p "$LEGACY_MODULES_DIR/AdGuardHome"
if migrate_configs; then fail 'missing legacy YAML accepted'; fi

printf '%s\n' 'migration tests passed'
