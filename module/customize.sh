#!/system/bin/sh
SKIPUNZIP=1

MODPATH=${MODPATH:-${0%/*}}
ZIPFILE=${ZIPFILE:-}
export MODDIR="$MODPATH"

# customize.sh is sourced by the manager: abort lets it clean up a failed install.
module_abort() {
    if command -v abort >/dev/null 2>&1; then
        abort "$1"
    fi
    ui_print "! $1"
    exit 1
}

if [ -z "$ZIPFILE" ] || [ ! -f "$ZIPFILE" ]; then
    ui_print "! Installer did not provide ZIPFILE"
    module_abort 'Installation failed; see the preceding error'
fi

ui_print "- AdGuardHome Android Module"
ui_print "- Extracting module files"
unzip -o "$ZIPFILE" 'module.prop' 'customize.sh' 'service.sh' 'action.sh' 'boot-completed.sh' 'uninstall.sh' 'scripts/*' 'config/*' 'rules/*' 'targets/*' 'webroot/*' 'bin/*' 'licenses/*' 'sbom/*' 'SHA256SUMS' 'Update.json' 'README*' 'CHANGELOG.md' 'SECURITY.md' 'RELEASE_PROVENANCE.md' 'LICENSE*' 'CREDITS.md' 'THIRD_PARTY_NOTICES.md' -d "$MODPATH" >/dev/null 2>&1 || {
    ui_print "! Module extraction failed"
    module_abort 'Installation failed; see the preceding error'
}

. "$MODPATH/scripts/lib/common.sh"
. "$MODPATH/scripts/lib/atomic.sh"
. "$MODPATH/scripts/lib/platform.sh"
. "$MODPATH/scripts/lib/credentials.sh"
. "$MODPATH/scripts/lib/config.sh"
. "$MODPATH/scripts/lib/i18n.sh"
. "$MODPATH/scripts/lifecycle/migrate.sh"
. "$MODPATH/scripts/lifecycle/install-options.sh"

# Validate assets before changing persistent settings.
detect_arch || module_abort 'Unsupported CPU architecture'
binary_asset="$MODPATH/bin/$AGH_ARCH/AdGuardHome"
checksum_asset="$MODPATH/bin/$AGH_ARCH/AdGuardHome.sha256"
verify_binary "$binary_asset" "$AGH_ARCH" "$checksum_asset" || module_abort 'Binary validation failed'

if command -v set_perm_recursive >/dev/null 2>&1; then
    set_perm_recursive "$MODPATH" 0 0 0755 0644
fi
chmod 0755 "$MODPATH"/*.sh "$MODPATH"/scripts/*/*.sh || module_abort 'Cannot set script permissions'

ensure_dirs || {
    ui_print "! Cannot create persistent data directories"
    module_abort 'Installation failed; see the preceding error'
}

module_detect_language || {
    ui_print "! Language detection failed"
    module_abort 'Installation failed; see the preceding error'
}
if [ "$MODULE_LANG" = zh ]; then
    module_install_description='[安装后请重启] 支持 KernelSU WebUI；首次启动后可查看运行状态和模式'
else
    module_install_description='[Reboot required] KernelSU WebUI provides runtime status and DNS mode'
fi
sed -i "s#^description=.*#description=$module_install_description#" "$MODPATH/module.prop" || module_abort 'Installation failed; see the preceding error'

migrate_configs || {
    ui_print "! Configuration migration failed; previous data was kept"
    module_abort 'Installation failed; see the preceding error'
}

install_runtime_defaults || {
    ui_print "! Runtime configuration initialization failed"
    module_abort 'Installation failed; see the preceding error'
}

configure_install_options || {
    ui_print "! Installation option configuration failed"
    module_abort 'Installation failed; see the preceding error'
}

mkdir -p "$AGH_ROOT/bin" || module_abort 'Installation failed; see the preceding error'
binary_tmp="$AGH_ROOT/bin/.AdGuardHome.new.$$"
cp "$binary_asset" "$binary_tmp" || module_abort 'Cannot stage the core binary'
chmod 0755 "$binary_tmp" || module_abort 'Cannot set binary permissions'
agh_move "$binary_tmp" "$AGH_ROOT/bin/AdGuardHome" || module_abort 'Cannot install the core binary'

ensure_credentials "$AGH_STATE_DIR/credentials.conf" || {
    ui_print "! Credential initialization failed"
    module_abort 'Installation failed; see the preceding error'
}
load_or_allocate_ports "$AGH_STATE_DIR/ports.conf" || {
    ui_print "! Port allocation failed"
    module_abort 'Installation failed; see the preceding error'
}

ui_print "- Architecture: $AGH_ARCH"
ui_print "- Installation validation passed"
