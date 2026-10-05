#!/usr/bin/env python3
"""Boot/PID regressions: real shell workers, no Android or host firewall."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "module"


class BootRegression(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = dict(os.environ, MODDIR=str(MODULE), AGH_ROOT=str(self.root))
        for key, name in (("CONFIG", "config"), ("STATE", "state"), ("RUN", "run"),
                          ("LOG", "logs"), ("DATA", "data"), ("BACKUP", "backup")):
            folder = self.root / name
            folder.mkdir()
            self.env["AGH_" + key + "_DIR"] = str(folder)
        self.workers = self.root / "workers"
        self.workers.mkdir()
        self.env["SUPERVISOR_WORKER_DIR"] = str(self.workers)
        self.env["MODULE_PROP_FILE"] = str(self.root / "module.prop")
        (self.root / "module.prop").write_text("description=fixture\n")
        (self.root / "config/mode.conf").write_text("mode=2\n")
        for name in ("proxy", "file"):
            (self.root / ("config/" + name + "-adapter.conf")).write_text("enabled=false\n")
        for name in ("core", "network", "firewall"):
            script = self.workers / (name + "-worker.sh")
            script.write_text("#!/bin/sh\n"
                              "state=ready\n"
                              "[ \"$1\" != stop ] || state=stopped\n"
                              "if [ -f \"$AGH_RUN_DIR/firewall/request\" ] && [ \"" + name + "\" = firewall ]; then\n"
                              "  state=removed; rm -f \"$AGH_RUN_DIR/firewall/request\"\nfi\n"
                              "printf 'state=%s\\nfirewall_authorized=1\\n' \"$state\" > \"$AGH_STATE_DIR/" + name + ".state\"\n")
            script.chmod(0o755)

    def run_once(self):
        return subprocess.run(["busybox", "sh", str(MODULE / "scripts/lifecycle/supervisor.sh"), "once"],
                              env=self.env, text=True, capture_output=True, timeout=10)

    def test_stale_cycle_lock_after_reboot_does_not_silently_skip_workers(self):
        (self.root / "run/supervisor.lock").mkdir()
        result = self.run_once()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / "state/core.state").exists(), "stale lock skipped all workers")
        self.assertFalse((self.root / "run/supervisor.lock").exists())

    def test_start_returns_to_captured_root_command(self):
        """KSU exec/ADB must receive EOF while the supervisor stays running."""
        def stop_started():
            (self.root/'run/stop').touch()
            pidfile=self.root/'run/supervisor.pid'
            if pidfile.exists():
                pid=int(pidfile.read_text().strip())
                try: os.kill(pid, 15)
                except ProcessLookupError: pass
        self.addCleanup(stop_started)
        result=subprocess.run(['busybox','sh',str(MODULE/'scripts/lifecycle/control.sh'),'start'],
                              env=self.env,capture_output=True,text=True,timeout=3)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('request=start',result.stdout)

    def test_foreign_live_pid_is_not_a_running_supervisor(self):
        foreign = subprocess.Popen(["sleep", "30"])
        def cleanup(process):
            if process.poll() is None:
                process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        self.addCleanup(cleanup, foreign)
        (self.root / "run/supervisor.pid").write_text(str(foreign.pid) + "\n")
        daemon = subprocess.Popen(["busybox", "sh", str(MODULE / "scripts/lifecycle/supervisor.sh"), "daemon"],
                                  env=dict(self.env, SUPERVISOR_INTERVAL="1"),
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(cleanup, daemon)
        for _ in range(300):
            if (self.root / "state/core.state").exists() or daemon.poll() is not None:
                break
            time.sleep(0.1)
        self.assertTrue((self.root / "state/core.state").exists(), "reused foreign PID suppressed startup")
        self.assertIsNone(foreign.poll(), "foreign PID was killed")
        (self.root / "run/stop").touch()
        self.assertEqual(daemon.wait(timeout=20), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
