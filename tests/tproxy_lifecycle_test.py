#!/usr/bin/env python3
"""IPv6 TPROXY lifecycle: real ash/processes/sockets, isolated kernel model.

No existing recording fixture is shared. The model only replaces privileged
kernel commands; the worker, process ownership and loopback binds are real.
Run as root on Linux with busybox and a C compiler available.
"""
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKER = ROOT / 'module/scripts/firewall/ipv6-tproxy.sh'

KERNEL = r'''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
root = Path(os.environ['TPROXY_FIXTURE'])
f = root / 'kernel.json'
s = json.loads(f.read_text())
a = sys.argv[1:]
with (root / 'events').open('a') as log:
    log.write(json.dumps([Path(sys.argv[0]).name] + a) + '\n')
def save(): f.write_text(json.dumps(s))
def fail(): sys.exit(1)
if os.environ.get('TPROXY_FAIL_INSPECT') == '1' and ('-S' in a or 'show' in a): fail()
if os.environ.get('TPROXY_FAIL_MATCH') and os.environ['TPROXY_FAIL_MATCH'] in ' '.join(a): fail()
if Path(sys.argv[0]).name == 'ip':
    assert a.pop(0) == '-6'
    kind = a.pop(0)
    op = a.pop(0)
    if kind == 'rule':
        if op == 'show':
            rules = s['rules']
            if os.environ.get('TPROXY_DECIMAL_RULE') == '1':
                rules = [line.replace('0x20000000/0x20000000', '536870912/536870912') for line in rules]
            print('\n'.join(rules)); sys.exit(0)
        pref = a[a.index('pref') + 1]
        mark = a[a.index('fwmark') + 1]
        table = a[a.index('table') + 1]
        line = f'{pref}: from all fwmark {mark} lookup {table}'
        if op == 'add': s['rules'].append(line)
        elif op == 'del':
            if line not in s['rules']: fail()
            s['rules'].remove(line)
        else: fail()
    elif kind == 'route':
        assert 'table' in a
        table = a[a.index('table') + 1]
        if op == 'show':
            if os.environ.get('TPROXY_NATIVE_LISTING') == '1' and not s['routes'].get(table):
                print('Error: ipv6: FIB table does not exist.\nDump terminated', file=sys.stderr)
                sys.exit(2)
            print('\n'.join(s['routes'].get(table, []))); sys.exit(0)
        destination = a[1] if a[:1] == ['local'] else '::/0'
        device = a[a.index('dev') + 1] if 'dev' in a else 'lo'
        line = f'local {destination} dev {device} metric 1024 pref medium'
        if op == 'add':
            if os.environ.get('TPROXY_NO_ROUTE') == '1': sys.exit(0)
            s['routes'].setdefault(table, []).append(line)
        elif op == 'del':
            if line not in s['routes'].get(table, []): fail()
            s['routes'][table].remove(line)
        else: fail()
    else: fail()
else:
    if a[:1] == ['-w']: a = a[2:]
    assert a.pop(0) == '-t'
    table = a.pop(0)
    op = a.pop(0)
    if table not in s['tables']:
        print("ip6tables: can't initialize ip6tables table `" + table + "': Table does not exist", file=sys.stderr)
        sys.exit(3)
    chains = s['tables'][table]
    if op == '-S':
        for name, rules in chains.items():
            print(('-P ' + name + ' ACCEPT') if name in ['OUTPUT', 'PREROUTING', 'INPUT'] else '-N ' + name)
            for rule in rules:
                rule = list(rule)
                if os.environ.get('TPROXY_NATIVE_LISTING') == '1' and '-p' in rule:
                    i = rule.index('-p'); proto = rule[i+1]
                    del rule[i:i+2]
                    pos = 2 if rule[:1] == ['-i'] else 0
                    rule[pos:pos] = ['-p', proto]
                    if '--dport' in rule:
                        i = rule.index('--dport')
                        rule[i:i] = ['-m', proto]
                    if '--on-ip' in rule:
                        i = rule.index('--on-ip'); addr = rule[i+1]
                        del rule[i:i+2]
                        i = rule.index('--on-port')
                        rule[i+2:i+2] = ['--on-ip', addr]
                print('-A ' + name + ' ' + ' '.join(rule))
        sys.exit(0)
    chain = a.pop(0)
    if op == '-N':
        if os.environ.get('TPROXY_RACE_CHAIN') == chain:
            chains[chain] = [['-j', 'RETURN']]
            chains['PREROUTING'].append(['-j', chain])
            save(); fail()
        if chain in chains: fail()
        chains[chain] = []
    elif op == '-L':
        if chain not in chains: fail()
    elif op == '-X':
        if chains.get(chain) or any(['-j', chain] == r[-2:] for rs in chains.values() for r in rs): fail()
        if chain not in chains: fail()
        del chains[chain]
    elif op == '-F':
        assert chain not in ['OUTPUT', 'PREROUTING', 'INPUT'], 'built-in flush forbidden'
        chains[chain] = []
    elif op in ['-A', '-I']:
        if chain not in chains: fail()
        if op == '-I':
            pos = int(a.pop(0)) - 1 if a and a[0].isdigit() else 0
            chains[chain].insert(pos, a)
        else: chains[chain].append(a)
    elif op in ['-C', '-D']:
        if a not in chains.get(chain, []): fail()
        if op == '-D': chains[chain].remove(a)
    else: fail()
save()
'''

RELAY = r'''
#include <sys/socket.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
static const char *ready;
static void stop(int n) { unlink(ready); _exit(0); }
int main(int argc, char **argv) {
 int port=0, upstream=0;
 for(int i=1;i+1<argc;i+=2) {
  if(!strcmp(argv[i],"--listen-port")) port=atoi(argv[i+1]);
  if(!strcmp(argv[i],"--upstream-port")) upstream=atoi(argv[i+1]);
  if(!strcmp(argv[i],"--ready-file")) ready=argv[i+1];
 }
 if(!port || !upstream || !ready) return 2;
 struct sockaddr_in6 a={.sin6_family=AF_INET6,.sin6_port=htons(port),.sin6_addr=IN6ADDR_LOOPBACK_INIT};
 int t=socket(AF_INET6,SOCK_STREAM,0),u=socket(AF_INET6,SOCK_DGRAM,0);
 int one=1; setsockopt(t,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));
 if(bind(t,(void*)&a,sizeof(a)) || listen(t,8) || bind(u,(void*)&a,sizeof(a))) return 3;
 if(!getenv("TPROXY_RELAY_NO_READY")) {
  FILE *f=fopen(ready,"w"); if(!f) return 4;
  fprintf(f,"%d\n",getpid()); fclose(f);
 }
 signal(SIGTERM,stop); signal(SIGINT,stop);
 for(;;) pause();
}
'''


class TproxyPackagingContract(unittest.TestCase):
    def test_required_builder_is_discoverable_without_unignoring_build_outputs(self):
        builder = ROOT / 'build/build-tproxy-helper.sh'
        self.assertTrue(builder.is_file())
        self.assertTrue(os.access(builder, os.R_OK))
        with tempfile.TemporaryDirectory(prefix='tproxy-packaging-') as folder:
            repo = Path(folder)
            shutil.copy2(ROOT / '.gitignore', repo / '.gitignore')
            (repo / 'build/generated').mkdir(parents=True)
            shutil.copy2(builder, repo / 'build/build-tproxy-helper.sh')
            (repo / 'build/generated/agh-dns-tproxy').write_bytes(b'')
            subprocess.run(['git', 'init', '-q', str(repo)], check=True)
            result = subprocess.run(['git', '-C', str(repo), 'check-ignore', '-q',
                                     'build/build-tproxy-helper.sh'])
            self.assertEqual(result.returncode, 1, 'required builder is ignored in a clean checkout')
            ignored = subprocess.run(['git', '-C', str(repo), 'check-ignore', '-q',
                                      'build/generated/agh-dns-tproxy'])
            self.assertEqual(ignored.returncode, 0, 'generated build assets must remain ignored')


class TproxyLifecycle(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix='tproxy-relay-')
        cls.addClassCleanup(cls.build.cleanup)
        source = Path(cls.build.name) / 'relay.c'
        source.write_text(RELAY)
        cls.relay = source.with_suffix('')
        subprocess.run(['cc', '-O2', str(source), '-o', str(cls.relay)], check=True)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='tproxy-lifecycle-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for folder in ['config', 'state', 'run', 'logs', 'bin', 'fake']:
            (self.root / folder).mkdir()
        shutil.copy2(self.relay, self.root / 'bin/agh-dns-tproxy')
        kernel = self.root / 'fake/kernel'
        kernel.write_text(KERNEL)
        kernel.chmod(0o755)
        for name in ['ip', 'ip6tables']:
            (kernel.parent / name).symlink_to(kernel)
        self.env = dict(os.environ, AGH_ROOT=str(self.root), MODDIR=str(ROOT / 'module'),
                        TPROXY_FIXTURE=str(self.root), TPROXY_IP_BIN=str(kernel.parent / 'ip'),
                        IP6TABLES_BIN=str(kernel.parent / 'ip6tables'), TPROXY_READY_WAIT='1',
                        TPROXY_STOP_WAIT='1', PORT_SEED='123')
        self.model = {'tables': {'mangle': {'OUTPUT': [], 'PREROUTING': [], 'FOREIGN': [['-j', 'RETURN']]},
                                 'filter': {'OUTPUT': [['-j', 'netd']], 'INPUT': [], 'netd': [['-j', 'RETURN']]}},
                      'rules': ['0: from all lookup local'], 'routes': {}}
        self.save(self.model)
        (self.root / 'state/core.state').write_text('state=ready\nfirewall_authorized=1\ndns_port=5354\nweb_port=8080\n')
        (self.root / 'state/ports.conf').write_text('dns_port=5354\nweb_port=8080\n')
        self.addCleanup(self.stop_relays)

    def stop_relays(self):
        # Only test-owned processes whose executable is our isolated relay.
        for proc in Path('/proc').iterdir():
            if not proc.name.isdigit(): continue
            try:
                if (proc / 'exe').resolve() == self.root / 'bin/agh-dns-tproxy':
                    os.kill(int(proc.name), signal.SIGKILL)
            except (FileNotFoundError, ProcessLookupError, PermissionError): pass

    def save(self, model):
        (self.root / 'kernel.json').write_text(json.dumps(model))

    def kernel(self):
        return json.loads((self.root / 'kernel.json').read_text())

    def invoke(self, action='once', **extra):
        self.assertTrue(WORKER.exists(), 'IPv6 TPROXY lifecycle worker is missing')
        return subprocess.run(['busybox', 'sh', str(WORKER), action],
                              env=dict(self.env, **extra), capture_output=True, text=True, timeout=20)

    def status(self):
        return dict(line.split('=', 1) for line in (self.root / 'state/ipv6-tproxy.state').read_text().splitlines())

    def events(self):
        path = self.root / 'events'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def ok(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_real_kernel_namespace_busybox_standalone_lifecycle(self):
        busybox, ip6tables, ip = (shutil.which(name) for name in ['busybox', 'ip6tables', 'ip'])
        self.assertIsNotNone(busybox)
        self.assertIsNotNone(ip6tables)
        self.assertIsNotNone(ip)
        env = dict(self.env, AGH_BUSYBOX=str(busybox), IP6TABLES_BIN=str(ip6tables))
        env.pop('TPROXY_IP_BIN', None)
        script = '''set -e
"$NATIVE_IP" link set lo up
"$NATIVE_IP" -6 rule show > "$AGH_ROOT/rules-before"
"$IP6TABLES_BIN" -t mangle -S > "$AGH_ROOT/mangle-before"
"$IP6TABLES_BIN" -t filter -S > "$AGH_ROOT/filter-before"
busybox sh "$WORKER" once
busybox sh "$WORKER" check-ready
busybox sh "$WORKER" once
busybox sh "$WORKER" remove
"$NATIVE_IP" -6 rule show > "$AGH_ROOT/rules-after"
"$IP6TABLES_BIN" -t mangle -S > "$AGH_ROOT/mangle-after"
"$IP6TABLES_BIN" -t filter -S > "$AGH_ROOT/filter-after"
'''
        result = subprocess.run(['unshare', '-n', 'sh', '-c', script],
                                env=dict(env, NATIVE_IP=str(ip), WORKER=str(WORKER)),
                                capture_output=True, text=True, timeout=30)
        self.ok(result)
        for name in ['rules', 'mangle', 'filter']:
            self.assertEqual((self.root / (name + '-before')).read_bytes(),
                             (self.root / (name + '-after')).read_bytes())

    def test_stale_marker_never_authorizes_ready_or_publishing(self):
        self.ok(self.invoke())
        pid = self.status()['pid']
        (self.root / 'run/ipv6-tproxy.ready').write_text('999999\n')
        before = (self.root / 'kernel.json').read_bytes()
        self.assertNotEqual(self.invoke('check-ready').returncode, 0)
        self.assertEqual((self.root / 'kernel.json').read_bytes(), before)
        self.assert_relay_live(pid)
        self.ok(self.invoke())
        self.assertNotEqual(self.status()['pid'], pid)
        self.ok(self.invoke('check-ready'))

    def test_setup_race_collision_preserves_foreign_hook_and_relay(self):
        result = self.invoke(TPROXY_RACE_CHAIN='AGHAD6P')
        self.assertNotEqual(result.returncode, 0)
        actual = self.kernel()
        self.assertEqual(actual['tables']['mangle']['AGHAD6P'], [['-j', 'RETURN']])
        self.assertIn(['-j', 'AGHAD6P'], actual['tables']['mangle']['PREROUTING'])
        self.assertEqual(self.status()['state'], 'degraded')
        self.assert_relay_live(self.status()['pid'])

    def test_root_exemption_must_precede_mark_even_when_all_rules_exist(self):
        self.ok(self.invoke())
        model = self.kernel()
        rules = model['tables']['mangle']['AGHAD6O']
        rules.append(rules.pop(0))
        self.save(model)
        self.assertNotEqual(self.invoke('check-ready').returncode, 0)
        self.assertEqual(self.kernel(), model)
        self.ok(self.invoke())
        self.assertEqual(self.kernel()['tables']['mangle']['AGHAD6O'][0],
                         ['-m', 'owner', '--uid-owner', '0', '-j', 'RETURN'])

    def test_occupied_persisted_port_is_reallocated_without_touching_socket(self):
        with socket.socket(socket.AF_INET6, socket.SOCK_DGRAM) as occupied:
            occupied.bind(('::1', 0))
            port = occupied.getsockname()[1]
            (self.root / 'state/tproxy-ports.conf').write_text('relay_port=' + str(port) + '\n')
            self.ok(self.invoke())
            self.assertNotEqual(int(self.status()['listen_port']), port)
            self.assertEqual(occupied.getsockname()[1], port)
            self.ok(self.invoke('check-ready'))

    def test_route_readback_failure_never_publishes_marking(self):
        self.assertNotEqual(self.invoke(TPROXY_NO_ROUTE='1').returncode, 0)
        self.assertNotIn(['ip6tables', '-w', '2', '-t', 'mangle', '-I', 'OUTPUT', '1', '-j', 'AGHAD6O'], self.events())
        self.assertEqual(self.kernel()['tables'], self.model['tables'])
        self.assertFalse((self.root / 'run/ipv6-tproxy.pid').exists())

    def test_decimal_rule_listing_is_semantically_identical(self):
        self.ok(self.invoke(TPROXY_DECIMAL_RULE='1'))
        self.ok(self.invoke('check-ready', TPROXY_DECIMAL_RULE='1'))
        self.ok(self.invoke('remove', TPROXY_DECIMAL_RULE='1'))

    def test_native_kernel_listing_format_and_absent_route_table(self):
        self.ok(self.invoke(TPROXY_NATIVE_LISTING='1'))
        self.ok(self.invoke('check-ready', TPROXY_NATIVE_LISTING='1'))
        self.ok(self.invoke('remove', TPROXY_NATIVE_LISTING='1'))

    def assert_relay_live(self, pid):
        self.assertEqual(Path('/proc', str(pid), 'exe').resolve(), self.root / 'bin/agh-dns-tproxy')
        self.assertNotEqual(Path('/proc', str(pid), 'stat').read_text().split()[2], 'Z')

    def test_cleanup_failures_preserve_relay_while_scope_is_unknown_or_remains(self):
        for extra in [{'TPROXY_FAIL_INSPECT': '1'},
                      {'TPROXY_FAIL_MATCH': '-D OUTPUT -j AGHAD6O'},
                      {'TPROXY_FAIL_MATCH': '-D PREROUTING -j AGHAD6P'},
                      {'TPROXY_FAIL_MATCH': 'rule del'},
                      {'TPROXY_FAIL_MATCH': 'route del'}]:
            with self.subTest(extra=extra):
                self.ok(self.invoke())
                before = self.status()
                self.assertNotEqual(self.invoke('remove', **extra).returncode, 0)
                self.assertEqual(self.status()['state'], 'degraded')
                self.assertEqual(self.status()['pid'], before['pid'])
                self.assertEqual(self.status()['listen_port'], before['listen_port'])
                self.assertEqual(self.status()['upstream_port'], before['upstream_port'])
                self.assert_relay_live(before['pid'])
                self.assertTrue((self.root / 'run/ipv6-tproxy.ready').exists())
                self.assertTrue((self.root / 'state/ipv6-tproxy.owner').exists())
                self.ok(self.invoke('remove'))

    def test_foreign_scope_collision_is_never_acquired_or_modified(self):
        cases = [('rules', '105: from all fwmark 0x8/0x8 lookup 999'),
                 ('rules', '105: from all fwmark 0x20000000/0x20000000 lookup 20535'),
                 ('routes', 'local ::/0 dev lo metric 1024 pref medium'),
                 ('chain', [['-j', 'RETURN']])]
        for key, value in cases:
            with self.subTest(key=key, value=value):
                model = json.loads(json.dumps(self.model))
                if key == 'rules': model['rules'].append(value)
                elif key == 'routes': model['routes']['20535'] = [value]
                else: model['tables']['mangle']['AGHAD6O'] = value
                self.save(model)
                self.assertNotEqual(self.invoke().returncode, 0)
                self.assertEqual(self.kernel(), model)
                self.assertFalse((self.root / 'state/ipv6-tproxy.owner').exists())
                self.assertFalse((self.root / 'run/ipv6-tproxy.pid').exists())
                self.assertNotEqual(self.invoke('remove').returncode, 0)
                self.assertEqual(self.kernel(), model)
        self.save(self.model)
        self.assertNotEqual(self.invoke(TPROXY_FAIL_INSPECT='1').returncode, 0)
        self.assertEqual(self.kernel(), self.model)
        self.assertFalse((self.root / 'state/ipv6-tproxy.owner').exists())

    def test_unknown_additions_inside_owned_chain_are_not_deleted(self):
        self.ok(self.invoke())
        pid = self.status()['pid']
        model = self.kernel()
        foreign = ['-p', 'tcp', '--dport', '443', '-j', 'RETURN']
        model['tables']['mangle']['AGHAD6O'].append(foreign)
        self.save(model)
        self.assertNotEqual(self.invoke('remove').returncode, 0)
        self.assertIn(foreign, self.kernel()['tables']['mangle']['AGHAD6O'])
        self.assert_relay_live(pid)
        self.assertTrue(self.kernel()['routes']['20535'])

    def test_upstream_change_replaces_only_after_detaching_and_reuses_port(self):
        self.ok(self.invoke())
        old = self.status()
        (self.root / 'state/core.state').write_text('state=ready\nfirewall_authorized=1\ndns_port=5454\nweb_port=8080\n')
        self.assertNotEqual(self.invoke('check-ready').returncode, 0)
        (self.root / 'events').write_text('')
        self.ok(self.invoke())
        self.assertNotEqual(self.status()['pid'], old['pid'])
        self.assertEqual(self.status()['listen_port'], old['listen_port'])
        self.assertEqual(self.status()['upstream_port'], '5454')
        mutations = [e for e in self.events() if '-S' not in e and 'show' not in e]
        self.assertEqual(mutations[0], ['ip6tables', '-w', '2', '-t', 'mangle', '-D', 'OUTPUT', '-j', 'AGHAD6O'])
        self.ok(self.invoke('check-ready'))

    def test_core_authorization_revocation_detaches_before_relay_stop(self):
        self.ok(self.invoke())
        (self.root / 'state/core.state').write_text('state=ready\nfirewall_authorized=0\ndns_port=5354\n')
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertEqual(self.status()['state'], 'degraded')
        self.assertIn('core_not_ready', self.status()['reason'])
        self.assertEqual(self.kernel()['tables'], self.model['tables'])
        self.assertFalse((self.root / 'run/ipv6-tproxy.pid').exists())

    def test_failed_setup_rolls_back_before_stopping_unpublished_relay(self):
        for extra in [{'TPROXY_RELAY_NO_READY': '1'},
                      {'TPROXY_FAIL_MATCH': 'rule add'},
                      {'TPROXY_FAIL_MATCH': '-I OUTPUT 1 -j AGHAD6T'},
                      {'TPROXY_FAIL_MATCH': '-I OUTPUT 1 -j AGHAD6O'}]:
            with self.subTest(extra=extra):
                result = self.invoke(**extra)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.status()['state'], 'degraded')
                self.assertEqual(self.kernel()['tables'], self.model['tables'])
                self.assertEqual(self.kernel()['rules'], self.model['rules'])
                self.assertFalse(self.kernel()['routes'].get('20535', []))
                self.assertFalse((self.root / 'run/ipv6-tproxy.pid').exists())
                self.assertFalse((self.root / 'state/ipv6-tproxy.owner').exists())

    def test_remove_detaches_first_then_removes_exact_scope_and_stops_relay(self):
        self.ok(self.invoke())
        pid = self.status()['pid']
        port = self.status()['listen_port']
        model = self.kernel()
        model['rules'].append('120: from all fwmark 0x8/0x8 lookup 999')
        model['routes']['999'] = ['local ::/0 dev lo metric 1024 pref medium']
        self.save(model)
        (self.root / 'events').write_text('')
        self.ok(self.invoke('remove'))
        self.assertEqual(self.status()['state'], 'removed')
        remaining = self.kernel()
        self.assertEqual(remaining['tables'], self.model['tables'])
        self.assertEqual(remaining['rules'], ['0: from all lookup local', '120: from all fwmark 0x8/0x8 lookup 999'])
        self.assertEqual(remaining['routes']['20535'], [])
        self.assertEqual(remaining['routes']['999'], model['routes']['999'])
        mutations = [e for e in self.events() if '-S' not in e and 'show' not in e]
        self.assertEqual(mutations[0], ['ip6tables', '-w', '2', '-t', 'mangle', '-D', 'OUTPUT', '-j', 'AGHAD6O'])
        self.assertFalse((self.root / 'run/ipv6-tproxy.ready').exists())
        if Path('/proc', pid).exists():
            self.assertEqual((Path('/proc', pid) / 'stat').read_text().split()[2], 'Z')
        self.assertEqual((self.root / 'state/tproxy-ports.conf').read_text(), 'relay_port=' + port + '\n')
        self.assertFalse((self.root / 'state/ipv6-tproxy.owner').exists())
        self.ok(self.invoke('remove'))

    def test_unchanged_refresh_and_check_ready_do_not_mutate(self):
        self.ok(self.invoke())
        before_kernel = (self.root / 'kernel.json').read_bytes()
        before_state = (self.root / 'state/ipv6-tproxy.state').stat().st_mtime_ns
        pid = self.status()['pid']
        (self.root / 'events').write_text('')
        self.ok(self.invoke('check-ready'))
        self.ok(self.invoke())
        self.assertEqual(self.status()['pid'], pid)
        self.assertEqual((self.root / 'kernel.json').read_bytes(), before_kernel)
        self.assertEqual((self.root / 'state/ipv6-tproxy.state').stat().st_mtime_ns, before_state)
        self.assertTrue(all('-S' in e or '-C' in e or 'show' in e for e in self.events()), self.events())

    def main_firewall_env(self):
        (self.root / 'config/mode.conf').write_text(
            'redirect_ipv4_dns=true\nredirect_ipv6_dns=true\nblock_ipv6_dot=true\nblock_ipv6_doq=true\n')
        (self.root / 'state/core.state').write_text(
            'state=ready\nfirewall_authorized=1\ndns_port=5354\nweb_port=8080\ndns_ipv6_ready=true\n')
        (self.root / 'state/network.state').write_text('state=ready\nmode=2\nnetwork=wifi\nvpn=false\n')
        return dict(self.env, AGH_BUSYBOX=str(shutil.which('busybox')),
                    IPTABLES_BIN=str(ROOT / 'tests/fixtures/iptables-recording-bin/iptables'),
                    IPTABLES_RECORD_FILE=str(self.root / 'v4-events'))

    def test_selective_vpn_dns_bypass_keeps_wifi_redirect_and_unchanged_refresh(self):
        env = self.main_firewall_env()
        (self.root / 'config/mode.conf').write_text(
            'redirect_ipv4_dns=true\nredirect_ipv6_dns=true\nbypass_vpn_traffic=false\nbypass_vpn_dns=true\n')
        (self.root / 'state/network.state').write_text('state=ready\nmode=2\nnetwork=wifi\nvpn=true\n')
        main = ROOT / 'module/scripts/firewall/firewall-worker.sh'
        def refresh():
            self.ok(subprocess.run(['busybox', 'sh', str(main), 'once'], env=env,
                                   capture_output=True, text=True, timeout=25))
        refresh()
        rules = self.kernel()['tables']['mangle']['AGHAD6O']
        self.assertEqual(rules[0], ['-m', 'owner', '--uid-owner', '0', '-j', 'RETURN'])
        first_mark = next(i for i, rule in enumerate(rules) if 'MARK' in rule)
        for iface in ('tun+', 'tap+', 'wg+', 'ppp+', 'tailscale+'):
            bypass = ['-o', iface, '-j', 'RETURN']
            self.assertIn(bypass, rules, 'VPN DNS egress must bypass TPROXY marking')
            self.assertLess(rules.index(bypass), first_mark)
        self.assertNotIn(['-o', 'wlan+', '-j', 'RETURN'], rules)
        self.assertEqual(sum('MARK' in rule for rule in rules), 2)
        pid = self.status()['pid']
        before = (self.root / 'kernel.json').read_bytes()
        state_mtime = (self.root / 'state/ipv6-tproxy.state').stat().st_mtime_ns
        (self.root / 'events').write_text('')
        self.ok(self.invoke('check-ready'))
        refresh()
        self.assertEqual(self.status()['pid'], pid)
        self.assertEqual((self.root / 'kernel.json').read_bytes(), before)
        self.assertEqual((self.root / 'state/ipv6-tproxy.state').stat().st_mtime_ns, state_mtime)
        self.assertTrue(all('-S' in e or '-C' in e or 'show' in e for e in self.events()), self.events())

    def test_vpn_egress_return_after_dns_mark_is_not_ready(self):
        (self.root / 'config/mode.conf').write_text('bypass_vpn_dns=true\n')
        (self.root / 'state/network.state').write_text('state=ready\nvpn=true\n')
        self.ok(self.invoke())
        model = self.kernel()
        rules = model['tables']['mangle']['AGHAD6O']
        bypass = ['-o', 'tun+', '-j', 'RETURN']
        rules.remove(bypass)
        rules.append(bypass)
        self.save(model)
        self.assertNotEqual(self.invoke('check-ready').returncode, 0,
                            'late VPN return cannot undo an existing DNS mark')
        self.assertEqual(self.kernel(), model)
        self.ok(self.invoke())
        repaired = self.kernel()['tables']['mangle']['AGHAD6O']
        self.assertLess(repaired.index(bypass), next(i for i, rule in enumerate(repaired) if 'MARK' in rule))
        self.ok(self.invoke('check-ready'))

    def test_vpn_dns_policy_and_network_changes_reconcile_recorded_previous_rules(self):
        mode = self.root / 'config/mode.conf'
        network = self.root / 'state/network.state'
        mode.write_text('bypass_vpn_traffic=false\nbypass_vpn_dns=true\n')
        network.write_text('state=ready\nvpn=true\ninterface=wlan0\n')
        self.ok(self.invoke(TPROXY_NATIVE_LISTING='1'))
        previous = self.status()
        for dns_bypass, vpn, iface, expected in [
                ('false', 'true', 'wlan0', False),
                ('true', 'true', 'wlan0', True),
                ('true', 'false', 'wlan1', False),
                ('true', 'true', 'wlan1', True)]:
            with self.subTest(dns_bypass=dns_bypass, vpn=vpn, iface=iface):
                mode.write_text('bypass_vpn_traffic=false\nbypass_vpn_dns=' + dns_bypass + '\n')
                network.write_text('state=ready\nvpn=' + vpn + '\ninterface=' + iface + '\n')
                before = self.kernel()
                self.assertNotEqual(self.invoke('check-ready', TPROXY_NATIVE_LISTING='1').returncode, 0)
                self.assertEqual(self.kernel(), before, 'readiness must not mutate stale policy')
                (self.root / 'events').write_text('')
                self.ok(self.invoke(TPROXY_NATIVE_LISTING='1'))
                current = self.status()
                self.assertNotEqual(current['pid'], previous['pid'])
                self.assertEqual(current['listen_port'], previous['listen_port'])
                rules = self.kernel()['tables']['mangle']['AGHAD6O']
                for prefix in ('tun+', 'tap+', 'wg+', 'ppp+', 'tailscale+'):
                    self.assertEqual(['-o', prefix, '-j', 'RETURN'] in rules, expected)
                mutations = [e for e in self.events() if '-S' not in e and '-C' not in e and 'show' not in e]
                self.assertEqual(mutations[0], ['ip6tables', '-w', '2', '-t', 'mangle', '-D', 'OUTPUT', '-j', 'AGHAD6O'])
                self.assertEqual(self.kernel()['routes']['20535'], [
                    'local ::/0 dev lo metric 1024 pref medium',
                    'local fe80::/10 dev ' + iface + ' metric 1024 pref medium'])
                self.ok(self.invoke('check-ready', TPROXY_NATIVE_LISTING='1'))
                previous = current
        # Explicit teardown must use the published policy, not the new config.
        mode.write_text('bypass_vpn_dns=false\n')
        network.write_text('state=ready\nvpn=false\ninterface=wlan2\n')
        self.ok(self.invoke('remove', TPROXY_NATIVE_LISTING='1'))
        self.assertEqual(self.kernel()['tables'], self.model['tables'])
        self.assertFalse(self.kernel()['routes']['20535'])

    def test_policy_change_does_not_authorize_foreign_vpn_return_in_old_chain(self):
        mode = self.root / 'config/mode.conf'
        network = self.root / 'state/network.state'
        mode.write_text('bypass_vpn_dns=false\n')
        network.write_text('state=ready\nvpn=true\n')
        self.ok(self.invoke())
        pid = self.status()['pid']
        model = self.kernel()
        foreign = ['-o', 'tun+', '-j', 'RETURN']
        model['tables']['mangle']['AGHAD6O'].append(foreign)
        self.save(model)
        mode.write_text('bypass_vpn_dns=true\n')
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertIn(foreign, self.kernel()['tables']['mangle']['AGHAD6O'])
        self.assert_relay_live(pid)
        self.assertTrue(self.kernel()['routes']['20535'])

    def test_main_encrypted_policy_and_tproxy_share_verified_prefix_without_churn(self):
        env = self.main_firewall_env()
        main = ROOT / 'module/scripts/firewall/firewall-worker.sh'
        def refresh():
            self.ok(subprocess.run(['busybox', 'sh', str(main), 'once'], env=env,
                                   capture_output=True, text=True, timeout=25))
            state = dict(line.split('=', 1) for line in
                         (self.root / 'state/firewall.state').read_text().splitlines())
            self.assertEqual(state['state'], 'ready', state)
        refresh()
        pid = self.status()['pid']
        before = self.kernel()
        (self.root / 'events').write_text('')
        for _ in range(3):
            refresh()
            self.ok(self.invoke('check-ready'))
            self.assertEqual(self.status()['pid'], pid)
            self.assertEqual(self.kernel(), before)
            self.assert_relay_live(pid)
        self.assertTrue(all('-S' in e or '-C' in e or 'show' in e for e in self.events()), self.events())
        self.assertEqual(set(tuple(r) for r in before['tables']['filter']['OUTPUT'][:2]),
                         {('-j', 'AGHADF6'), ('-j', 'AGHAD6T')})
        self.assertEqual(before['tables']['filter']['OUTPUT'][2:], self.model['tables']['filter']['OUTPUT'])

    def test_shared_filter_prefix_never_accepts_foreign_interleaving_or_dns_blocking_policy(self):
        self.ok(self.invoke())
        pid = self.status()['pid']
        model = self.kernel()
        model['tables']['filter']['AGHADF6'] = [
            ['-m', 'owner', '--uid-owner', '0', '-j', 'RETURN'],
            ['-p', 'tcp', '--dport', '853', '-j', 'DROP']]
        model['tables']['filter']['OUTPUT'].insert(0, ['-j', 'AGHADF6'])
        self.save(model)
        self.ok(self.invoke('check-ready'))
        for damage in ('interleaving', 'root_order', 'dns_drop'):
            with self.subTest(damage=damage):
                damaged = json.loads(json.dumps(model))
                filt = damaged['tables']['filter']
                if damage == 'interleaving':
                    filt['OUTPUT'].insert(1, filt['OUTPUT'].pop(2))
                elif damage == 'root_order':
                    filt['AGHADF6'].reverse()
                else:
                    filt['AGHADF6'].append(['-p', 'udp', '--dport', '53', '-j', 'DROP'])
                self.save(damaged)
                (self.root / 'events').write_text('')
                self.assertNotEqual(self.invoke('check-ready').returncode, 0)
                self.assertEqual(self.kernel(), damaged)
                self.assertTrue(all('-S' in e or '-C' in e or 'show' in e for e in self.events()))
                self.assert_relay_live(pid)
        self.save(model)

    def test_real_kernel_encrypted_policy_refresh_keeps_relay_and_rules_unchanged(self):
        native = shutil.which('ip6tables')
        ip = shutil.which('ip')
        self.assertIsNotNone(native)
        self.assertIsNotNone(ip)
        wrapper = self.root / 'fake/native-ip6tables'
        wrapper.write_text('''#!/bin/sh
printf '%s\\n' "$*" >> "$AGH_ROOT/native-events"
case " $* " in
 *' -t nat '*) printf "ip6tables: table 'nat': Table does not exist\\n" >&2; exit 3 ;;
esac
exec "$NATIVE_IP6TABLES" "$@"
''')
        wrapper.chmod(0o755)
        env = dict(self.main_firewall_env(), IP6TABLES_BIN=str(wrapper),
                   NATIVE_IP6TABLES=str(native), NATIVE_IP=str(ip),
                   MAIN=str(ROOT / 'module/scripts/firewall/firewall-worker.sh'))
        script = '''set -e
"$NATIVE_IP" link set lo up
"$NATIVE_IP6TABLES" -t filter -N netd
"$NATIVE_IP6TABLES" -t filter -A netd -j RETURN
"$NATIVE_IP6TABLES" -t filter -A OUTPUT -j netd
busybox sh "$MAIN" once
pid=$(cat "$AGH_ROOT/run/ipv6-tproxy.pid")
# Also exercise the valid encrypted-policy-first ordering.
"$NATIVE_IP6TABLES" -t filter -D OUTPUT -j AGHADF6
"$NATIVE_IP6TABLES" -t filter -I OUTPUT 1 -j AGHADF6
"$NATIVE_IP6TABLES" -t filter -S > "$AGH_ROOT/filter-before"
"$NATIVE_IP6TABLES" -t mangle -S > "$AGH_ROOT/mangle-before"
: > "$AGH_ROOT/native-events"
for cycle in 1 2 3; do
    busybox sh "$MAIN" once
    grep -qx 'state=ready' "$AGH_ROOT/state/firewall.state"
    [ "$(cat "$AGH_ROOT/run/ipv6-tproxy.pid")" = "$pid" ]
done
cp "$AGH_ROOT/native-events" "$AGH_ROOT/native-refresh-events"
# Duplicate repair must retain the other own hook and the same live relay.
"$NATIVE_IP6TABLES" -t filter -A OUTPUT -j AGHADF6
busybox sh "$MAIN" once
grep -qx 'state=ready' "$AGH_ROOT/state/firewall.state"
[ "$(cat "$AGH_ROOT/run/ipv6-tproxy.pid")" = "$pid" ]
"$NATIVE_IP6TABLES" -t filter -S > "$AGH_ROOT/filter-after"
"$NATIVE_IP6TABLES" -t mangle -S > "$AGH_ROOT/mangle-after"
busybox sh "$MAIN" remove
'''
        result = subprocess.run(['unshare', '-n', 'sh', '-c', script], env=env,
                                capture_output=True, text=True, timeout=35)
        if result.returncode:
            result.stderr += '\n' + '\n'.join(p.read_text() for p in
                (self.root / 'state').glob('*.state'))
            result.stderr += '\n' + (self.root / 'native-events').read_text()
        self.ok(result)
        for table in ('filter', 'mangle'):
            self.assertEqual((self.root / (table + '-before')).read_bytes(),
                             (self.root / (table + '-after')).read_bytes())
        events = (self.root / 'native-refresh-events').read_text().splitlines()
        self.assertTrue(all(' -S' in line or ' -C ' in line for line in events), events)

    def test_scoped_linklocal_dns_gets_owned_interface_route_and_cleanup(self):
        (self.root/'state/network.state').write_text('state=ready\ninterface=wlan0\ndns6=fe80::1%wlan0\n')
        self.ok(self.invoke())
        self.assertIn('local fe80::/10 dev wlan0 metric 1024 pref medium', self.kernel()['routes']['20535'])
        self.assertIn(['-p', 'tcp', '-d', 'fe80::/10', '-j', 'RETURN'], self.kernel()['tables']['mangle']['AGHAD6O'])
        self.ok(self.invoke('check-ready'))
        self.ok(self.invoke('remove'))
        self.assertEqual(self.kernel()['routes']['20535'], [])

    def test_scoped_dns_is_published_only_after_relay_route_and_allowance(self):
        self.ok(self.invoke())
        status = self.status()
        self.assertEqual(status['state'], 'ready')
        self.assertEqual(status['upstream_port'], '5354')
        self.assertNotIn(status['listen_port'], ['5354', '8080'])
        self.assertTrue(Path('/proc', status['pid']).exists())
        model = self.kernel()
        mangle, filt = model['tables']['mangle'], model['tables']['filter']
        self.assertEqual(mangle['AGHAD6O'], [
            ['-m', 'owner', '--uid-owner', '0', '-j', 'RETURN'],
            ['-p', 'tcp', '-d', 'fe80::/10', '-j', 'RETURN'],
            ['-p', 'udp', '--dport', '53', '-j', 'MARK', '--set-xmark', '0x20000000/0x20000000'],
            ['-p', 'tcp', '--dport', '53', '-j', 'MARK', '--set-xmark', '0x20000000/0x20000000']])
        for rule in mangle['AGHAD6P']:
            self.assertEqual(rule[:6], ['-i', 'lo', '-m', 'mark', '--mark', '0x20000000/0x20000000'])
            self.assertIn('::1', rule)
            self.assertIn(status['listen_port'], rule)
        for rule in filt['AGHAD6T']:
            self.assertIn('0x20000000/0x20000000', rule)
            self.assertIn('53', rule)
            self.assertEqual(rule[-2:], ['-j', 'ACCEPT'])
        self.assertEqual(filt['OUTPUT'][0], ['-j', 'AGHAD6T'])
        self.assertEqual(mangle['FOREIGN'], self.model['tables']['mangle']['FOREIGN'])
        self.assertEqual(filt['netd'], self.model['tables']['filter']['netd'])
        events = self.events()
        publish = events.index(['ip6tables', '-w', '2', '-t', 'mangle', '-I', 'OUTPUT', '1', '-j', 'AGHAD6O'])
        for e in [['ip', '-6', 'route', 'add', 'local', '::/0', 'dev', 'lo', 'table', '20535'],
                  ['ip6tables', '-w', '2', '-t', 'mangle', '-I', 'PREROUTING', '1', '-j', 'AGHAD6P'],
                  ['ip6tables', '-w', '2', '-t', 'filter', '-I', 'OUTPUT', '1', '-j', 'AGHAD6T']]:
            self.assertLess(events.index(e), publish)
        self.ok(self.invoke('check-ready'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
