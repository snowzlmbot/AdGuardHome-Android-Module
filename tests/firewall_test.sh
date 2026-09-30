#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# The fixture implements ordered/stateful iptables semantics, never host rules.
# unittest failures include worker stdout/stderr and keep each case isolated.
python3 "$ROOT/tests/firewall_regression_test.py" "$@"
