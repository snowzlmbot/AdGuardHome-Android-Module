#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

archive = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    module = root / 'module'
    module.mkdir()
    env = os.environ.copy()
    env.update(MODPATH=str(module), ZIPFILE=str(archive), ARCH='arm64',
               AGH_ROOT=str(root / 'runtime'), LEGACY_MODULES_DIR=str(root / 'modules'),
               INSTALL_NONINTERACTIVE='1', INSTALL_DNS_MODE='2',
               INSTALL_BLOCK_853='false', INSTALL_ENABLE_IPV6='true',
               INSTALL_ENABLE_PROXY='false', INSTALL_ENABLE_FILE='false')
    for key, name in [('CONFIG', 'config'), ('STATE', 'state'), ('RUN', 'run'),
                      ('DATA', 'data'), ('LOG', 'logs'), ('BACKUP', 'backup')]:
        env['AGH_' + key + '_DIR'] = str(root / 'runtime' / name)
    for entry in ('module.prop', 'customize.sh'):
        result = subprocess.run(['busybox', 'unzip', '-o', str(archive), entry, '-d', str(module)], capture_output=True)
        assert result.returncode == 0, result.stderr
    shell = 'ui_print() { printf "%s\\n" "$*"; }; abort() { printf "ABORT\\n"; exit 71; }; . "$MODPATH/customize.sh"'
    result = subprocess.run(['busybox', 'sh', '-c', shell], env=env, text=True, capture_output=True, timeout=30)
    assert result.returncode == 0, result.stdout + result.stderr
    for entry in ('service.sh', 'boot-completed.sh', 'scripts/core/core-worker.sh', 'rules/anti-ad-easylist.txt', 'licenses/anti-AD-MIT.txt', 'sbom/SPDX.json'):
        assert (module / entry).is_file(), entry
    assert (module / 'scripts/core/core-worker.sh').stat().st_mode & 0o111
    assert (root / 'runtime/bin/agh-http-fetch').stat().st_mode & 0o111
    before = (root / 'runtime/config/mode.conf').read_bytes()
    env['ARCH'] = 'x86'
    rejected = subprocess.run(['busybox', 'sh', '-c', shell], env=env, text=True, capture_output=True, timeout=30)
    assert rejected.returncode == 71, rejected.stdout + rejected.stderr
    assert (root / 'runtime/config/mode.conf').read_bytes() == before
print('exact packaged BusyBox installer passed: payload, executable bits, abort and preserved config')
