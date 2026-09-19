#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ui_print() { :; }

export MODDIR="$ROOT/module"
export AGH_ROOT="$fixture/agh"
export AGH_CONFIG_DIR="$AGH_ROOT/config"
export AGH_STATE_DIR="$AGH_ROOT/state"
export AGH_RUN_DIR="$AGH_ROOT/run"
export AGH_LOG_DIR="$AGH_ROOT/logs"
export AGH_BACKUP_DIR="$AGH_ROOT/backup"
export AGH_DATA_DIR="$AGH_ROOT/data"
. "$ROOT/module/scripts/lib/common.sh"
. "$ROOT/module/scripts/lib/atomic.sh"
. "$ROOT/module/scripts/lib/config.sh"
. "$ROOT/module/scripts/lib/i18n.sh"
. "$ROOT/module/scripts/lifecycle/install-options.sh"
MODULE_LANG=zh
export MODULE_LANG

ensure_dirs
cp "$ROOT/module/config/mode.conf" "$AGH_CONFIG_DIR/mode.conf"
cp "$ROOT/module/config/proxy-adapter.conf" "$AGH_CONFIG_DIR/proxy-adapter.conf"
cp "$ROOT/module/config/file-adapter.conf" "$AGH_CONFIG_DIR/file-adapter.conf"

export INSTALL_NONINTERACTIVE=1
export INSTALL_DNS_MODE=3
export INSTALL_ENABLE_IPV6=false
export INSTALL_BLOCK_853=false
export INSTALL_ENABLE_PROXY=true
export INSTALL_ENABLE_FILE=true
configure_install_options || fail 'noninteractive options failed'
grep -q '^mode=3$' "$AGH_CONFIG_DIR/mode.conf" || fail 'DNS mode choice missing'
grep -q '^redirect_ipv6_dns=false$' "$AGH_CONFIG_DIR/mode.conf" || fail 'IPv6 choice missing'
grep -q '^block_ipv4_dot=false$' "$AGH_CONFIG_DIR/mode.conf" || fail '853 choice missing'
grep -q '^enabled=true$' "$AGH_CONFIG_DIR/proxy-adapter.conf" || fail 'proxy choice missing'
grep -q '^enabled=true$' "$AGH_CONFIG_DIR/file-adapter.conf" || fail 'file choice missing'
[ -f "$AGH_STATE_DIR/install-options.done" ] || fail 'selection marker missing'

export INSTALL_DNS_MODE=1
export INSTALL_ENABLE_PROXY=false
configure_install_options || fail 'repeat options failed'
grep -q '^mode=3$' "$AGH_CONFIG_DIR/mode.conf" || fail 'repeat install overwrote saved selection'
grep -q '^enabled=true$' "$AGH_CONFIG_DIR/proxy-adapter.conf" || fail 'repeat install overwrote adapter selection'

printf '%s\n' 'install option tests passed'
