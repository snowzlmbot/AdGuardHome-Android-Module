#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/module/scripts/lib/credentials.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

state=$(mktemp)
trap 'rm -f "$state" "$state.second"' EXIT

ensure_credentials "$state" || fail 'first credential generation failed'
[ -f "$state" ] || fail 'credential state missing'
mode=$(stat -c '%a' "$state" 2>/dev/null || stat -f '%Lp' "$state")
[ "$mode" = 600 ] || fail "credential mode is $mode"
password_one=$(sed -n 's/^password=//p' "$state")
[ "${#password_one}" -ge 24 ] || fail 'generated password is too short'

ensure_credentials "$state" || fail 'credential preservation failed'
password_two=$(sed -n 's/^password=//p' "$state")
[ "$password_one" = "$password_two" ] || fail 'existing password changed'

if grep -qi 'password=' "$ROOT/module/module.prop"; then
    fail 'module metadata exposes a password'
fi

printf '%s\n' 'credential tests passed'
