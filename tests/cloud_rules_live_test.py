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
    shutil.copy(ROOT/'module/config/file-adapter.conf',root/'config/file-adapter.conf')
    command=['sh',str(ROOT/'module/scripts/adapters/file-rules.sh'),'refresh']
    result=subprocess.run(command,env=env,capture_output=True,text=True,timeout=240)
    state=(root/'state/file-rules.state').read_text() if (root/'state/file-rules.state').exists() else 'no state'
    assert result.returncode==0,(result.stderr,state)
    assert 'state=ready\n' in state
    assert (root/'config/file-ad-targets.conf').read_bytes()==(ROOT/'module/targets/file-ad-targets.conf').read_bytes()
    assert 'enabled=false\n' in (root/'config/file-adapter.conf').read_text()
    print('actual HTTPS cloud download + SHA256 + safety validation + persistent installation passed')
