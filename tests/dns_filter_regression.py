#!/usr/bin/env python3
"""Exercise the real shell config helpers; no public DNS is used by these tests."""
import hashlib
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "module"


class DNSFilterRegression(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = os.environ.copy()
        self.env.update(MODDIR=str(MODULE), AGH_ROOT=str(self.root))
        for key, directory in [("CONFIG", "config"), ("STATE", "state"),
                               ("DATA", "data"), ("BACKUP", "backup"),
                               ("RUN", "run"), ("LOG", "logs")]:
            path = self.root / directory
            path.mkdir()
            self.env[f"AGH_{key}_DIR"] = str(path)
        self.yaml = self.root / "config/AdGuardHome.yaml"
        self.mode = self.root / "config/mode.conf"
        shutil.copyfile(MODULE / "config/mode.conf", self.mode)

    def helper(self, body):
        common = shlex.quote(str(MODULE / "scripts/lib/common.sh"))
        filters = shlex.quote(str(MODULE / "scripts/lib/dns-filters.sh"))
        return subprocess.run(["sh", "-c", f". {common}; . {filters}; {body}"],
                              env=self.env, text=True, capture_output=True)

    def test_pinned_offline_rules_have_valid_digest_and_ad_domains(self):
        rules = MODULE / "rules/anti-ad-easylist.txt"
        digest = (MODULE / "rules/anti-ad-easylist.txt.sha256").read_text().split()[0]
        self.assertEqual(hashlib.sha256(rules.read_bytes()).hexdigest(), digest)
        text = rules.read_text()
        self.assertIn("||gdt.qq.com^", text)
        self.assertNotIn("||weixin.qq.com^\n", text)
        self.assertNotIn("||qq.com^\n", text)

    def test_default_filter_is_seeded_before_first_start(self):
        self.yaml.write_text("http:\n  address: 127.0.0.1:3000\ndns:\n  port: 5591\nfilters: []\nfiltering:\n  filtering_enabled: true\n")
        result = self.helper('agh_initialize_dns_filters "$AGH_CONFIG_DIR/AdGuardHome.yaml"')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("https://anti-ad.net/easylist.txt", self.yaml.read_text())
        cache = self.root / "data/data/filters/10001.txt"
        self.assertEqual(cache.read_bytes(), (MODULE / "rules/anti-ad-easylist.txt").read_bytes())

    def test_custom_filter_and_explicit_disable_survive_seed_and_restart(self):
        self.yaml.write_text("http:\n  address: 127.0.0.1:3000\ndns:\n  port: 5591\nfilters:\n  - enabled: false\n    url: https://example.org/custom.txt\n    name: Mine\n    id: 42\nfiltering:\n  filtering_enabled: false\n")
        body = 'agh_initialize_dns_filters "$AGH_CONFIG_DIR/AdGuardHome.yaml"'
        result = self.helper(body)
        self.assertEqual(result.returncode, 0, result.stderr)
        first = self.yaml.read_bytes()
        self.assertIn(b"filtering_enabled: false", first)
        self.assertIn(b"url: https://example.org/custom.txt", first)
        result = self.helper(body)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(first, self.yaml.read_bytes())
        # Removing all filters in the dashboard is a deliberate choice, not a
        # reason for the supervisor to reinsert the shipped subscription.
        self.yaml.write_text("filters: []\n")
        result = self.helper(body)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.yaml.read_text(), "filters: []\n")

    def test_mode_edit_is_scoped_to_dns_and_accepts_inline_lists(self):
        extra = "other:\n  upstream_timeout: 99s\n  cache_optimistic: false\n"
        self.yaml.write_text("dns:\n  port: 5591\n  upstream_dns: []\n  bootstrap_dns: []\n" + extra)
        helpers = " ".join(f'. {shlex.quote(str(MODULE / "scripts/lib" / name))};' for name in ("common.sh", "agh-config.sh"))
        result = subprocess.run(["sh", "-c", helpers + ' agh_apply_mode 3'], env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        text = self.yaml.read_text()
        self.assertEqual(text.count("  upstream_dns:"), 1)
        self.assertEqual(text.count("  bootstrap_dns:"), 1)
        self.assertIn(extra, text)

    def test_invalid_control_requests_fail_without_success_message(self):
        for args in [("set-mode", "99"), ("set-policy", "arbitrary", "true"),
                     ("set-policy", "block_ipv4_dot", "invalid")]:
            result = subprocess.run(["sh", str(MODULE / "scripts/lifecycle/control.sh"), *args],
                                    env=self.env, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0, (args, result.stdout))
            self.assertNotIn("mode=99", result.stdout)
            self.assertNotIn("policy=", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
