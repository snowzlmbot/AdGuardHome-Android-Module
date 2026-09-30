#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
if [ "${FILE_ADAPTER_TEST_SHELL:-}" = busybox ]; then
    mkdir -p "$fixture/bin"
    printf '#!/bin/sh\nexec busybox ash "$@"\n' > "$fixture/bin/sh"
    chmod 0755 "$fixture/bin/sh"
    PATH="$fixture/bin:$PATH"
    export PATH
fi
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
rules="$ROOT/module/scripts/adapters/file-rules.sh"
reject() {
    printf '%s\n' "$1" > "$fixture/bad.conf"
    if sh "$rules" validate "$fixture/bad.conf"; then fail "unsafe manifest accepted: $1"; fi
}
accept() {
    printf '%s\n' "$1" > "$fixture/good.conf"
    sh "$rules" validate "$fixture/good.conf" || fail "safe manifest rejected: $1"
}

sh "$rules" validate "$ROOT/module/targets/file-ad-targets.conf" || fail 'maintainer manifest rejected'
reject 'root|/data|directory|medium|if-unchanged||active'
reject 'arbitrary|/etc|directory|medium|if-unchanged||active'
reject 'parent|/data/data/com.anjuke.android.app/cache/splash_ad/../../files|directory|medium|if-unchanged|com.anjuke.android.app|active'
reject 'dot|/data/data/com.anjuke.android.app/cache/./Ad|directory|medium|if-unchanged|com.anjuke.android.app|active'
reject 'slash|/data/data/com.anjuke.android.app/cache//Ad|directory|medium|if-unchanged|com.anjuke.android.app|active'
reject 'prefs-root|/data/data/com.example/shared_prefs|directory|medium|if-unchanged|com.example|active'
reject 'db-root|/data/user/10/com.tencent.mm/databases|directory|medium|if-unchanged|com.tencent.mm|active'
reject 'wechat|/data/user/10/com.tencent.mm/MicroMsg|directory|medium|if-unchanged|com.tencent.mm|active'
reject 'coolapk|/data/data/com.coolapk.market/cache|directory|medium|if-unchanged|com.coolapk.market|active'
reject 'config|/data/data/com.coocaa.familychat/app_e_qq_com_setting_7d767d052a5753acb54b111c8a40c128/sdkCloudSetting.cfg|file|low|if-unchanged|com.coocaa.familychat|active'
reject 'pictures|/data/media/0/Android/data/com.yongyou/files/Pictures|directory|medium|if-unchanged|com.yongyou|active'
reject 'trailing|/data/data/com.anjuke.android.app/cache/splash_ad/|directory|medium|if-unchanged|com.anjuke.android.app|active'
reject 'media-alias|/data/media/0/x/Android/data/com.netease.cloudmusic/cache/Ad|directory|medium|if-unchanged|com.netease.cloudmusic|active'
reject 'user-id|/data/user/010/com.anjuke.android.app/cache/splash_ad|directory|medium|if-unchanged|com.anjuke.android.app|active'
reject 'wildcard|/data/user/*/com.anjuke.android.app/cache/splash_ad|directory|medium|if-unchanged|com.anjuke.android.app|active'
reject 'mismatch|/data/data/com.anjuke.android.app/cache/splash_ad|directory|medium|if-unchanged|com.tencent.mm|active'
reject 'wrong-type|/data/data/com.anjuke.android.app/cache/splash_ad|file|low|if-unchanged|com.anjuke.android.app|active'
reject 'bad-policy|/data/data/com.anjuke.android.app/cache/splash_ad|directory|medium|force|com.anjuke.android.app|active'
reject 'extra|/data/data/com.anjuke.android.app/cache/splash_ad|directory|medium|if-unchanged|com.anjuke.android.app|active|repeat-cache|ignored'
reject 'unsafe-repeat|/data/data/com.cn21.ecloud/files/ecloud_current_screenad.obj|file|low|if-unchanged|com.cn21.ecloud|active|repeat-cache'
accept 'clone|/data/user/10/com.anjuke.android.app/cache/splash_ad|directory|medium|if-unchanged|com.anjuke.android.app|active|repeat-cache'
accept 'external|/data/media/10/Android/data/com.netease.cloudmusic/cache/Ad|directory|medium|if-unchanged|com.netease.cloudmusic|active|repeat-cache'
# A final row without LF is still validated; it must not be silently skipped.
printf '%s\n%s' 'safe|/data/data/com.cn21.ecloud/files/ecloud_current_screenad.obj|file|low|if-unchanged|com.cn21.ecloud|active' 'bad|/etc|directory|medium|if-unchanged||active' > "$fixture/bad.conf"
if sh "$rules" validate "$fixture/bad.conf"; then fail 'unterminated unsafe final row ignored'; fi

printf 'enabled=false\nmax_backup_bytes=10485760\ntarget_manifest=targets/file-ad-targets.conf\n' > "$AGH_CONFIG_DIR/file-adapter.conf"
sh "$rules" set-url 'https://github.com/example/repo/blob/main/rules.conf' || fail 'GitHub URL normalization failed'
grep -F 'rules_url=https://raw.githubusercontent.com/example/repo/main/rules.conf' "$AGH_CONFIG_DIR/file-adapter.conf" >/dev/null || fail 'raw rule URL was not stored'
grep -F 'rules_view_url=https://github.com/example/repo/blob/main/rules.conf' "$AGH_CONFIG_DIR/file-adapter.conf" >/dev/null || fail 'view URL was not stored'
config_hash=$(sha256sum "$AGH_CONFIG_DIR/file-adapter.conf")
for unsafe_url in "$(printf 'https://raw.githubusercontent.com/example/repo/main/rules.conf\nenabled=true')" 'https://raw.githubusercontent.com/example/repo/main/rules.conf#fragment' 'https://raw.githubusercontent.com/example/repo/main/a&b'; do
    if sh "$rules" set-url "$unsafe_url"; then fail 'unsafe URL could corrupt/enable config'; fi
    [ "$(sha256sum "$AGH_CONFIG_DIR/file-adapter.conf")" = "$config_hash" ] || fail 'rejected URL changed config'
done
[ "$(sha256sum "$ROOT/module/targets/file-ad-targets.conf" | cut -d ' ' -f1)" = "$(cut -d ' ' -f1 "$ROOT/module/targets/file-ad-targets.conf.sha256")" ] || fail 'maintainer checksum stale'
printf '%s\n' 'file rules tests passed'
