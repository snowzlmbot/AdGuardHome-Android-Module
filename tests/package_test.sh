#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

mkdir -p "$fixture/out"
(
    cd "$fixture"
    ASSET_CACHE_DIR="$fixture/cache" "$ROOT/build/package.sh" 0.1.0 0.107.79 out > "$fixture/result"
)
package=$(sed -n '1p' "$fixture/result")
[ -f "$package" ] || fail 'package was not created'
unzip -Z1 "$package" > "$fixture/list"
grep -Fx 'bin/arm64/AdGuardHome' "$fixture/list" >/dev/null || fail 'arm64 binary missing'
grep -Fx 'bin/armv7/AdGuardHome' "$fixture/list" >/dev/null || fail 'armv7 binary missing'
grep -Fx 'SHA256SUMS' "$fixture/list" >/dev/null || fail 'SHA256SUMS missing'
grep -F 'upstreams/' "$fixture/list" >/dev/null && fail 'audit checkout leaked into package' || true
unzip -p "$package" bin/arm64/AdGuardHome | sha256sum | grep -F '64a9b6fc6269247f1973cddbf285aa6ce866d11bd29546b0f4135ba31d2283c8' >/dev/null || fail 'arm64 binary digest mismatch'
unzip -p "$package" bin/armv7/AdGuardHome | sha256sum | grep -F 'df4df847871d0851489c9c2933b7d81202972f84bc55c86c09d6daa914334691' >/dev/null || fail 'armv7 binary digest mismatch'
printf '%s\n' 'package tests passed'
