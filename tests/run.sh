#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUSYBOX_BIN=${BUSYBOX_BIN:-busybox}

for test_script in \
    platform_test.sh \
    credentials_test.sh \
    migration_test.sh \
    install_options_test.sh \
    i18n_test.sh \
    core_worker_test.sh \
    core_native_test.sh \
    supervisor_test.sh \
    control_test.sh \
    network_test.sh \
    firewall_test.sh \
    proxy_adapter_test.sh \
    file_adapter_test.sh \
    diagnostics_test.sh \
    uninstall_test.sh \
    webui_test.sh \
    package_test.sh
do
    sh "$ROOT/tests/$test_script"
done

"$ROOT/tests/static/check-shell.sh" "$ROOT"

for required in module/module.prop module/customize.sh module/service.sh module/action.sh module/uninstall.sh module/boot-completed.sh module/webroot/index.html; do
    if [ ! -f "$ROOT/$required" ]; then
        printf 'missing module file: %s\n' "$required" >&2
        exit 1
    fi
done

printf '%s\n' 'all tests and package checks passed'
