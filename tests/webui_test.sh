#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[ -f "$ROOT/module/webroot/index.html" ] || fail 'webroot/index.html missing'
[ -f "$ROOT/module/webroot/styles.css" ] || fail 'webroot/styles.css missing'
[ -f "$ROOT/module/webroot/app.js" ] || fail 'webroot/app.js missing'
grep -F 'window.ksu.exec' "$ROOT/module/webroot/app.js" >/dev/null || fail 'KernelSU exec bridge missing'
grep -F "localStorage.getItem('agh-language')" "$ROOT/module/webroot/app.js" >/dev/null || fail 'language persistence missing'
grep -F "reason.initial_configuration" "$ROOT/module/webroot/app.js" >/dev/null || fail 'localized error reason missing'
grep -F "LOCAL DNS" "$ROOT/module/webroot/app.js" >/dev/null || fail 'English translation missing'
grep -F "本地 DNS" "$ROOT/module/webroot/app.js" >/dev/null || fail 'Chinese translation missing'
grep -F 'scripts/lifecycle/control.sh' "$ROOT/module/webroot/app.js" >/dev/null || fail 'control path missing'
grep -F 'scripts/diagnostics/diagnostics.sh' "$ROOT/module/webroot/app.js" >/dev/null || fail 'diagnostics path missing'
grep -F 'data-command="start"' "$ROOT/module/webroot/index.html" >/dev/null || fail 'start control missing'
grep -F 'data-command="pause"' "$ROOT/module/webroot/index.html" >/dev/null || fail 'pause control missing'
grep -F 'id="openAdmin"' "$ROOT/module/webroot/index.html" >/dev/null || fail 'AdGuard Home dashboard control missing'
grep -F 'id="openQueryLog"' "$ROOT/module/webroot/index.html" >/dev/null || fail 'query log control missing'
grep -F 'id="showLogs"' "$ROOT/module/webroot/index.html" >/dev/null || fail 'module log control missing'
grep -F '/#logs?response_status=all' "$ROOT/module/webroot/app.js" >/dev/null || fail 'query log route missing'
grep -F 'DIAGNOSTICS} logs' "$ROOT/module/webroot/app.js" >/dev/null || fail 'module log command missing'
if grep -RE '<(script|link)[^>]+(src|href)="https?://' "$ROOT/module/webroot" 2>/dev/null | grep -v '/internal/insets.css' >/dev/null; then
    fail 'external WebUI resource found'
fi
printf '%s\n' 'webui tests passed'
