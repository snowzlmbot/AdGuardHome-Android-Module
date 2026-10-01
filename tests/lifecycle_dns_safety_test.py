#!/usr/bin/env python3
"""Exercise real lifecycle code with isolated component event fixtures."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / 'module'


class LifecycleDNSSafety(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = dict(os.environ, MODDIR=str(MODULE), AGH_ROOT=str(self.root))
        for key, folder in [('CONFIG', 'config'), ('STATE', 'state'), ('RUN', 'run'),
                            ('LOG', 'logs'), ('DATA', 'data'), ('BACKUP', 'backup')]:
            path = self.root / folder
            path.mkdir()
            self.env['AGH_' + key + '_DIR'] = str(path)
        workers = self.root / 'workers'
        workers.mkdir()
        self.env.update(SUPERVISOR_WORKER_DIR=str(workers), MODULE_PROP_FILE=str(self.root / 'module.prop'))
        (self.root / 'module.prop').write_text('description=fixture\n')
        (self.root / 'config/mode.conf').write_text('mode=2\n')
        for name in ['proxy', 'file']:
            (self.root / ('config/' + name + '-adapter.conf')).write_text('enabled=false\n')
        for name in ['core', 'firewall', 'network']:
            path = workers / (name + '-worker.sh')
            path.write_text('''#!/bin/sh
name=''' + name + '''
printf '%s:%s\n' "$name" "$1" >> "$AGH_ROOT/events"
if [ "$name:$1" = core:check-ready ]; then
    [ "${PROBE_FAIL:-0}" != 1 ]
    exit $?
fi
if [ "$name" = firewall ]; then
    if [ "$1" = remove ] || [ -f "$AGH_RUN_DIR/firewall/request" ]; then
        printf '%s\n' 'firewall:remove' >> "$AGH_ROOT/events"
        [ "${FAIL_REMOVE:-0}" != 1 ] || exit 1
        rm -f "$AGH_RUN_DIR/firewall/request"
        printf 'state=removed\n' > "$AGH_STATE_DIR/firewall.state"
        exit 0
    fi
fi
if [ "$name:$1" = core:stop ]; then
    printf 'state=stopped\n' > "$AGH_STATE_DIR/core.state"
else
    printf 'state=ready\nfirewall_authorized=1\n' > "$AGH_STATE_DIR/$name.state"
fi
''')
            path.chmod(0o755)

    def invoke(self, action, **extra):
        return subprocess.run(['busybox', 'sh', str(MODULE / 'scripts/lifecycle/supervisor.sh'), action],
                              env=dict(self.env, **extra), capture_output=True, text=True, timeout=20)

    def events(self):
        path = self.root / 'events'
        return path.read_text().splitlines() if path.exists() else []

    def test_restart_detaches_dns_before_stopping_core(self):
        control = self.root / 'run/control'
        control.mkdir()
        (control / 'restart-core').touch()
        result = self.invoke('once')
        self.assertEqual(result.returncode, 0, result.stderr)
        events = self.events()
        self.assertIn('core:stop', events)
        self.assertIn('firewall:remove', events)
        self.assertLess(events.index('firewall:remove'), events.index('core:stop'))
        self.assertLess(events.index('core:stop'), events.index('core:once'))

    def test_firewall_remove_failure_never_stops_core(self):
        control = self.root / 'run/control'
        control.mkdir()
        (control / 'restart-core').touch()
        result = self.invoke('once', FAIL_REMOVE='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('core:stop', self.events())
        self.assertTrue((control / 'restart-core').exists(), 'failed restart request lost')

    def test_stop_consumes_cleanup_without_another_daemon_cycle(self):
        result = self.invoke('stop')
        self.assertEqual(result.returncode, 0, result.stderr)
        events = self.events()
        self.assertIn('firewall:remove', events)
        self.assertIn('core:stop', events)
        self.assertLess(events.index('firewall:remove'), events.index('core:stop'))
        self.assertNotIn('core:once', events)
        self.assertFalse((self.root / 'run/core/request').exists())

    def test_stop_marker_blocks_one_shot_core_restart(self):
        (self.root / 'run/stop').touch()
        result = self.invoke('once')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('core:once', self.events())
        self.assertIn('firewall:remove', self.events())

    def test_unhealthy_core_detaches_before_recovery(self):
        result = self.invoke('once', PROBE_FAIL='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        events = self.events()
        self.assertLess(events.index('firewall:remove'), events.index('core:once'))

    def test_disabled_core_detaches_before_core_worker(self):
        (self.root / 'state/core.disabled').touch()
        result = self.invoke('once')
        self.assertEqual(result.returncode, 0, result.stderr)
        events = self.events()
        self.assertLess(events.index('firewall:remove'), events.index('core:once'))

    def test_suspend_failure_keeps_listener_and_does_not_mark_global_stop(self):
        result = self.invoke('suspend-core', FAIL_REMOVE='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('core:stop', self.events())
        self.assertFalse((self.root / 'run/stop').exists())

    def test_suspend_detaches_without_stopping_supervisor(self):
        result = self.invoke('suspend-core')
        self.assertEqual(result.returncode, 0, result.stderr)
        events = self.events()
        self.assertLess(events.index('firewall:remove'), events.index('core:stop'))
        self.assertFalse((self.root / 'run/stop').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
