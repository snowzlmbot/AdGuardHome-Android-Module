#!/usr/bin/env python3
"""Real control/diagnostics and stateful firewall fixture, never host rules."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
MODULE=ROOT/'module'
class VPNPolicy(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name); self.env=dict(os.environ, MODDIR=str(MODULE), AGH_ROOT=str(self.root))
        for key,folder in [('CONFIG','config'),('STATE','state'),('RUN','run'),('LOG','logs'),('BACKUP','backup'),('DATA','data')]:
            p=self.root/folder;p.mkdir();self.env['AGH_'+key+'_DIR']=str(p)
        self.workers=self.root/'workers';self.workers.mkdir()
        self.env['SUPERVISOR_WORKER_DIR']=str(self.workers)
        self.env['MODULE_PROP_FILE']=str(self.root/'module.prop')
        (self.root/'module.prop').write_text('description=test\n')
        shutil.copy(MODULE/'config/mode.conf',self.root/'config/mode.conf')
        for name in ['proxy','file']:(self.root/f'config/{name}-adapter.conf').write_text('enabled=false\n')
        (self.root/'state/ports.conf').write_text('web_port=35001\ndns_port=35002\n')
        for name,body in [('core','state=ready\nfirewall_authorized=1\ndns_port=35002\ndns_ipv6_ready=true\n'),('network','state=ready\nnetwork=wifi\nvpn=true\n')]:
            p=self.workers/f'{name}-worker.sh';p.write_text('#!/bin/sh\nprintf '+repr(body)+' > "$AGH_STATE_DIR/'+name+'.state"\n');p.chmod(0o755)
            (self.root/f'state/{name}.state').write_text(body)
        self.env.update(IPTABLES_BIN=str(ROOT/'tests/fixtures/iptables-recording-bin/iptables'),
                        IP6TABLES_BIN=str(ROOT/'tests/fixtures/iptables-recording-bin/ip6tables'),
                        IPTABLES_RECORD_FILE=str(self.root/'v4.log'), IP6TABLES_RECORD_FILE=str(self.root/'v6.log'),FIREWALL_NO_WAIT='1')
    def command(self,script,*args):
        return subprocess.run(['sh',str(MODULE/'scripts'/script),*args],env=self.env,capture_output=True,text=True,timeout=30)
    def test_disable_bypass_has_no_hidden_tun_exemptions(self):
        for enabled in ['false','true','false']:
            r=self.command('lifecycle/control.sh','set-policy','bypass_vpn_traffic',enabled)
            self.assertEqual(r.returncode,0,r.stderr)
            config=(self.root/'config/mode.conf').read_text()
            for key in ['bypass_vpn_traffic','bypass_vpn_dns','bypass_vpn_encrypted_dns']:
                self.assertIn(key+'='+enabled+'\n',config)
            fw=(self.root/'state/firewall.state').read_text()
            self.assertIn('state='+('bypassed' if enabled=='true' else 'ready'),fw)
            if enabled=='false':
                tables=json.loads((self.root/'v4.log.state').read_text())
                self.assertFalse(any('-o' in rule and 'tun+' in rule for rules in tables['nat'].values() for rule in rules))
            diag=self.command('diagnostics/diagnostics.sh')
            self.assertIn('bypass_vpn_traffic='+enabled+'\n',diag.stdout)
            self.assertIn('vpn_passthrough='+enabled+'\n',diag.stdout)
    def test_rules_status_not_masked_by_stale_cleanup_ready(self):
        (self.root/'state/file.state').write_text('state=ready\nrules_state=ready\nrules_sha256=old\n')
        (self.root/'state/file-rules.state').write_text('state=failed\nreason=checksum_download\nsha256=unknown\nurl=https://raw.githubusercontent.com/example/repo/main/x\n')
        r=self.command('diagnostics/diagnostics.sh')
        self.assertIn('file_rules_state=failed\n',r.stdout)
        self.assertIn('file_rules_reason=checksum_download\n',r.stdout)
if __name__=='__main__':unittest.main(verbosity=2)
