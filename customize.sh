#!/system/bin/sh
SKIPUNZIP=1

MODPATH=${MODPATH:-${0%/*}}
ZIPFILE=${ZIPFILE:-}
export MODDIR="$MODPATH"

if [ -z "$ZIPFILE" ] || [ ! -f "$ZIPFILE" ]; then
    ui_print "! Installer did not provide ZIPFILE"
    exit 1
fi

ui_print "- AdGuardHome Android Module"
ui_print "- Extracting module files"
unzip -o "$ZIPFILE" 'module.prop' 'scripts/*' 'config/*' 'targets/*' 'bin/*' 'LICENSE*' 'CREDITS.md' 'THIRD_PARTY_NOTICES.md' -d "$MODPATH" >/dev/null 2>&1 || {
    ui_print "! Module extraction failed"
    exit 1
}

. "$MODPATH/scripts/lib/common.sh"
. "$MODPATH/scripts/lib/atomic.sh"
. "$MODPATH/scripts/lib/platform.sh"
. "$MODPATH/scripts/lib/credentials.sh"
. "$MODPATH/scripts/lib/config.sh"
. "$MODPATH/scripts/lifecycle/migrate.sh"

ensure_dirs || {
    ui_print "! Cannot create persistent data directories"
    exit 1
}

migrate_configs || {
    ui_print "! Configuration migration failed; previous data was kept"
    exit 1
}

detect_arch || {
    ui_print "! Unsupported CPU architecture"
    exit 1
}

binary_asset="$MODPATH/bin/$AGH_ARCH/AdGuardHome"
checksum_asset="$MODPATH/bin/$AGH_ARCH/AdGuardHome.sha256"
if [ ! -f "$binary_asset" ]; then
    ui_print "! Missing AdGuard Home asset for $AGH_ARCH"
    exit 1
fi
if [ ! -f "$checksum_asset" ]; then
    ui_print "! Missing checksum for $AGH_ARCH"
    exit 1
fi
if ! verify_binary "$binary_asset" "$AGH_ARCH" "$checksum_asset"; then
    ui_print "! AdGuard Home asset validation failed"
    exit 1
fi

mkdir -p "$AGH_ROOT/bin" || exit 1
cp -f "$binary_asset" "$AGH_ROOT/bin/AdGuardHome" || exit 1
chmod 0755 "$AGH_ROOT/bin/AdGuardHome" || exit 1

ensure_credentials "$AGH_STATE_DIR/credentials.conf" || {
    ui_print "! Credential initialization failed"
    exit 1
}
load_or_allocate_ports "$AGH_STATE_DIR/ports.conf" || {
    ui_print "! Port allocation failed"
    exit 1
}

ui_print "- Architecture: $AGH_ARCH"
ui_print "- Installation validation passed"
