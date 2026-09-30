#!/usr/bin/env python3
"""Deterministic worker regressions. Run via `sh tests/firewall_test.sh`.

No real iptables, Root, Android, network or AGH process is used. The model only
covers rule ordering/matching used here; it does not prove kernel conntrack,
SELinux, OEM netd, or actual application ad-filter behavior on a device.
"""
from copy import deepcopy
import ipaddress
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "tests/fixtures/iptables-recording-bin"
WORKER = ROOT / "module/scripts/firewall/firewall-worker.sh"
FOREIGN = {
    "nat": {"OUTPUT": [["-j", "FOREIGN_NAT"]], "FOREIGN_NAT": []},
    "filter": {
        "OUTPUT": [["-j", "FOREIGN_NETD"]],
        "FOREIGN_NETD": [["-d", "127.0.0.0/8", "-m", "owner", "--uid-owner",
                          "100000-4294967294", "-j", "REJECT"]],
    },
}


def rule_matches(rule, packet):
    """Small, explicit model of matches in these fixtures (not iptables itself)."""
    for option, field in (("-p", "proto"), ("--dport", "dport"),
                          ("--ctorigdstport", "original_dport")):
        if option in rule and str(packet[field]) != rule[rule.index(option) + 1]:
            return False
    if "-d" in rule:
        if ipaddress.ip_address(packet["dst"]) not in ipaddress.ip_network(
                rule[rule.index("-d") + 1], strict=False):
            return False
    if "-o" in rule:
        iface = rule[rule.index("-o") + 1]
        if not (packet["iface"].startswith(iface[:-1]) if iface.endswith("+")
                else packet["iface"] == iface):
            return False
    if "--uid-owner" in rule:
        uid = rule[rule.index("--uid-owner") + 1]
        low, high = map(int, uid.split("-")) if "-" in uid else (int(uid), int(uid))
        if not low <= packet["uid"] <= high:
            return False
    if "--ctstate" in rule and rule[rule.index("--ctstate") + 1] == "DNAT":
        if not packet["dnat"]:
            return False
    return True


def traverse(chains, chain, packet):
    for rule in chains.get(chain, []):
        if not rule_matches(rule, packet):
            continue
        target = rule[rule.index("-j") + 1]
        if target == "RETURN":
            return None
        if target == "REDIRECT":
            packet.update(dst="127.0.0.1", iface="lo", dnat=True,
                          dport=int(rule[rule.index("--to-ports") + 1]))
            return "REDIRECT"
        if target in ("ACCEPT", "DROP", "REJECT"):
            return target
        verdict = traverse(chains, target, packet)
        if verdict is not None:
            return verdict
    return None


class FirewallRegression(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="agh-firewall-")
        self.addCleanup(self.scratch.cleanup)
        self.base = Path(self.scratch.name)
        self.config = self.base / "agh/config"
        self.state = self.base / "agh/state"
        self.config.mkdir(parents=True)
        self.state.mkdir(parents=True)
        self.mode = (ROOT / "module/config/mode.conf").read_text()
        self.core = "state=ready\nfirewall_authorized=1\ndns_port=35002\n"
        self.network = "state=ready\nmode=2\nnetwork=wifi\nvpn=false\n"
        self.env = dict(os.environ, MODDIR=str(ROOT / "module"),
                        AGH_ROOT=str(self.base / "agh"), FIREWALL_NO_WAIT="1",
                        IPTABLES_BIN=str(BIN / "iptables"), IP6TABLES_BIN=str(BIN / "ip6tables"),
                        IPTABLES_RECORD_FILE=str(self.base / "v4.log"),
                        IP6TABLES_RECORD_FILE=str(self.base / "v6.log"))
        # Prevent inherited test hooks or Android data paths from changing scope.
        for name in tuple(self.env):
            if name.startswith("AGH_") and name != "AGH_ROOT":
                self.env.pop(name)
            if name.startswith(("IPTABLES_", "IP6TABLES_")) and name.endswith(
                    ("_FAIL_MATCH", "_FAIL_CODE", "_IGNORE_MATCH", "_STATE_FILE")):
                self.env.pop(name)
        for family in ("v4", "v6"):
            (self.base / (family + ".log.state")).write_text(json.dumps(FOREIGN))

    def configure(self, **values):
        settings = dict(line.split("=", 1) for line in self.mode.splitlines()
                        if "=" in line and not line.startswith("#"))
        settings.update({key: str(value) for key, value in values.items()})
        self.mode = "".join(key + "=" + value + "\n" for key, value in settings.items())

    def run_worker(self, action="once", **env):
        (self.config / "mode.conf").write_text(self.mode)
        (self.state / "core.state").write_text(self.core)
        (self.state / "network.state").write_text(self.network)
        return subprocess.run(["sh", str(WORKER), action], env=dict(self.env, **env),
                              text=True, capture_output=True, timeout=25)

    def rules(self, family="v4"):
        return json.loads((self.base / (family + ".log.state")).read_text())

    def status(self):
        return dict(line.split("=", 1) for line in
                    (self.state / "firewall.state").read_text().splitlines())

    def packet(self, uid=110123, proto="udp", dst="192.0.2.53", dport=53,
               iface="wlan0", family="v4", dnat=False, original_dport=None):
        packet = dict(uid=uid, proto=proto, dst=dst, dport=dport, iface=iface,
                      dnat=dnat, original_dport=dport if original_dport is None else original_dport)
        rules = self.rules(family)
        traverse(rules["nat"], "OUTPUT", packet)
        packet["verdict"] = traverse(rules["filter"], "OUTPUT", packet) or "ACCEPT"
        return packet

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def assert_foreign_preserved(self, family="v4"):
        actual = self.rules(family)
        for table, chains in FOREIGN.items():
            for chain, rules in chains.items():
                if chain == "OUTPUT":
                    self.assertEqual([rule for rule in actual[table][chain]
                                      if "AGHAD" not in " ".join(rule)], rules)
                else:
                    self.assertEqual(actual[table][chain], rules)

    def assert_no_owned_hooks(self, family="v4"):
        rules = self.rules(family)
        for table in ("nat", "filter"):
            self.assertFalse(any("AGHAD" in " ".join(rule) for rule in rules[table]["OUTPUT"]))
        self.assert_foreign_preserved(family)

    def test_secondary_user_redirected_dns_passes_netd_only_for_real_dns(self):
        self.assert_success(self.run_worker())
        for uid in (10123, 110123, 1010123):
            for proto in ("udp", "tcp"):
                with self.subTest(uid=uid, proto=proto):
                    packet = self.packet(uid=uid, proto=proto)
                    self.assertTrue(packet["dnat"], packet)
                    self.assertEqual(packet["dport"], 35002, packet)
                    self.assertEqual(packet["verdict"], "ACCEPT", packet)
        # Never open WebUI/other loopback services, or unsolicited listener access.
        for port in (35002, 35003, 80):
            self.assertEqual(self.packet(dst="127.0.0.1", dport=port)["verdict"], "REJECT")
        self.assertEqual(self.packet(dst="127.0.0.1", dport=35002, dnat=True,
                                     original_dport=80)["verdict"], "REJECT")
        self.assert_foreign_preserved()

    def test_root_plain_upstream_never_redirects_back_to_agh(self):
        self.assert_success(self.run_worker())
        for proto in ("udp", "tcp"):
            packet = self.packet(uid=0, proto=proto, dst="198.51.100.53")
            self.assertFalse(packet["dnat"], packet)
            self.assertEqual(packet["dport"], 53, packet)


if __name__ == "__main__":
    unittest.main()
