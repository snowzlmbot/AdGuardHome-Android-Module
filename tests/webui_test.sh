#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[ -f "$ROOT/webroot/index.html" ] || fail 'webroot/index.html missing'
[ -f "$ROOT/webroot/styles.css" ] || fail 'webroot/styles.css missing'
[ -f "$ROOT/webroot/app.js" ] || fail 'webroot/app.js missing'
grep -F 'window.ksu.exec' "$ROOT/webroot/app.js" >/dev/null || fail 'KernelSU exec bridge missing'
grep -F "localStorage.getItem('agh-language')" "$ROOT/webroot/app.js" >/dev/null || fail 'language persistence missing'
grep -F "reason.initial_configuration" "$ROOT/webroot/app.js" >/dev/null || fail 'localized error reason missing'
grep -F "LOCAL DNS" "$ROOT/webroot/app.js" >/dev/null || fail 'English translation missing'
grep -F "本地 DNS" "$ROOT/webroot/app.js" >/dev/null || fail 'Chinese translation missing'
grep -F 'scripts/lifecycle/control.sh' "$ROOT/webroot/app.js" >/dev/null || fail 'control path missing'
grep -F 'scripts/diagnostics/diagnostics.sh' "$ROOT/webroot/app.js" >/dev/null || fail 'diagnostics path missing'
grep -F 'data-command="start"' "$ROOT/webroot/index.html" >/dev/null || fail 'start control missing'
grep -F 'data-command="pause"' "$ROOT/webroot/index.html" >/dev/null || fail 'pause control missing'
grep -F 'id="openAdmin"' "$ROOT/webroot/index.html" >/dev/null || fail 'AdGuard Home dashboard control missing'
grep -F 'id="openQueryLog"' "$ROOT/webroot/index.html" >/dev/null || fail 'query log control missing'
grep -F 'id="showLogs"' "$ROOT/webroot/index.html" >/dev/null || fail 'module log control missing'
grep -F '/#logs?response_status=all' "$ROOT/webroot/app.js" >/dev/null || fail 'query log route missing'
grep -F 'DIAGNOSTICS} logs' "$ROOT/webroot/app.js" >/dev/null || fail 'module log command missing'
if grep -RE '<(script|link)[^>]+(src|href)="https?://' "$ROOT/webroot" 2>/dev/null | grep -v '/internal/insets.css' >/dev/null; then
    fail 'external WebUI resource found'
fi
printf '%s\n' 'webui tests passed'
