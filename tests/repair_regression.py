#!/usr/bin/env python3
from __future__ import annotations

import os
import pathlib
import shlex
import shutil
import socket
import subprocess
import tempfile

PROJECT = pathlib.Path(__file__).resolve().parents[1]
MODULE = PROJECT / "module"
PATCH = PROJECT / "build" / "patches" / "adguardhome-v0.107.79-querylog-autorefresh.patch"


def run(cmd: list[str], *, env: dict[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(cmd, env=env, text=True, capture_output=True)
    if check and result.returncode != 0:
        raise AssertionError(
            f"command failed ({result.returncode}): {shlex.join(cmd)}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def write(path: pathlib.Path, content: str, mode: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    if mode is not None:
        path.chmod(mode)


def assert_contains(text: str, needle: str) -> None:
    if needle not in text:
        raise AssertionError(f"missing expected text: {needle!r}")


def test_shell_syntax() -> None:
    scripts = sorted(MODULE.rglob("*.sh"))
    scripts.extend([MODULE / "action.sh", MODULE / "service.sh", MODULE / "boot-completed.sh", MODULE / "uninstall.sh"])
    for script in sorted(set(scripts)):
        run(["sh", "-n", str(script)])


def test_mode_tuning() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        config_dir = root / "config"
        config_dir.mkdir()
        yaml = config_dir / "AdGuardHome.yaml"
        mode_file = config_dir / "mode.conf"
        write(
            yaml,
            """http:\n  address: 127.0.0.1:3000\ndns:\n  upstream_dns:\n    - 223.5.5.5\n  bootstrap_dns:\n    - 180.184.1.1\n  fallback_dns: []\n  upstream_mode: parallel\n  cache_optimistic: false\n  upstream_timeout: 10s\nquerylog:\n  enabled: true\n""",
        )
        shutil.copy2(MODULE / "config" / "mode.conf", mode_file)
        shell = f"""
. {shlex.quote(str(MODULE / 'scripts/lib/common.sh'))}
agh_sync() {{ :; }}
. {shlex.quote(str(MODULE / 'scripts/lib/agh-config.sh'))}
agh_apply_mode 1 {shlex.quote(str(yaml))} {shlex.quote(str(mode_file))}
"""
        run(["sh", "-c", shell])
        tuned = yaml.read_text()
        assert_contains(tuned, "  upstream_timeout: 3s")
        assert_contains(tuned, "  cache_optimistic: true")
        assert_contains(tuned, "    - https://1.12.12.12/dns-query")
        mode_text = mode_file.read_text()
        assert_contains(mode_text, "lan_dns_target=223.5.5.5:53,119.29.29.29:53")

        shell = f"""
. {shlex.quote(str(MODULE / 'scripts/lib/common.sh'))}
agh_sync() {{ :; }}
. {shlex.quote(str(MODULE / 'scripts/lib/agh-config.sh'))}
agh_apply_mode 2 {shlex.quote(str(yaml))} {shlex.quote(str(mode_file))}
"""
        run(["sh", "-c", shell])
        tuned = yaml.read_text()
        assert_contains(tuned, "    - https://1.12.12.12/dns-query")
        assert_contains(tuned, "    - 223.5.5.5")
        assert_contains(tuned, "  upstream_timeout: 3s")
        assert_contains(tuned, "  cache_optimistic: true")


def runtime_env(root: pathlib.Path) -> dict[str, str]:
    env = os.environ.copy()
    env.update(
        {
            "MODDIR": str(MODULE),
            "AGH_ROOT": str(root),
            "AGH_CONFIG_DIR": str(root / "config"),
            "AGH_STATE_DIR": str(root / "state"),
            "AGH_RUN_DIR": str(root / "run"),
            "AGH_LOG_DIR": str(root / "logs"),
            "AGH_BACKUP_DIR": str(root / "backup"),
            "AGH_DATA_DIR": str(root / "data"),
        }
    )
    return env


def test_proxy_manifest_is_idempotent() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        proxy_file = root / "proxy" / "config.yaml"
        write(proxy_file, "dns:\n  enhanced-mode: fake-ip\n  nameserver:\n    - 1.1.1.1\n")
        config = root / "config" / "proxy-adapter.conf"
        write(
            config,
            f"enabled=true\nmax_file_bytes=1048576\nallowed_prefix={proxy_file.parent}\nfile={proxy_file}\n",
        )
        write(root / "state" / "ports.conf", "web_port=3000\ndns_port=5591\n")
        env = runtime_env(root)
        worker = MODULE / "scripts" / "adapters" / "proxy-worker.sh"
        run(["sh", str(worker), "once"], env=env)
        first = proxy_file.read_text()
        manifest = root / "backup" / "proxy" / "manifest.tsv"
        if len(manifest.read_text().splitlines()) != 1:
            raise AssertionError("proxy manifest should contain exactly one entry after first run")
        run(["sh", str(worker), "once"], env=env)
        if proxy_file.read_text() != first:
            raise AssertionError("second proxy pass unexpectedly changed the file")
        if len(manifest.read_text().splitlines()) != 1:
            raise AssertionError("proxy manifest duplicated an existing entry")


def test_file_adapter_does_not_reclear_changed_target() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        target = root / "target"
        write(target / "cached.bin", "original")
        manifest_source = root / "targets.conf"
        write(manifest_source, f"sample|{target}|directory|medium|if-unchanged\n")
        write(
            root / "config" / "file-adapter.conf",
            f"enabled=true\nmax_backup_bytes=10485760\ntarget_manifest={manifest_source}\n",
        )
        env = runtime_env(root)
        worker = MODULE / "scripts" / "adapters" / "file-worker.sh"
        run(["sh", str(worker), "once"], env=env)
        write(target / "new.bin", "new data")
        second = run(["sh", str(worker), "once"], env=env, check=False)
        if second.returncode == 0:
            raise AssertionError("changed target should fail closed instead of being cleared again")
        if not (target / "new.bin").exists():
            raise AssertionError("changed target was cleared on a repeated pass")
        backup_manifest = root / "backup" / "file" / "manifest.tsv"
        if len(backup_manifest.read_text().splitlines()) != 1:
            raise AssertionError("file adapter created duplicate backup records")


def test_firewall_exempts_all_plain_dns_upstreams() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        fake_bin = root / "bin"
        log = root / "firewall.log"
        fake = """#!/bin/sh
printf '%s %s\\n' "$0" "$*" >> "$FIREWALL_TEST_LOG"
case " $* " in
  *" -C "*|*" -L "*) exit 1 ;;
esac
exit 0
"""
        write(fake_bin / "iptables", fake, 0o755)
        write(fake_bin / "ip6tables", fake, 0o755)
        write(fake_bin / "iptables-save", "#!/bin/sh\nexit 0\n", 0o755)
        write(root / "config" / "mode.conf", "mode=1\nredirect_ipv4_dns=true\nredirect_ipv6_dns=false\nblock_ipv4_dot=false\nblock_ipv6_dot=false\nblock_ipv4_doq=false\nblock_ipv6_doq=false\nbypass_vpn_dns=true\nbypass_vpn_encrypted_dns=true\nbypass_vpn_traffic=true\nlan_dns_target=223.5.5.5:53,119.29.29.29:53\nbootstrap_dns=\n")
        write(root / "state" / "network.state", "state=ready\nmode=1\nnetwork=wifi\ninterface=wlan0\nvpn=false\n")
        write(root / "state" / "core.state", "state=ready\nfirewall_authorized=1\ndns_port=5591\n")
        write(root / "state" / "ports.conf", "web_port=3000\ndns_port=5591\n")
        env = runtime_env(root)
        env.update({"PATH": f"{fake_bin}:{env['PATH']}", "FIREWALL_TEST_LOG": str(log), "FIREWALL_NO_WAIT": "1"})
        worker = MODULE / "scripts" / "firewall" / "firewall-worker.sh"
        run(["sh", str(worker), "once"], env=env)
        trace = log.read_text()
        for ip in ("223.5.5.5", "119.29.29.29"):
            assert_contains(trace, f"-d {ip} -p udp --dport 53 -j RETURN")
            assert_contains(trace, f"-d {ip} -p tcp --dport 53 -j RETURN")


def test_udp_port_is_not_reported_free() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        fake_bin = root / "bin"
        write(
            fake_bin / "ss",
            """#!/bin/sh
case "$1" in
  -lnu) printf 'UNCONN 0 0 127.0.0.1:45555 0.0.0.0:*\\n' ;;
esac
""",
            0o755,
        )
        env = os.environ.copy()
        env["PATH"] = f"{fake_bin}:{env['PATH']}"
        shell = f". {shlex.quote(str(MODULE / 'scripts/lib/platform.sh'))}; port_is_free 45555"
        result = run(["sh", "-c", shell], env=env, check=False)
        if result.returncode == 0:
            raise AssertionError("UDP listener was incorrectly reported as a free port")


def test_restore_failure_preserves_backups() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        module_copy = root / "module"
        shutil.copytree(MODULE, module_copy)
        for rel in ("scripts/adapters/proxy-worker.sh", "scripts/adapters/file-worker.sh"):
            write(module_copy / rel, "#!/system/bin/sh\nexit 1\n", 0o755)
        write(module_copy / "scripts/firewall/firewall-worker.sh", "#!/system/bin/sh\nexit 0\n", 0o755)
        runtime = root / "runtime"
        write(runtime / "backup" / "keep", "backup")
        env = os.environ.copy()
        env.update(
            {
                "MODDIR": str(module_copy),
                "AGH_ROOT": str(runtime),
                "AGH_CONFIG_DIR": str(runtime / "config"),
                "AGH_STATE_DIR": str(runtime / "state"),
                "AGH_RUN_DIR": str(runtime / "run"),
                "AGH_LOG_DIR": str(runtime / "logs"),
                "AGH_BACKUP_DIR": str(runtime / "backup"),
                "AGH_DATA_DIR": str(runtime / "data"),
                "AGH_UNINSTALL_REPORT": str(root / "uninstall-report.log"),
            }
        )
        result = run(["sh", str(module_copy / "uninstall.sh")], env=env, check=False)
        if result.returncode == 0:
            raise AssertionError("uninstall should report restore failure")
        if not (runtime / "backup" / "keep").exists():
            raise AssertionError("uninstall deleted backups after restore failure")
        report = (root / "uninstall-report.log").read_text()
        assert_contains(report, "completed=false")
        assert_contains(report, "data_removed=false")


def test_query_log_source_patch() -> None:
    patch = PATCH.read_text()
    for needle in (
        "QUERY_LOGS_AUTO_REFRESH_INTERVAL_MS = 5000",
        "window.setInterval",
        "window.clearInterval",
        "document.visibilityState === 'visible'",
        "refreshFilteredLogs()",
        "QUERY_LOGS_PAGE_LIMIT",
    ):
        assert_contains(patch, needle)


def test_repository_layout() -> None:
    required = [
        MODULE / "module.prop",
        MODULE / "customize.sh",
        MODULE / "service.sh",
        MODULE / "scripts" / "core" / "core-worker.sh",
        MODULE / "webroot" / "index.html",
        PATCH,
    ]
    missing = [str(path.relative_to(PROJECT)) for path in required if not path.is_file()]
    if missing:
        raise AssertionError(f"repository repair inputs missing: {missing}")
    package = (PROJECT / "build" / "package.sh").read_text()
    if "artifact-latest" in package:
        raise AssertionError("repository package path depends on extracted runtime snapshot")


def main() -> None:
    tests = [
        test_shell_syntax,
        test_mode_tuning,
        test_proxy_manifest_is_idempotent,
        test_file_adapter_does_not_reclear_changed_target,
        test_firewall_exempts_all_plain_dns_upstreams,
        test_udp_port_is_not_reported_free,
        test_restore_failure_preserves_backups,
        test_query_log_source_patch,
        test_repository_layout,
    ]
    for test in tests:
        test()
        print(f"PASS {test.__name__}")
    print(f"PASS all ({len(tests)} tests)")


if __name__ == "__main__":
    main()
