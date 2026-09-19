#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

mkdir -p "$fixture/bin" "$fixture/state"
cat > "$fixture/bin/getprop" <<'EOF'
#!/bin/sh
printf '%s\n' "${TEST_LOCALE:-en-US}"
EOF
chmod 0755 "$fixture/bin/getprop"
PATH="$fixture/bin:$PATH"
export PATH AGH_STATE_DIR="$fixture/state" TEST_LOCALE=zh-CN
. "$ROOT/module/scripts/lib/i18n.sh"
module_detect_language || fail 'Chinese language detection failed'
[ "$MODULE_LANG" = zh ] || fail 'Chinese locale not detected'
[ "$(i18n_text 中文 English)" = 中文 ] || fail 'Chinese translation failed'

TEST_LOCALE=en-US
export TEST_LOCALE
MODULE_LANG=
module_detect_language || fail 'stored language reload failed'
[ "$MODULE_LANG" = zh ] || fail 'stored language was not preserved'

rm -f "$AGH_STATE_DIR/language.conf"
MODULE_LANG=
module_detect_language || fail 'English language detection failed'
[ "$MODULE_LANG" = en ] || fail 'English locale not detected'
[ "$(i18n_text 中文 English)" = English ] || fail 'English translation failed'
printf '%s\n' 'i18n tests passed'
