#!/usr/bin/env sh
set -eu

root=${1:?project root required}
busybox_bin=${BUSYBOX_BIN:-busybox}
checker=$root/tests/static/check-shell.sh
status=0

for file in $(find "$root" -type f -name '*.sh' -not -path '*/.git/*' -not -path '*/.build/*' -not -path '*/node_modules/*' -print | sort); do
    [ "$file" = "$checker" ] && continue
    "$busybox_bin" ash -n "$file" || status=1
    if grep -nE '<<<|(^|[[:space:]])\[\[[[:space:]]|(^|[[:space:]])(declare|local)[[:space:]]|[A-Za-z_][A-Za-z0-9_]*\+=\(|\$\{[^}]*//' "$file"; then
        printf '%s\n' "Bash-only syntax found in $file" >&2
        status=1
    fi
done

exit "$status"
