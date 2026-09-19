#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

mkdir -p "$fixture/out"
(
    cd "$fixture"
    ASSET_CACHE_DIR="$fixture/cache" "$ROOT/build/package.sh" 0.1.8 0.107.79 out > "$fixture/result"
)
package=$(sed -n '1p' "$fixture/result")
[ -f "$package" ] || fail 'package was not created'
unzip -Z1 "$package" > "$fixture/list"
grep -Fx 'bin/arm64/AdGuardHome' "$fixture/list" >/dev/null || fail 'arm64 binary missing'
grep -Fx 'bin/armv7/AdGuardHome' "$fixture/list" >/dev/null || fail 'armv7 binary missing'
grep -Fx 'SHA256SUMS' "$fixture/list" >/dev/null || fail 'SHA256SUMS missing'
grep -Fx 'service.sh' "$fixture/list" >/dev/null || fail 'service.sh missing from module root'
grep -Fx 'action.sh' "$fixture/list" >/dev/null || fail 'action.sh missing from module root'
grep -Fx 'boot-completed.sh' "$fixture/list" >/dev/null || fail 'boot-completed.sh missing from module root'
grep -Fx 'uninstall.sh' "$fixture/list" >/dev/null || fail 'uninstall.sh missing from module root'
grep -Fx 'webroot/index.html' "$fixture/list" >/dev/null || fail 'KernelSU WebUI missing'
grep -F 'upstreams/' "$fixture/list" >/dev/null && fail 'audit checkout leaked into package' || true
unzip -p "$package" bin/arm64/AdGuardHome | sha256sum | grep -F '64a9b6fc6269247f1973cddbf285aa6ce866d11bd29546b0f4135ba31d2283c8' >/dev/null || fail 'arm64 binary digest mismatch'
unzip -p "$package" bin/armv7/AdGuardHome | sha256sum | grep -F 'df4df847871d0851489c9c2933b7d81202972f84bc55c86c09d6daa914334691' >/dev/null || fail 'armv7 binary digest mismatch'

install_root="$fixture/installed-module"
data_root="$fixture/data/adb/agh"
mkdir -p "$install_root" "$fixture/modules"
cat > "$fixture/run-installer.sh" <<EOF
#!/usr/bin/env sh
ui_print() { :; }
export MODPATH='$install_root'
export ZIPFILE='$package'
export ARCH=arm64
export AGH_ROOT='$data_root'
export AGH_CONFIG_DIR='$data_root/config'
export AGH_STATE_DIR='$data_root/state'
export AGH_RUN_DIR='$data_root/run'
export AGH_LOG_DIR='$data_root/logs'
export AGH_BACKUP_DIR='$data_root/backup'
export AGH_DATA_DIR='$data_root/data'
export LEGACY_MODULES_DIR='$fixture/modules'
export INSTALL_NONINTERACTIVE=1
export INSTALL_DNS_MODE=\${INSTALL_DNS_MODE:-2}
export INSTALL_ENABLE_IPV6=true
export INSTALL_BLOCK_853=true
export INSTALL_ENABLE_PROXY=false
export INSTALL_ENABLE_FILE=false
. '$ROOT/module/customize.sh'
EOF
sh "$fixture/run-installer.sh" || fail 'customize.sh installation simulation failed'
for installed_file in service.sh action.sh boot-completed.sh uninstall.sh webroot/index.html scripts/lifecycle/supervisor.sh; do
    [ -f "$install_root/$installed_file" ] || fail "installed module missing $installed_file"
done
for runtime_file in config/AdGuardHome.yaml config/mode.conf config/proxy-adapter.conf config/file-adapter.conf state/credentials.conf state/ports.conf state/language.conf; do
    [ -f "$data_root/$runtime_file" ] || fail "persistent data missing $runtime_file"
done
grep -F 'mode=2' "$data_root/config/mode.conf" >/dev/null || fail 'installation mode choice missing'
grep -F 'redirect_ipv6_dns=true' "$data_root/config/mode.conf" >/dev/null || fail 'IPv6 option missing'
grep -F 'enabled=false' "$data_root/config/proxy-adapter.conf" >/dev/null || fail 'proxy option missing'
cp "$data_root/state/ports.conf" "$fixture/ports.before"
rm -f "$data_root/state/install-options.done"
INSTALL_DNS_MODE=3 sh "$fixture/run-installer.sh" || fail 'reinstall simulation failed'
cmp -s "$fixture/ports.before" "$data_root/state/ports.conf" || fail 'ports changed after reinstall'
grep -F 'mode=2' "$data_root/config/mode.conf" >/dev/null || fail 'saved install choices changed on reinstall'

printf '%s\n' 'package tests passed'
