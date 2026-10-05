#!/usr/bin/env python3
"""Read-only DNS acceptance over an explicitly selected, authorized ADB device.

Runs real packets as non-root UIDs. It does not prove visual removal of
same-domain advertisements, app DoH interception, or app SELinux permissions.
No credentials or historical query logs are collected.
"""
import argparse
import ipaddress
import json
from pathlib import Path
import shlex
import struct
import subprocess
import sys
import time


def packet(name, qtype):
    return (struct.pack('!6H', 0xA671, 0x0100, 1, 0, 0, 0)
            + b''.join(bytes([len(label)]) + label.encode('ascii') for label in name.split('.'))
            + b'\0' + struct.pack('!HH', qtype, 1))


def skip_name(data, offset):
    while True:
        size = data[offset]
        if size & 0xC0 == 0xC0:
            return offset + 2
        offset += 1
        if size == 0:
            return offset
        offset += size


def answers(data):
    ident, flags, questions, count, _, _ = struct.unpack('!6H', data[:12])
    assert ident == 0xA671 and flags & 0x8000, 'invalid DNS transaction'
    offset = 12
    for _ in range(questions):
        offset = skip_name(data, offset) + 4
    addresses = []
    for _ in range(count):
        offset = skip_name(data, offset)
        kind, klass, ttl, size = struct.unpack('!HHIH', data[offset:offset + 10])
        offset += 10
        raw = data[offset:offset + size]
        offset += size
        if kind in (1, 28) and klass == 1:
            addresses.append(str(ipaddress.ip_address(raw)))
    return flags & 15, addresses


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--serial', required=True)
    parser.add_argument('--dns4', required=True)
    parser.add_argument('--dns6', required=True)
    parser.add_argument('--uids', default='2000')
    parser.add_argument('--ipv6-udp-only', action='store_true', help='documented link-local TCP bypass remains a separate non-passing case')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--blocked', default='gdt.qq.com')
    parser.add_argument('--normal', default='example.com')
    args = parser.parse_args()
    rows = []
    failed = False
    for uid_text in args.uids.split(','):
        uid = int(uid_text)
        assert 0 < uid <= 4294967294, 'acceptance requires non-root UIDs'
        for family, server in ((4, args.dns4), (6, args.dns6)):
            for tcp in (False, True):
                if family == 6 and tcp and args.ipv6_udp_only:
                    continue
                for qtype in (1, 28):
                    for name, blocked in ((args.blocked, True), (args.normal, False)):
                        row: dict[str, object] = dict(uid=uid, family=family, transport='tcp' if tcp else 'udp',
                                   qtype=qtype, domain=name, blocked_expected=blocked)
                        command = '/data/local/tmp/agh-test/dnsprobe --server ' + shlex.quote(server)
                        command += ' --name ' + shlex.quote(name) + ' --type ' + str(qtype)
                        command += ' --tcp' if tcp else ''
                        started = time.monotonic()
                        try:
                            result = subprocess.run([args.adb, '-s', args.serial, 'shell',
                                                     'su', str(uid), '-c', command],
                                                    capture_output=True, timeout=8, text=True)
                            if result.returncode:
                                raise RuntimeError(result.stderr.strip() or result.stdout.strip())
                            response = json.loads(result.stdout)
                            rcode, addresses = response['rcode'], response['addresses']
                            row.update(rcode=rcode, addresses=addresses)
                            if blocked:
                                ok = rcode == 3 or (rcode == 0 and bool(addresses)
                                                    and all(ipaddress.ip_address(a).is_unspecified
                                                            for a in addresses))
                            else:
                                ok = rcode == 0 and bool(addresses) and all(
                                    not ipaddress.ip_address(a).is_unspecified for a in addresses)
                            row['passed'] = ok
                        except Exception as exc:
                            row.update(passed=False, error=str(exc))
                        row['elapsed_s'] = round(time.monotonic() - started, 3)
                        rows.append(row)
                        failed |= not row['passed']
                        args.output.parent.mkdir(parents=True, exist_ok=True)
                        args.output.write_text(json.dumps(rows, indent=2) + '\n')
                        print(json.dumps(row), flush=True)
    expected_per_uid = 12 if args.ipv6_udp_only else 16
    assert len(rows) == len(args.uids.split(',')) * expected_per_uid
    print('DNS acceptance:', sum(r['passed'] for r in rows), '/', len(rows), flush=True)
    return int(failed)


if __name__ == '__main__':
    sys.exit(main())
