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
FOREIGN6 = deepcopy(FOREIGN)
FOREIGN6["filter"]["FOREIGN_NETD"][0][1] = "::1/128"


def rule_matches(rule, packet):
    """Small, explicit model of matches in these fixtures (not iptables itself)."""
    for option, field in (("-p", "proto"), ("--dport", "dport"),
                          ("--ctorigdstport", "original_dport"), ("--ctdir", "ctdir")):
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
        if target == "DNAT":
            address = rule[rule.index("--to-destination") + 1]
            host, port = address.rsplit(":", 1)
            packet.update(dst=host.strip("[]"), iface="lo", dnat=True, dport=int(port))
            return "DNAT"
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
        self.core = "state=ready\nfirewall_authorized=1\ndns_port=35002\ndns_ipv6_ready=true\n"
        self.network = "state=ready\nmode=2\nnetwork=wifi\nvpn=false\n"
        self.env = dict(os.environ, MODDIR=str(ROOT / "module"),
                        AGH_ROOT=str(self.base / "agh"),
                        AGH_CONFIG_DIR=str(self.config), AGH_STATE_DIR=str(self.state),
                        AGH_RUN_DIR=str(self.base / "agh/run"),
                        AGH_LOG_DIR=str(self.base / "agh/logs"),
                        AGH_DATA_DIR=str(self.base / "agh/data"),
                        AGH_BACKUP_DIR=str(self.base / "agh/backup"), FIREWALL_NO_WAIT="1",
                        IPTABLES_BIN=str(BIN / "iptables"), IP6TABLES_BIN=str(BIN / "ip6tables"),
                        IPTABLES_RECORD_FILE=str(self.base / "v4.log"),
                        IP6TABLES_RECORD_FILE=str(self.base / "v6.log"))
        # Prevent inherited test hooks or Android data paths from changing scope.
        for name in tuple(self.env):
            if name.startswith("AGH_") and name != "AGH_ROOT":
                self.env.pop(name)
            if name.startswith(("IPTABLES_", "IP6TABLES_")) and name.endswith(
                    ("_FAIL_MATCH", "_FAIL_CODE", "_IGNORE_MATCH", "_STATE_FILE",
                     "_FAIL_INSPECT", "_SNAPSHOT_FILE")):
                self.env.pop(name)
        for family, foreign in (("v4", FOREIGN), ("v6", FOREIGN6)):
            (self.base / (family + ".log.state")).write_text(json.dumps(foreign))

    def configure(self, **values):
        settings = dict(line.split("=", 1) for line in self.mode.splitlines()
                        if "=" in line and not line.startswith("#"))
        settings.update({key: str(value) for key, value in values.items()})
        self.mode = "".join(key + "=" + value + "\n" for key, value in settings.items())

    def run_worker(self, action="once", **env):
        (self.config / "mode.conf").write_text(self.mode)
        (self.state / "core.state").write_text(self.core)
        (self.state / "network.state").write_text(self.network)
        shell = ["busybox", "sh"] if os.environ.get("FIREWALL_TEST_BUSYBOX") == "1" else ["sh"]
        return subprocess.run(shell + [str(WORKER), action], env=dict(self.env, **env),
                              text=True, capture_output=True, timeout=25)

    def rules(self, family="v4"):
        return json.loads((self.base / (family + ".log.state")).read_text())

    def status(self):
        return dict(line.split("=", 1) for line in
                    (self.state / "firewall.state").read_text().splitlines())

    def packet(self, uid=110123, proto="udp", dst="192.0.2.53", dport=53,
               iface="wlan0", family="v4", dnat=False, original_dport=None, ctdir="ORIGINAL"):
        packet = dict(uid=uid, proto=proto, dst=dst, dport=dport, iface=iface, ctdir=ctdir,
                      dnat=dnat, original_dport=dport if original_dport is None else original_dport)
        rules = self.rules(family)
        traverse(rules["nat"], "OUTPUT", packet)
        packet["verdict"] = traverse(rules["filter"], "OUTPUT", packet) or "ACCEPT"
        return packet

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def assert_foreign_preserved(self, family="v4"):
        actual = self.rules(family)
        for table, chains in (FOREIGN6 if family == "v6" else FOREIGN).items():
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
            self.assertEqual(self.packet(dst="127.0.0.1", iface="lo", dport=port)["verdict"], "REJECT")
        self.assertEqual(self.packet(dst="127.0.0.1", iface="lo", dport=35002, dnat=True,
                                     original_dport=80)["verdict"], "REJECT")
        self.assertEqual(self.packet(dst="127.0.0.1", iface="lo", dport=35002, dnat=True,
                                     original_dport=53, ctdir="REPLY")["verdict"], "REJECT")
        self.assert_foreign_preserved()

    def test_root_plain_upstream_never_redirects_back_to_agh(self):
        self.assert_success(self.run_worker())
        for proto in ("udp", "tcp"):
            packet = self.packet(uid=0, proto=proto, dst="198.51.100.53")
            self.assertFalse(packet["dnat"], packet)
            self.assertEqual(packet["dport"], 53, packet)

    def test_modes_do_not_whitelist_upstream_destinations_for_apps(self):
        for mode, config in (("1", {"lan_dns_target": "192.0.2.53:53"}),
                             ("3", {"bootstrap_dns": "192.0.2.53:53,198.51.100.53:53"})):
            with self.subTest(mode=mode):
                self.network = "state=ready\nmode=" + mode + "\nnetwork=wifi\nvpn=false\n"
                self.configure(**config)
                self.assert_success(self.run_worker())
                for proto in ("udp", "tcp"):
                    packet = self.packet(uid=110123, proto=proto)
                    self.assertTrue(packet["dnat"], packet)
                    self.assertEqual(packet["verdict"], "ACCEPT", packet)
                    self.assertFalse(self.packet(uid=0, proto=proto)["dnat"])

    def test_ipv6_uses_ready_loopback_listener_not_dns_drop(self):
        self.assert_success(self.run_worker())
        self.assertEqual(self.status()["v6_redirect"], "true")
        for proto in ("tcp", "udp"):
            packet = self.packet(proto=proto, dst="2001:db8::53", family="v6")
            self.assertEqual((packet["dst"], packet["dport"], packet["verdict"]),
                             ("::1", 35002, "ACCEPT"))
            self.assertTrue(packet["dnat"])
            self.assertFalse(self.packet(uid=0, proto=proto, dst="2001:db8::53",
                                         family="v6")["dnat"])
        self.assertEqual(self.packet(dst="::1", iface="lo", dport=35002, family="v6")["verdict"], "REJECT")
        self.assertEqual(self.packet(dst="::1", iface="lo", dport=35002, family="v6", dnat=True,
                                     original_dport=80)["verdict"], "REJECT")
        self.assert_foreign_preserved("v6")

    def test_default_private_dns_and_doq_are_not_blackholed(self):
        self.assert_success(self.run_worker())
        for family, dst in (("v4", "192.0.2.53"), ("v6", "2001:db8::53")):
            for proto, port in (("tcp", 853), ("udp", 853), ("udp", 784)):
                self.assertEqual(self.packet(proto=proto, dst=dst, dport=port,
                                             family=family)["verdict"], "ACCEPT")
        self.assertFalse(any("DROP" in rule for family in ("v4", "v6")
                             for rules in self.rules(family)["filter"].values() for rule in rules))

    def test_absent_encrypted_policy_keys_also_default_to_safe(self):
        self.mode = "mode=2\nredirect_ipv4_dns=true\nredirect_ipv6_dns=false\n"
        self.assert_success(self.run_worker())
        self.assertEqual(self.packet(proto="tcp", dport=853)["verdict"], "ACCEPT")
        self.assertEqual(self.packet(dport=784)["verdict"], "ACCEPT")

    def test_explicit_encrypted_blocks_preserved_without_root_upstream_block(self):
        self.configure(block_ipv4_dot="true", block_ipv4_doq="true",
                       block_ipv6_dot="true", block_ipv6_doq="true")
        self.assert_success(self.run_worker())
        self.assertEqual((self.config / "mode.conf").read_text(), self.mode)
        for family, dst in (("v4", "192.0.2.53"), ("v6", "2001:db8::53")):
            for proto, port in (("tcp", 853), ("udp", 853), ("udp", 784)):
                self.assertEqual(self.packet(proto=proto, dst=dst, dport=port,
                                             family=family)["verdict"], "DROP")
                self.assertEqual(self.packet(uid=0, proto=proto, dst=dst, dport=port,
                                             family=family)["verdict"], "ACCEPT")

    def test_ipv6_missing_binary_nat_match_or_listener_retains_ipv4(self):
        for failure in ("binary", "nat", "allow", "jump", "listener"):
            with self.subTest(failure=failure):
                self.assert_success(self.run_worker("remove"))
                env = {}
                self.core = "state=ready\nfirewall_authorized=1\ndns_port=35002\ndns_ipv6_ready=true\n"
                if failure == "binary":
                    env["IP6TABLES_BIN"] = str(self.base / "missing-ip6tables")
                elif failure == "nat":
                    env["IP6TABLES_FAIL_MATCH"] = "-t nat -N AGHADM6N"
                elif failure == "allow":
                    env["IP6TABLES_FAIL_MATCH"] = "--ctstate DNAT"
                elif failure == "jump":
                    env["IP6TABLES_FAIL_MATCH"] = "-t nat -I OUTPUT"
                else:
                    self.core = self.core.replace("dns_ipv6_ready=true\n", "")
                self.assert_success(self.run_worker(**env))
                self.assertEqual(self.status()["state"], "degraded")
                self.assertEqual(self.status()["v4_redirect"], "true")
                self.assertEqual(self.status()["v6_redirect"], "false")
                self.assertEqual(self.packet()["verdict"], "ACCEPT")
                self.assertTrue(self.packet()["dnat"])
                self.assert_no_owned_hooks("v6")
                self.assertEqual(self.packet(dst="2001:db8::53", family="v6")["verdict"], "ACCEPT")

    def test_ipv4_failures_and_silent_noop_roll_back_before_ready(self):
        for hook, match in (("FAIL", "-t nat -N AGHADM4N"),
                            ("FAIL", "--ctstate DNAT"),
                            ("FAIL", "--uid-owner 0"),
                            ("FAIL", "-p tcp --dport 53 -j REDIRECT"),
                            ("FAIL", "-t nat -I OUTPUT"),
                            ("IGNORE", "-t nat -A AGHADM4N -p udp --dport 53"),
                            ("IGNORE", "-t filter -I OUTPUT")):
            with self.subTest(hook=hook, match=match):
                self.assert_success(self.run_worker("remove"))
                result = self.run_worker(**{"IPTABLES_" + hook + "_MATCH": match})
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.status()["state"], "degraded")
                self.assertEqual(self.status()["v4_redirect"], "false")
                self.assert_no_owned_hooks()
                self.assert_no_owned_hooks("v6")

    def test_repeated_ensure_remove_deduplicates_and_preserves_foreign(self):
        self.assert_success(self.run_worker())
        for family in ("v4", "v6"):
            rules = self.rules(family)
            for table in ("nat", "filter"):
                ours = [rule for rule in rules[table]["OUTPUT"] if any("AGHAD" in token for token in rule)]
                rules[table]["OUTPUT"].extend(deepcopy(ours))
                if table == "filter":
                    rules[table]["OUTPUT"].insert(0, rules[table]["OUTPUT"].pop(
                        rules[table]["OUTPUT"].index(["-j", "FOREIGN_NETD"])))
            (self.base / (family + ".log.state")).write_text(json.dumps(rules))
        self.assert_success(self.run_worker())
        for family, nat, filt in (("v4", "AGHADM4N", "AGHADF4"),
                                   ("v6", "AGHADM6N", "AGHADF6")):
            rules = self.rules(family)
            self.assertEqual(rules["nat"]["OUTPUT"].count(["-j", nat]), 1)
            self.assertEqual(rules["filter"]["OUTPUT"].count(["-j", filt]), 1)
            self.assertEqual(rules["filter"]["OUTPUT"][0], ["-j", filt])
            self.assert_foreign_preserved(family)
        self.assertEqual(self.packet()["verdict"], "ACCEPT")
        for _ in range(2):
            self.assert_success(self.run_worker("remove"))
            self.assertEqual(self.status()["state"], "removed")
            for family in ("v4", "v6"):
                self.assert_no_owned_hooks(family)
                self.assert_foreign_preserved(family)

    def assert_continuous_dns(self, snapshot, family, after_filter_publish=False):
        snapshots = [json.loads(line) for line in snapshot.read_text().splitlines()]
        self.assertTrue(snapshots, "fixture did not observe worker commands")
        published = not after_filter_publish
        for observation in snapshots:
            args = observation["args"]
            if "-I" in args and "filter" in args:
                published = True
            rules = observation["rules"]
            for proto in ("udp", "tcp"):
                new = dict(uid=110123, proto=proto, dst="192.0.2.53" if family == "v4" else "2001:db8::53",
                           dport=53, iface="wlan0", ctdir="ORIGINAL", dnat=False, original_dport=53)
                traverse(rules["nat"], "OUTPUT", new)
                self.assertTrue(new["dnat"], observation["args"])
                existing = dict(new, dst="127.0.0.1" if family == "v4" else "::1", dport=35002,
                                iface="lo", dnat=True)
                if published:
                    self.assertEqual(traverse(rules["filter"], "OUTPUT", existing) or "ACCEPT",
                                     "ACCEPT", observation["args"])
        self.assertTrue(published, "displaced filter hook was never repaired")

    def test_unchanged_ensure_is_verified_without_live_rule_mutations(self):
        self.assert_success(self.run_worker())
        # Match the spelling/order produced by real iptables -S, not just the
        # argv spelling stored by the fixture on its initial publication.
        for family in ("v4", "v6"):
            rules = self.rules(family)
            for chains in rules.values():
                for chain, items in chains.items():
                    if not chain.startswith("AGHAD"):
                        continue
                    for rule in items:
                        if "-d" in rule:
                            index = rule.index("-d") + 1
                            rule[index] = rule[index].replace("/32", "").replace("/128", "")
                        if "-p" in rule:
                            rule.extend(["-m", rule[rule.index("-p") + 1]])
                        if "--ctorigdstport" in rule:
                            index = rule.index("--ctorigdstport")
                            pair = rule[index:index + 2]
                            del rule[index:index + 2]
                            rule[rule.index("--ctdir"):rule.index("--ctdir")] = pair
            (self.base / (family + ".log.state")).write_text(json.dumps(rules))
        before = {family: self.rules(family) for family in ("v4", "v6")}
        snapshots = {family: self.base / (family + ".snapshots") for family in before}
        self.assert_success(self.run_worker(IPTABLES_SNAPSHOT_FILE=str(snapshots["v4"]),
                                            IP6TABLES_SNAPSHOT_FILE=str(snapshots["v6"])))
        for family in before:
            self.assert_continuous_dns(snapshots[family], family)
            self.assertEqual(self.rules(family), before[family])
            for line in snapshots[family].read_text().splitlines():
                args = json.loads(line)["args"]
                self.assertFalse(set(args) & {"-N", "-A", "-I", "-D", "-F", "-X"}, args)
        self.assertEqual(self.status()["state"], "ready")

    def test_remove_failure_is_visible_and_a_later_remove_recovers(self):
        self.assert_success(self.run_worker())
        result = self.run_worker("remove", IPTABLES_FAIL_MATCH="-t nat -D OUTPUT")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.status()["state"], "degraded")
        self.assertIn("remove", self.status()["reason"])
        self.assert_foreign_preserved()
        self.assert_success(self.run_worker("remove"))
        self.assert_no_owned_hooks()

    def test_unchanged_hook_repair_publishes_before_deleting_duplicates(self):
        self.assert_success(self.run_worker())
        snapshots = {}
        for family, nat, filt in (("v4", "AGHADM4N", "AGHADF4"),
                                  ("v6", "AGHADM6N", "AGHADF6")):
            rules = self.rules(family)
            for table, chain in (("nat", nat), ("filter", filt)):
                rules[table]["OUTPUT"].extend([["-j", chain], ["-j", chain]])
                foreign = "FOREIGN_NAT" if table == "nat" else "FOREIGN_NETD"
                rules[table]["OUTPUT"].insert(0, rules[table]["OUTPUT"].pop(
                    rules[table]["OUTPUT"].index(["-j", foreign])))
            (self.base / (family + ".log.state")).write_text(json.dumps(rules))
            snapshots[family] = self.base / (family + ".repair-snapshots")
        self.assert_success(self.run_worker(IPTABLES_SNAPSHOT_FILE=str(snapshots["v4"]),
                                            IP6TABLES_SNAPSHOT_FILE=str(snapshots["v6"])))
        for family, nat, filt in (("v4", "AGHADM4N", "AGHADF4"),
                                  ("v6", "AGHADM6N", "AGHADF6")):
            # The foreign netd hook was already rejecting before this cycle.
            # Once the first corrective mutation publishes our exemption,
            # every later command must keep both new and conntracked DNS safe.
            self.assert_continuous_dns(snapshots[family], family, after_filter_publish=True)
            mutations = [json.loads(line)["args"] for line in snapshots[family].read_text().splitlines()
                         if set(json.loads(line)["args"]) & {"-N", "-A", "-I", "-D", "-F", "-X"}]
            self.assertEqual(mutations[0][:7], ["-t", "filter", "-I", "OUTPUT", "1", "-m", "comment"])
            self.assertEqual(mutations[0][-2:], ["-j", filt])
            self.assert_foreign_preserved(family)
            for table, chain in (("nat", nat), ("filter", filt)):
                output = self.rules(family)[table]["OUTPUT"]
                self.assertEqual(output[0], ["-j", chain])
                self.assertEqual(output.count(["-j", chain]), 1)
            for line in snapshots[family].read_text().splitlines():
                args = json.loads(line)["args"]
                self.assertFalse(set(args) & {"-N", "-A", "-F", "-X"}, args)

    def test_hook_repair_preserves_foreign_rules_prepended_between_inspection_and_delete(self):
        self.assert_success(self.run_worker())
        injected = ["-m", "owner", "--uid-owner", "99999", "-j", "RETURN"]
        extra = {}
        for prefix, family in (("IPTABLES", "v4"), ("IP6TABLES", "v6")):
            rules = self.rules(family)
            for table in ("filter", "nat"):
                output = rules[table]["OUTPUT"]
                output.append(deepcopy(output[0]))
                output.insert(0, output.pop(1))  # Existing netd/foreign hook is first.
            (self.base / (family + ".log.state")).write_text(json.dumps(rules))
            pending = self.base / (family + ".prepend")
            pending.write_text(json.dumps({table: injected for table in ("filter", "nat")}))
            extra[prefix + "_PREPEND_ON_DELETE_FILE"] = str(pending)
            extra[prefix + "_SNAPSHOT_FILE"] = str(self.base / (family + ".race-snapshots"))
        result = self.run_worker(**extra)
        for family in ("v4", "v6"):
            snapshot = self.base / (family + ".race-snapshots")
            self.assert_continuous_dns(snapshot, family, after_filter_publish=True)
            for table, foreign in (FOREIGN6 if family == "v6" else FOREIGN).items():
                expected = [injected] + foreign["OUTPUT"]
                self.assertEqual([rule for rule in self.rules(family)[table]["OUTPUT"]
                                  if "AGHAD" not in " ".join(rule)], expected)
            for line in snapshot.read_text().splitlines():
                args = json.loads(line)["args"]
                if "-D" in args:
                    index = args.index("-D")
                    self.assertFalse(args[index + 2].isdigit(), args)
        self.assert_success(result)
        self.assertEqual(self.status()["state"], "ready")

    def test_interrupted_hook_repair_retains_dns_and_recovers_or_removes_exact_temporary_hook(self):
        for match in ("-I OUTPUT 1 -m comment", "-I OUTPUT 1 -j AGHADF4",
                      "-D OUTPUT -m comment"):
            for recovery in ("once", "remove"):
                with self.subTest(match=match, recovery=recovery):
                    self.assert_success(self.run_worker())
                    rules = self.rules()
                    rules["filter"]["OUTPUT"].append(["-j", "AGHADF4"])
                    (self.base / "v4.log.state").write_text(json.dumps(rules))
                    snapshot = self.base / "interrupted.snapshots"
                    snapshot.write_text("")
                    result = self.run_worker(IPTABLES_FAIL_MATCH=match,
                                             IPTABLES_SNAPSHOT_FILE=str(snapshot))
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(self.status()["state"], "degraded")
                    self.assert_continuous_dns(snapshot, "v4")
                    self.assert_foreign_preserved()
                    self.assert_success(self.run_worker(recovery))
                    self.assertFalse(list(self.state.glob("firewall-hook-*")))
                    self.assertFalse(any("--comment" in rule for table in self.rules().values()
                                         for rule in table["OUTPUT"]))
                    if recovery == "once":
                        self.assertEqual(self.status()["state"], "ready")
                        self.assertEqual(self.packet()["verdict"], "ACCEPT")
                    else:
                        self.assert_no_owned_hooks()

    def test_failed_inspection_cannot_certify_removal(self):
        self.assert_success(self.run_worker())
        for prefix, family in (("IPTABLES", "v4"), ("IP6TABLES", "v6")):
            with self.subTest(family=family):
                before = self.rules(family)
                result = self.run_worker("remove", **{prefix + "_FAIL_INSPECT": "1"})
                self.assertNotEqual(result.returncode, 0, "unreadable firewall reported removed")
                self.assertEqual(self.status()["state"], "degraded")
                self.assertEqual(self.rules(family), before, "inspection failure mutated live rules")
                self.assert_success(self.run_worker())
        self.assert_success(self.run_worker("remove"))
        for family in ("v4", "v6"):
            self.assert_no_owned_hooks(family)

    def test_missing_ipv6_tool_cannot_certify_live_redirect_removal(self):
        self.assert_success(self.run_worker())
        before = self.rules("v6")
        result = self.run_worker("remove", IP6TABLES_BIN=str(self.base / "missing-ip6tables"))
        self.assertNotEqual(result.returncode, 0, "missing tool certified a live IPv6 redirect removed")
        self.assertEqual(self.status()["state"], "degraded")
        self.assertEqual(self.rules("v6"), before)

    def test_core_readiness_port_and_authorization_are_required(self):
        for change in (("state=ready", "state=failed"),
                       ("firewall_authorized=1", "firewall_authorized=0"),
                       ("dns_port=35002", "dns_port=53")):
            with self.subTest(change=change):
                self.assert_success(self.run_worker())
                ready = self.core
                self.core = ready.replace(*change)
                self.assert_success(self.run_worker())
                self.assertEqual(self.status()["reason"], "core_not_ready")
                self.assert_no_owned_hooks()
                self.assert_no_owned_hooks("v6")
                self.core = ready

    def test_unproven_nat_detachment_preserves_live_listener_exemption(self):
        self.assert_success(self.run_worker())
        for prefix, family in (("IPTABLES", "v4"), ("IP6TABLES", "v6")):
            for hook in ("FAIL", "IGNORE"):
                with self.subTest(family=family, hook=hook):
                    before = self.rules(family)
                    result = self.run_worker("remove", **{prefix + "_" + hook + "_MATCH": "-t nat -S"})
                    try:
                        self.assertNotEqual(result.returncode, 0, "invalid inspection certified removal")
                        self.assertEqual(self.status()["state"], "degraded")
                        self.assertEqual(self.rules(family), before, "live NAT lost its DNS exemption")
                    finally:
                        self.assert_success(self.run_worker())

    def test_proven_absent_ipv6_nat_is_optional_but_general_errors_are_not(self):
        rules = self.rules("v6")
        del rules["nat"]  # CONFIG_IP6_NF_NAT is not set on the target Xiaomi.
        (self.base / "v6.log.state").write_text(json.dumps(rules))
        self.assert_success(self.run_worker())
        self.assertEqual(self.status()["state"], "degraded")
        self.assertEqual(self.status()["v4_redirect"], "true")
        self.assertEqual(self.status()["v6_redirect"], "false")
        self.assertTrue(self.packet()["dnat"])
        self.assert_success(self.run_worker("remove"))
        self.assertEqual(self.status()["state"], "removed")
        self.assertEqual(self.rules("v6"), rules)
        result = self.run_worker("remove", IP6TABLES_FAIL_MATCH="-t nat -S", IP6TABLES_FAIL_CODE="3")
        self.assertNotEqual(result.returncode, 0, "generic exit 3 mistaken for missing table")
        self.assertEqual(self.status()["state"], "degraded")

    def test_vpn_full_bypass_clears_both_families_without_false_applied_status(self):
        self.assert_success(self.run_worker())
        self.network = "state=ready\nmode=2\nnetwork=mobile\nvpn=true\n"
        self.assert_success(self.run_worker())
        self.assertEqual(self.status()["state"], "bypassed")
        self.assertEqual(self.status()["reason"], "vpn_passthrough")
        self.assertEqual(self.status()["v4_redirect"], "false")
        self.assertEqual(self.status()["v6_redirect"], "false")
        for family in ("v4", "v6"):
            self.assert_no_owned_hooks(family)
            self.assert_foreign_preserved(family)

    def test_vpn_selective_bypass_keeps_wifi_mobile_filtering(self):
        self.configure(bypass_vpn_traffic="false", block_ipv4_dot="true",
                       block_ipv6_dot="true", block_ipv4_doq="true", block_ipv6_doq="true")
        for network in ("wifi", "mobile"):
            self.network = "state=ready\nmode=2\nnetwork=" + network + "\nvpn=true\n"
            self.assert_success(self.run_worker())
            for family, dst in (("v4", "192.0.2.53"), ("v6", "2001:db8::53")):
                for iface in ("tun0", "wg0"):
                    self.assertFalse(self.packet(dst=dst, iface=iface, family=family)["dnat"])
                    self.assertEqual(self.packet(dst=dst, iface=iface, family=family,
                                                 proto="tcp", dport=853)["verdict"], "ACCEPT")
                for iface in ("wlan0", "rmnet0"):
                    self.assertTrue(self.packet(dst=dst, iface=iface, family=family)["dnat"])
                    self.assertEqual(self.packet(dst=dst, iface=iface, family=family,
                                                 proto="tcp", dport=853)["verdict"], "DROP")

    def test_disabling_redirect_respects_choice_and_preserves_system_isolation(self):
        self.configure(redirect_ipv4_dns="false", redirect_ipv6_dns="false")
        self.assert_success(self.run_worker())
        self.assertEqual(self.status()["state"], "ready")
        for family in ("v4", "v6"):
            self.assert_no_owned_hooks(family)
        self.assertFalse(self.packet()["dnat"])
        self.assertEqual(self.packet(dst="127.0.0.1", iface="lo", dport=35002)["verdict"], "REJECT")

    def test_discovery_without_exposed_dns_is_safe_until_network_not_ready(self):
        self.assert_success(self.run_worker())
        self.network = "state=failed\nmode=2\nnetwork=unknown\nvpn=false\n"
        self.assert_success(self.run_worker())
        self.assertEqual(self.status()["reason"], "network_not_ready")
        self.assert_no_owned_hooks()
        self.assert_no_owned_hooks("v6")

    def test_xtables_wait_and_filter_before_nat_publish(self):
        self.assert_success(self.run_worker(FIREWALL_NO_WAIT="0"))
        for family in ("v4", "v6"):
            lines = (self.base / (family + ".log")).read_text().splitlines()
            self.assertTrue(all(" -w 2 -t " in line for line in lines))
            filter_hook = next(i for i, line in enumerate(lines) if "-t filter -I OUTPUT" in line)
            nat_hook = next(i for i, line in enumerate(lines) if "-t nat -I OUTPUT" in line)
            self.assertLess(filter_hook, nat_hook)


if __name__ == "__main__":
    unittest.main()
