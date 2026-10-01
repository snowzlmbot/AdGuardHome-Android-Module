#!/usr/bin/env python3
"""Stateful host-only iptables fixture; never calls the host firewall.

Implements just the commands the worker uses, including ordered insertion,
references, duplicate removal, missing-chain failures, and injected failures.
The JSON state is inspectable by regressions; it is NOT a kernel emulator.
"""
import json
import os
from pathlib import Path
import sys


def main():
    family, *args = sys.argv[1:]
    prefix = "IP6TABLES" if family == "6" else "IPTABLES"
    record = Path(os.environ[prefix + "_RECORD_FILE"])
    state = Path(os.environ.get(prefix + "_STATE_FILE", str(record) + ".state"))
    record.parent.mkdir(parents=True, exist_ok=True)
    with record.open("a", encoding="utf-8") as stream:
        stream.write(("ip6tables" if family == "6" else "iptables") + " " + " ".join(args) + "\n")
    command_text = " ".join(args)
    fail = os.environ.get(prefix + "_FAIL_MATCH", "")
    if fail and fail in command_text:
        return int(os.environ.get(prefix + "_FAIL_CODE", "1"))
    ignore = os.environ.get(prefix + "_IGNORE_MATCH", "")
    if ignore and ignore in command_text:
        return 0
    if args[:1] == ["-w"]:
        args = args[2:]
    table = "filter"
    if args[:1] == ["-t"]:
        table, args = args[1], args[2:]
    if len(args) < 2:
        return 2
    command, chain, *rule = args
    tables = json.loads(state.read_text()) if state.exists() else {
        "nat": {"OUTPUT": []}, "filter": {"OUTPUT": []}
    }
    if table not in tables:
        return 2
    chains = tables[table]
    if command == "-N":
        if chain in chains:
            return 1
        chains[chain] = []
    elif command == "-L":
        return 0 if chain in chains else 1
    elif chain not in chains:
        return 1
    elif command == "-F":
        chains[chain] = []
    elif command == "-X":
        if chain == "OUTPUT" or chains[chain]:
            return 1
        if any("-j" in item and item[item.index("-j") + 1] == chain
               for rules in chains.values() for item in rules):
            return 1
        del chains[chain]
    elif command in ("-A", "-I"):
        position = 1
        if command == "-I":
            position = int(rule.pop(0)) if rule and rule[0].isdigit() else 1
            if not 1 <= position <= len(chains[chain]) + 1:
                return 1
        if "-j" in rule:
            target = rule[rule.index("-j") + 1]
            if target not in ("ACCEPT", "DROP", "REJECT", "RETURN", "REDIRECT", "DNAT") and target not in chains:
                return 1
        if command == "-A":
            chains[chain].append(rule)
        else:
            chains[chain].insert(position - 1, rule)
    elif command == "-C":
        return 0 if rule in chains[chain] else 1
    elif command == "-D":
        if rule not in chains[chain]:
            return 1
        chains[chain].remove(rule)  # iptables removes ONE duplicate, not all.
    else:
        return 2
    state.parent.mkdir(parents=True, exist_ok=True)
    state.write_text(json.dumps(tables, sort_keys=True), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
