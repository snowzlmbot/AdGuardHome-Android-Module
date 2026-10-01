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
mkdir -p "$fixture/no-flock"
printf '#!/bin/sh\nexit 127\n' > "$fixture/no-flock/flock"
chmod 0755 "$fixture/no-flock/flock"
PATH="$fixture/no-flock:$PATH"
export PATH
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
export MODDIR="$ROOT/module"
# Only a filesystem fixture: manifests still contain real Android paths.
export AGH_FILE_DATA_ROOT="$fixture/data"
export AGH_ROOT="$fixture/agh"
export AGH_CONFIG_DIR="$AGH_ROOT/config"
export AGH_STATE_DIR="$AGH_ROOT/state"
export AGH_RUN_DIR="$AGH_ROOT/run"
export AGH_LOG_DIR="$AGH_ROOT/logs"
export AGH_DATA_DIR="$AGH_ROOT/data"
export AGH_BACKUP_DIR="$AGH_ROOT/backup"
worker="$ROOT/module/scripts/adapters/file-worker.sh"
reset_fixture() {
    rm -rf "$AGH_ROOT" "$AGH_FILE_DATA_ROOT" "$fixture/outside"
    mkdir -p "$AGH_CONFIG_DIR" "$AGH_STATE_DIR" "$AGH_RUN_DIR" "$AGH_FILE_DATA_ROOT/user/0" "$fixture/outside"
    ln -s "$AGH_FILE_DATA_ROOT/user/0" "$AGH_FILE_DATA_ROOT/data"
    printf 'enabled=true\nmax_backup_bytes=10485760\ntarget_manifest=%s\n' "$fixture/targets.conf" > "$AGH_CONFIG_DIR/file-adapter.conf"
}
rule() { printf '%s\n' "$1" > "$fixture/targets.conf"; }
run() {
    if [ "${FILE_ADAPTER_TEST_TRACE:-0}" = 1 ]; then
        sh -x "$worker" "$@"
    else
        sh "$worker" "$@"
    fi
}
ad_rule='ads|/data/data/com.anjuke.android.app/cache/splash_ad|directory|medium|if-unchanged|com.anjuke.android.app|active|repeat-cache'
file_rule='screen|/data/data/com.cn21.ecloud/files/ecloud_current_screenad.obj|file|low|if-unchanged|com.cn21.ecloud|active'

reset_fixture
rule "escape|$fixture/outside|directory|medium|if-unchanged|com.anjuke.android.app|active"
printf 'keep\n' > "$fixture/outside/user.txt"
if run once; then fail 'arbitrary absolute path accepted'; fi
[ -s "$fixture/outside/user.txt" ] || fail 'off-allowlist content deleted'

reset_fixture
rule "$ad_rule"
ad="$AGH_FILE_DATA_ROOT/user/0/com.anjuke.android.app/cache/splash_ad"
mkdir -p "$ad"
printf 'original\n' > "$ad/image"
printf 'enabled=false\nmax_backup_bytes=10485760\ntarget_manifest=%s\n' "$fixture/targets.conf" > "$AGH_CONFIG_DIR/file-adapter.conf"
run once || fail 'disabled worker failed'
[ -s "$ad/image" ] || fail 'disabled worker touched cache'
printf 'enabled=true\nmax_backup_bytes=10485760\ntarget_manifest=%s\n' "$fixture/targets.conf" > "$AGH_CONFIG_DIR/file-adapter.conf"
run once || fail 'initial cache clear failed'
[ ! -e "$ad/image" ] || fail 'cache was not cleared through primary-user alias'
printf 'regenerated\n' > "$ad/new-image"
run once || fail 'regenerated dedicated cache clear failed'
[ ! -e "$ad/new-image" ] || fail 'regenerated ad cache was left active'
run --clean || fail 'cache restore failed'
grep -F original "$ad/image" >/dev/null || fail 'original backup was replaced on reapply'
run --clean || fail 'second restore was not idempotent'
run once || fail 'restored target could not be applied again'
[ ! -e "$ad/image" ] || fail 'successful restore retained a stale applied record'

reset_fixture
rule "$file_rule"
file="$AGH_FILE_DATA_ROOT/user/0/com.cn21.ecloud/files/ecloud_current_screenad.obj"
mkdir -p "${file%/*}"
printf 'original-file\n' > "$file"
run once || fail 'file clear failed'
[ ! -s "$file" ] || fail 'file target not cleared'
printf 'user-edit\n' > "$file"
run once || fail 'one-shot changed target should warn, not fail'
grep -F 'reason=target_changed' "$AGH_STATE_DIR/file.state" >/dev/null || fail 'one-shot regeneration did not warn'
if run --clean; then fail 'changed file restore should warn'; fi
grep -F user-edit "$file" >/dev/null || fail 'changed file overwritten'

reset_fixture
rule "$file_rule"
file="$AGH_FILE_DATA_ROOT/user/0/com.cn21.ecloud/files/ecloud_current_screenad.obj"
mkdir -p "${file%/*}"; printf 'original\n' > "$file"
chmod 0644 "$file"
run once || fail 'metadata-change setup failed'
chmod 0600 "$file"
if run --clean; then fail 'changed target metadata ignored by restore'; fi
[ "$(stat -c '%a' "$file")" = 600 ] || fail 'restore overwrote changed target mode'
[ ! -s "$file" ] || fail 'restore overwrote metadata-edited file'

reset_fixture
rule 'splash|/data/data/com.zhihu.android/files/ad|directory|medium|if-unchanged|com.zhihu.android|active'
ad="$AGH_FILE_DATA_ROOT/user/0/com.zhihu.android/files/ad"
mkdir -p "$ad"
printf 'original\n' > "$ad/image"
run once || fail 'one-shot directory clear failed'
mkdir "$ad/user-created-empty-directory"
if run --clean; then fail 'new empty directory was ignored by restore fingerprint'; fi
[ -d "$ad/user-created-empty-directory" ] || fail 'user-created empty directory removed'

reset_fixture
printf '%s\n%s\n' "$ad_rule" 'external|/data/media/0/Android/data/com.netease.cloudmusic/cache/Ad|directory|medium|if-unchanged|com.netease.cloudmusic|active|repeat-cache' > "$fixture/targets.conf"
for user in 0 10; do
    for base in "$AGH_FILE_DATA_ROOT/user/$user/com.anjuke.android.app" "$AGH_FILE_DATA_ROOT/media/$user/Android/data/com.netease.cloudmusic"; do
        case "$base" in */com.anjuke.android.app) cache=splash_ad ;; *) cache=Ad ;; esac
        mkdir -p "$base/cache/$cache"
        printf 'ads-%s\n' "$user" > "$base/cache/$cache/image"
        mkdir -p "$base/files" "$base/databases" "$base/shared_prefs"
        printf 'keep\n' > "$base/files/user.txt"
        printf 'keep-db\n' > "$base/databases/chats.db"
        printf 'keep-config\n' > "$base/shared_prefs/config.xml"
    done
done
run once || fail 'multi-user apply failed'
grep -F 'targets_applied=4' "$AGH_STATE_DIR/file.state" >/dev/null || fail 'primary/clone/internal/external targets not all applied'
for user in 0 10; do
    for base in "$AGH_FILE_DATA_ROOT/user/$user/com.anjuke.android.app" "$AGH_FILE_DATA_ROOT/media/$user/Android/data/com.netease.cloudmusic"; do
        case "$base" in */com.anjuke.android.app) cache=splash_ad ;; *) cache=Ad ;; esac
        [ ! -e "$base/cache/$cache/image" ] || fail 'clone or external ad cache not cleared'
        [ -s "$base/files/user.txt" ] && [ -s "$base/databases/chats.db" ] && [ -s "$base/shared_prefs/config.xml" ] || fail 'non-ad user data changed'
    done
done
run --clean || fail 'multi-user restore failed'
run --clean || fail 'multi-user second restore failed'

reset_fixture
rule "$file_rule"
# Some Android versions expose /data/user/0 as a link to /data/data instead.
rm "$AGH_FILE_DATA_ROOT/data"
rmdir "$AGH_FILE_DATA_ROOT/user/0"
mkdir "$AGH_FILE_DATA_ROOT/data"
ln -s "$AGH_FILE_DATA_ROOT/data" "$AGH_FILE_DATA_ROOT/user/0"
file="$AGH_FILE_DATA_ROOT/data/com.cn21.ecloud/files/ecloud_current_screenad.obj"
mkdir -p "${file%/*}"; printf 'primary\n' > "$file"
run once || fail 'reverse primary-user alias rejected'
[ ! -s "$file" ] || fail 'reverse primary-user alias missed'
run --clean || fail 'reverse alias restore failed'

reset_fixture
rule 'clone|/data/user/10/com.cn21.ecloud/files/ecloud_current_screenad.obj|file|low|if-unchanged|com.cn21.ecloud|active'
for user in 0 10; do
    file="$AGH_FILE_DATA_ROOT/user/$user/com.cn21.ecloud/files/ecloud_current_screenad.obj"
    mkdir -p "${file%/*}"; printf 'keep-%s\n' "$user" > "$file"
done
run once com.cn21.ecloud || fail 'explicit /data/user path or package lookup rejected'
[ -s "$AGH_FILE_DATA_ROOT/user/0/com.cn21.ecloud/files/ecloud_current_screenad.obj" ] || fail 'explicit clone path touched primary user'
[ ! -s "$AGH_FILE_DATA_ROOT/user/10/com.cn21.ecloud/files/ecloud_current_screenad.obj" ] || fail 'explicit clone target missed'

reset_fixture
rule "$ad_rule"
mkdir -p "$fixture/outside/splash_ad"
printf 'keep\n' > "$fixture/outside/splash_ad/image"
mkdir -p "$AGH_FILE_DATA_ROOT/user/0/com.anjuke.android.app"
ln -s "$fixture/outside" "$AGH_FILE_DATA_ROOT/user/0/com.anjuke.android.app/cache"
if run once; then fail 'symlink ancestor accepted'; fi
[ -s "$fixture/outside/splash_ad/image" ] || fail 'ancestor symlink escaped target'

reset_fixture
rule "$ad_rule"
ad="$AGH_FILE_DATA_ROOT/user/0/com.anjuke.android.app/cache/splash_ad"
mkdir -p "$ad"
ln -s "$fixture/outside/missing" "$ad/dangling"
if run once; then fail 'dangling descendant symlink accepted'; fi
[ -L "$ad/dangling" ] || fail 'unsafe cache tree was changed'

reset_fixture
rule "$ad_rule"
ad="$AGH_FILE_DATA_ROOT/user/0/com.anjuke.android.app/cache/splash_ad"
mkdir -p "$ad"; printf 'keep\n' > "$fixture/outside/user.txt"
ln "$fixture/outside/user.txt" "$ad/linked"
if run once; then fail 'hardlinked cache descendant accepted'; fi
[ -s "$fixture/outside/user.txt" ] || fail 'hardlinked cache descendant changed'

reset_fixture
rule "$file_rule"
file="$AGH_FILE_DATA_ROOT/user/0/com.cn21.ecloud/files/ecloud_current_screenad.obj"
mkdir -p "${file%/*}"; printf 'keep-hardlink\n' > "$fixture/outside/user.txt"
ln "$fixture/outside/user.txt" "$file"
if run once; then fail 'hardlinked file accepted'; fi
[ -s "$fixture/outside/user.txt" ] || fail 'hardlinked user content truncated'

reset_fixture
rule "$file_rule"
file="$AGH_FILE_DATA_ROOT/user/0/com.cn21.ecloud/files/ecloud_current_screenad.obj"
mkdir -p "${file%/*}"; printf 'original\n' > "$file"
run once || fail 'restore-symlink setup failed'
rm -rf "$AGH_FILE_DATA_ROOT/user/0/com.cn21.ecloud/files"
printf 'keep\n' > "$fixture/outside/ecloud_current_screenad.obj"
ln -s "$fixture/outside" "$AGH_FILE_DATA_ROOT/user/0/com.cn21.ecloud/files"
if run --clean; then fail 'restore accepted replaced ancestor'; fi
grep -F keep "$fixture/outside/ecloud_current_screenad.obj" >/dev/null || fail 'restore followed attacker ancestor'

reset_fixture
rule "$ad_rule"
ad="$AGH_FILE_DATA_ROOT/user/0/com.anjuke.android.app/cache/splash_ad"
mkdir -p "$ad"; printf 'original\n' > "$ad/image"
run once || fail 'deleted-target setup failed'
rmdir "$ad"
if run --clean; then fail 'deleted directory was treated as unchanged'; fi
[ ! -e "$ad" ] || fail 'deleted app directory was recreated'
[ -s "$AGH_BACKUP_DIR/file/manifest.tsv" ] || fail 'failed restore lost backup record'

reset_fixture
rule 'legacy|/data/data/com.netease.cloudmusic/cache/MusicWebApp|directory|high|if-unchanged|com.netease.cloudmusic|blocked'
# Construct the exact v1 manifest/fingerprint for a now-blocked broad cache.
# It must remain restorable, but never become eligible for fresh cleanup.
old="$AGH_FILE_DATA_ROOT/data/com.netease.cloudmusic/cache/MusicWebApp"
mkdir -p "$old"
printf 'legacy-original\n' > "$old/image"
before=$(find "$old" -type f -print | sort | while IFS= read -r entry; do sha256sum "$entry"; done | sha256sum | cut -d ' ' -f1)
after=$(printf '' | sha256sum | cut -d ' ' -f1)
name=$(printf '%s' "$old" | sha256sum | cut -d ' ' -f1)
backup="$AGH_BACKUP_DIR/file/$name/content"
mkdir -p "${backup%/*}"
cp -pR "$old" "$backup"
printf '%s|%s|%s|directory|%s|%s|%s|%s\n' "$old" "$backup" "$before" "$(stat -c '%a' "$old")" "$(stat -c '%u' "$old")" "$(stat -c '%g' "$old")" "$after" > "$AGH_BACKUP_DIR/file/manifest.tsv"
rm "$old/image"
run --clean || fail 'v1 primary-user alias/blocked-cache restore failed'
grep -F legacy-original "$old/image" >/dev/null || fail 'v1 backup fingerprint or original path lost'
run --clean || fail 'v1 second restore failed'
run once || fail 'blocked provenance processing failed'
[ -s "$old/image" ] || fail 'now-blocked broad cache was cleaned'

reset_fixture
rule "$ad_rule"
ad="$AGH_FILE_DATA_ROOT/user/0/com.anjuke.android.app/cache/splash_ad"
mkdir -p "$ad"; printf 'original\n' > "$ad/image"
run once || fail 'tampered-backup setup failed'
backup=$(cut -d '|' -f2 "$AGH_BACKUP_DIR/file/manifest.tsv")
printf 'tampered\n' > "$backup/image"
if run --clean; then fail 'corrupt backup accepted'; fi
[ ! -e "$ad/image" ] || fail 'corrupt backup restored'

reset_fixture
rule "$ad_rule"
ad="$AGH_FILE_DATA_ROOT/user/0/com.anjuke.android.app/cache/splash_ad"
mkdir -p "$ad"; printf 'keep-locked\n' > "$ad/image"
mkdir -p "$AGH_RUN_DIR/file-adapter.lock.d"
lock_birth=$(sed 's/.*) //' "/proc/$$/stat" | awk '{print $20}')
printf '%s:%s\n' "$$" "$lock_birth" > "$AGH_RUN_DIR/file-adapter.lock.d/owner"
if run once; then fail 'concurrent adapter action ignored lock'; fi
[ -s "$ad/image" ] || fail 'locked action modified target'
rm "$AGH_RUN_DIR/file-adapter.lock.d/owner"
rmdir "$AGH_RUN_DIR/file-adapter.lock.d"

printf '%s\n' 'file adapter tests passed'
