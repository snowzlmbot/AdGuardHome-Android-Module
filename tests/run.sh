#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUSYBOX_BIN=${BUSYBOX_BIN:-busybox}

"$ROOT/tests/static/check-shell.sh" "$ROOT"

for required in module.prop customize.sh service.sh action.sh uninstall.sh boot-completed.sh; do
    if [ ! -f "$ROOT/$required" ]; then
        printf 'missing module file: %s\n' "$required" >&2
        exit 1
    fi
done

printf '%s\n' 'static shell and package checks passed'
