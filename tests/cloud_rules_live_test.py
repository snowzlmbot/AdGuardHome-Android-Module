#!/usr/bin/env python3
"""Fetch actual public rules using module code and verify retained configuration."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp);env=dict(os.environ,MODDIR=str(ROOT/'module'),AGH_ROOT=str(root))
    for key,name in [('CONFIG','config'),('STATE','state'),('RUN','run'),('LOG','logs'),('DATA','data'),('BACKUP','backup')]:
        (root/name).mkdir();env['AGH_'+key+'_DIR']=str(root/name)
    legacy='https://raw.githubusercontent.com/snowzlmbot/AdGuardHome-Android-Module/main/module/targets/file-ad-targets.conf'
    (root/'config/file-adapter.conf').write_text('enabled=false\nrules_url='+legacy+'\nrules_sha256_url='+legacy+'.sha256\n')
    before=(root/'config/file-adapter.conf').read_text()
    command=['sh',str(ROOT/'module/scripts/adapters/file-rules.sh'),'refresh']
    result=subprocess.run(command,env=env,capture_output=True,text=True,timeout=240)
    state=(root/'state/file-rules.state').read_text() if (root/'state/file-rules.state').exists() else 'no state'
    download_log=(root/'logs/file-rules-worker.log').read_text() if (root/'logs/file-rules-worker.log').exists() else ''
    assert result.returncode==0,(result.stderr,state,download_log)
    assert 'state=ready\n' in state
    assert (root/'config/file-ad-targets.conf').read_bytes()==(ROOT/'module/targets/file-ad-targets.conf').read_bytes()
    assert 'enabled=false\n' in (root/'config/file-adapter.conf').read_text()
    assert (root/'config/file-adapter.conf').read_text()!=before,'legacy source migration did not run'
    diagnostics=subprocess.run(['sh',str(ROOT/'module/scripts/diagnostics/diagnostics.sh')],env=env,text=True,capture_output=True)
    assert 'file_rules_state=ready\n' in diagnostics.stdout
    print('actual HTTPS cloud download + SHA256 + safety validation + persistent installation passed')
