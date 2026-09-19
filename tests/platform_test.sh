#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/module/scripts/lib/platform.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "$3 (got=$1 expected=$2)"; }

normalize_arch arm64
assert_eq "$AGH_ARCH" arm64 arm64
normalize_arch aarch64
assert_eq "$AGH_ARCH" arm64 aarch64
normalize_arch arm
assert_eq "$AGH_ARCH" armv7 arm
normalize_arch armv7
assert_eq "$AGH_ARCH" armv7 armv7
if normalize_arch x86; then fail 'x86 accepted'; fi
if normalize_arch ''; then fail 'empty architecture accepted'; fi

fixture=$(mktemp)
trap 'rm -f "$fixture" "$fixture.sha256" "$fixture.bad" "$fixture.bad.sha256" "$fixture.occupied"' EXIT

dd if=/dev/zero of="$fixture" bs=1 count=64 2>/dev/null
printf '\177ELF\002\001\001\000' | dd of="$fixture" bs=1 conv=notrunc 2>/dev/null
printf '\267\000' | dd of="$fixture" bs=1 seek=18 conv=notrunc 2>/dev/null
elf_matches_arch "$fixture" arm64 || fail 'arm64 ELF not detected'
if elf_matches_arch "$fixture" armv7; then fail 'arm64 ELF accepted as armv7'; fi

printf '%s  %s\n' "$(sha256sum "$fixture" | awk '{print $1}')" "$fixture" > "$fixture.sha256"
verify_binary "$fixture" arm64 "$fixture.sha256" || fail 'valid binary rejected'

printf '\177ELF' > "$fixture.bad"
if verify_binary "$fixture.bad" arm64 ''; then fail 'truncated binary accepted'; fi

if valid_port 80; then fail 'port 80 accepted'; fi
valid_port 30000 || fail 'port 30000 rejected'

PORT_STATE_FILE="$fixture.occupied"
printf 'web_port=35001\ndns_port=35002\n' > "$PORT_STATE_FILE"
port_is_free() { [ "$1" != 35001 ]; }
load_or_allocate_ports "$PORT_STATE_FILE" || fail 'fixed port reload failed'
[ "$PORT_WEB" = 35001 ] || fail 'existing web port changed on reinstall'
[ "$PORT_DNS" = 35002 ] || fail 'existing DNS port changed on reinstall'

printf 'web_port=35003\ndns_port=35003\n' > "$PORT_STATE_FILE"
port_is_free() { return 0; }
load_or_allocate_ports "$PORT_STATE_FILE" || fail 'collision allocation failed'
[ "$PORT_WEB" != "$PORT_DNS" ] || fail 'collision was not repaired'

printf '%s\n' 'platform tests passed'
