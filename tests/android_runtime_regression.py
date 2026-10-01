#!/usr/bin/env python3
"""Minimal public reproductions derived from device symptoms, no private logs."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / 'module'

class AndroidRuntimeRegression(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = dict(os.environ, MODDIR=str(MODULE), AGH_ROOT=str(self.root))
        for key, name in [('CONFIG','config'),('STATE','state'),('RUN','run'),('LOG','logs'),('DATA','data'),('BACKUP','backup')]:
            (self.root/name).mkdir()
            self.env['AGH_'+key+'_DIR'] = str(self.root/name)
        self.bin = self.root/'broken-system-bin'
        self.bin.mkdir()
        for name in ('awk','chmod','mv','sync','toybox'):
            p = self.bin/name
            p.write_text('#!/bin/sh\nprintf "CANNOT LINK EXECUTABLE fixture\\n" >&2\nexit 127\n')
            p.chmod(0o755)
        busybox=shutil.which('busybox')
        assert busybox, 'BusyBox is required'
        self.env.update(AGH_BUSYBOX=busybox, PATH=str(self.bin)+':'+os.environ['PATH'])
        shutil.copy(MODULE/'config/mode.conf', self.root/'config/mode.conf')
    def worker(self, rel, *args, **extra):
        return subprocess.run(['sh', str(MODULE/rel), *args], env=dict(self.env, **extra), capture_output=True, text=True, timeout=30)
    def test_scoped_ipv6_dns_is_not_a_disconnected_network(self):
        snap = self.root/'network.snapshot'
        snap.write_text('network=wifi\ninterface=wlan0\nvpn=true\ndns4=192.0.2.1\ndns6=fe80::1%wlan0\n')
        result=self.worker('scripts/network/network-worker.sh','once',NETWORK_SNAPSHOT_FILE=str(snap))
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('state=ready\n',(self.root/'state/network.state').read_text())
        self.assertIn('dns6=fe80::1%wlan0\n',(self.root/'state/network.state').read_text())
    def test_file_validator_uses_static_busybox_not_broken_system_awk(self):
        result=self.worker('scripts/adapters/file-rules.sh','validate',str(MODULE/'targets/file-ad-targets.conf'))
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertNotIn('CANNOT LINK',result.stderr)
    def test_common_writers_do_not_call_broken_toybox(self):
        body='. "$MODDIR/scripts/lib/common.sh"; agh_printf "%s" ok; agh_chmod 600 "$AGH_ROOT/probe"; agh_move "$AGH_ROOT/probe" "$AGH_ROOT/moved"'
        (self.root/'probe').write_text('keep')
        result=subprocess.run(['sh','-c',body],env=self.env,capture_output=True,text=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout,'ok')
        self.assertEqual((self.root/'moved').read_text(),'keep')
    def test_invalid_owned_cache_recovers_without_download(self):
        config='enabled=true\nmax_backup_bytes=10485760\ntarget_manifest=targets/file-ad-targets.conf\n'
        (self.root/'config/file-adapter.conf').write_text(config)
        bad='unsafe|/data/data/com.example.app/files|directory|high|if-unchanged|com.example.app|active\n'
        (self.root/'config/file-ad-targets.conf').write_text(bad)
        data=self.root/'android-data'
        (data/'user/0').mkdir(parents=True)
        result=self.worker('scripts/adapters/file-worker.sh','once',AGH_FILE_DATA_ROOT=str(data))
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual((self.root/'config/file-ad-targets.conf').read_bytes(),(MODULE/'targets/file-ad-targets.conf').read_bytes())
        self.assertTrue(any(p.read_text()==bad for p in (self.root/'backup/file/rules').glob('*.conf')))

if __name__=='__main__': unittest.main(verbosity=2)
