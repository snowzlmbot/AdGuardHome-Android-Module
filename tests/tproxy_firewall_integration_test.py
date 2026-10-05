#!/usr/bin/env python3
"""Integration of main firewall policy with optional IPv6 TPROXY lifecycle."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('firewall_fixture', ROOT/'tests/firewall_regression_test.py')
assert spec is not None and spec.loader is not None
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class TproxyFirewallIntegration(unittest.TestCase):
    def setUp(self):
        self.f = fixture.FirewallRegression()
        self.f.setUp()
        self.addCleanup(self.f.doCleanups)
        self.module = self.f.base/'module'
        shutil.copytree(ROOT/'module/scripts/lib', self.module/'scripts/lib')
        directory = self.module/'scripts/firewall'
        directory.mkdir()
        shutil.copy2(ROOT/'module/scripts/firewall/firewall-worker.sh', directory/'firewall-worker.sh')
        stub = directory/'ipv6-tproxy.sh'
        stub.write_text('''#!/bin/sh
mkdir -p "$AGH_ROOT/state"
printf '%s\\n' "$1" >> "$AGH_ROOT/tproxy-calls"
case "$1" in
 once)
  [ "${FAKE_TPROXY_FAIL:-0}" != 1 ] || exit 1
  printf 'scope=ipv6-dns-v1\\n' > "$AGH_ROOT/state/ipv6-tproxy.owner"
  printf 'state=ready\\n' > "$AGH_ROOT/state/ipv6-tproxy.state" ;;
 remove)
  [ "${FAKE_TPROXY_REMOVE_FAIL:-0}" != 1 ] || exit 1
  rm -f "$AGH_ROOT/state/ipv6-tproxy.owner"
  printf 'state=removed\\n' > "$AGH_ROOT/state/ipv6-tproxy.state" ;;
 check-ready) [ -f "$AGH_ROOT/state/ipv6-tproxy.owner" ] ;;
esac
''')
        stub.chmod(0o755)
        binary = self.f.base/'agh/bin/agh-dns-tproxy'
        binary.parent.mkdir(parents=True)
        binary.write_text('#!/bin/sh\nexit 0\n')
        binary.chmod(0o755)
        self.env = dict(self.f.env, MODDIR=str(self.module))
        tables = self.f.rules('v6')
        del tables['nat']
        (self.f.base/'v6.log.state').write_text(json.dumps(tables))

    def run_worker(self, action='once', **extra):
        (self.f.config/'mode.conf').write_text(self.f.mode)
        (self.f.state/'core.state').write_text(self.f.core)
        (self.f.state/'network.state').write_text(self.f.network)
        return subprocess.run(['sh', str(self.module/'scripts/firewall/firewall-worker.sh'), action],
                              env=dict(self.env, **extra), capture_output=True, text=True, timeout=25)

    def test_missing_nat_uses_tproxy_and_reports_applied_method(self):
        result = self.run_worker()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.f.status()['state'], 'ready')
        self.assertEqual(self.f.status()['v6_redirect'], 'true')
        self.assertEqual(self.f.status()['v6_method'], 'tproxy')
        self.assertTrue(self.f.packet()['dnat'])

    def test_nat_inspection_error_never_attempts_tproxy(self):
        result = self.run_worker(IP6TABLES_FAIL_MATCH='-t nat -S', IP6TABLES_FAIL_CODE='4')
        self.assertEqual(self.f.status()['state'], 'degraded')
        self.assertFalse((self.f.base/'agh/tproxy-calls').exists())

    def test_cleanup_failure_blocks_removed_certification(self):
        self.assertEqual(self.run_worker().returncode, 0)
        result = self.run_worker('remove', FAKE_TPROXY_REMOVE_FAIL='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.f.status()['state'], 'degraded')

    def test_disabling_ipv6_removes_its_fallback(self):
        self.assertEqual(self.run_worker().returncode, 0)
        self.f.configure(redirect_ipv6_dns='false')
        self.assertEqual(self.run_worker().returncode, 0)
        self.assertFalse((self.f.state/'ipv6-tproxy.owner').exists())
        self.assertEqual(self.f.status()['v6_redirect'], 'false')


if __name__ == '__main__':
    unittest.main(verbosity=2)
