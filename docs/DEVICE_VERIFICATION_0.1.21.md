# Xiaomi 14 Ultra device verification — 0.1.21 candidate

## Scope and environment

- Device: Xiaomi 14 Ultra, model `24031PN0DC`, device `aurora`, Android 16/API 36, KernelSU root.
- Authorized USB ADB was used. No account credentials, raw query logs, phone serial, network SSID, or complete private YAML are included in this report.
- Initial state: AdGuardHome module and persistent `/data/adb/agh` were absent; no AGH DNS listener or module interception rules existed.
- Published `0.1.20` ZIP and its published SHA-256 were verified before installation and reproduction. Backups were retained locally before deployment and upgrade.

## Confirmed causes

1. Dormant Android `tunl0` was classified as a running VPN. Default VPN passthrough then removed every DNS redirect despite a working, filtering AGH core.
2. The kernel has `CONFIG_IP6_NF_NAT` disabled but supports IPv6 TPROXY/policy routing. Android's observed DNS server preference included scoped link-local IPv6, so IPv4 interception alone did not filter the normal resolver path.
3. Firewall inspection errors were interpreted as absent rules. Cleanup could incorrectly authorize stopping the listener while redirects remained.
4. Routine unchanged firewall refresh detached live rules; concurrent updates could also affect hook repair. Review-required safety changes are included in the final candidate.
5. Network subscriptions were confused with active transports, reporting Wi-Fi with no default connection. Default-agent selection and explicit offline state now have regression tests.

## Device observations and acceptance

The following are real device results, not simulated Android acceptance:

- AdGuard Home `v0.107.79` runs with protection enabled. Bundled anti-AD filter `10001` loaded **93,234** rules.
- Advertising-domain tests use `gdt.qq.com`; normal-domain tests use `example.com`. Blocked A/AAAA responses are `0.0.0.0`/`::`, while normal A/AAAA records remain available.
- IPv4 UDP/TCP and global IPv6 UDP/TCP A/AAAA packets passed under UID 2000, installed browser UID 10131, and **synthetic** clone-range UID 99910131.
- Scoped link-local IPv6 UDP A/AAAA passed under the same selected UIDs. Link-local IPv6 TCP is excluded from this passing matrix and remains unfiltered; see limits below.
- Pause detached owned interception/policy routing while preserving the core PID. Resume restored filtering.
- With IPv6 encrypted-port blocking temporarily enabled, five repeated real supervisor cycles retained the relay PID. The original port-blocking configuration was restored afterward.
- Core restart replaced its PID and restored filtering. Disable detached rules and stopped the core; enable recovered. Repeated supervisor cycles remained healthy.
- The module was installed by the real `ksud module install` path and the phone was rebooted. The installed module moved to `/data/adb/modules/AdGuardHome`, auto-started, retained ports/configuration, and repeated DNS acceptance passed.
- The Android Java/netd resolver probe returned the blocked address for `gdt.qq.com`.
- Xiaomi Browser loaded the normal test page (`Example Domain` in the UI hierarchy). After a cold browser launch, `doubleclick.net` showed `网页无法访问`. This is limited browser evidence, not an all-app advertising score.
- Wi-Fi off/on was exercised and Wi-Fi restored. Both SIM slots report `ABSENT`; there is no cellular subscription, so **mobile-data filtering was not verified**. The misleading offline Wi-Fi state was reproduced and repaired separately.
- A forced supervisor cycle while Wi-Fi was off reported `network=none/reason=no_network`, detached interception, and recovered to ready after Wi-Fi returned.

Probe UIDs run through KernelSU's execution context. They test UID firewall behavior, not every application's own SELinux context. This device currently has only user 0; there is no real running OEM clone profile, so the synthetic clone UID does not certify OEM clone behavior.

## Known limits — do not overstate completion

- **Link-local IPv6 TCP DNS remains unfiltered.** On this kernel, loopback-recirculated scoped TCP completes SYN/SYN-ACK but resets on ACK before application handling. The safe fallback leaves this path unchanged rather than breaking it. Diagnostics publish `ipv6_linklocal_tcp=false`. Link-local UDP and global IPv6 UDP/TCP are filtered.
- Application DoH, strict Android Private DNS, hard-coded IP connections, cached assets, and shared-domain feed/video advertisements can bypass DNS-level blocking. No TLS interception, global IPv6 disabling, broad DNS DROP, Private DNS setting rewrite, or application-data deletion is used.
- A Xiaomi Browser splash advertisement was still visible during one cold start. DNS filtering is not a claim that cached/same-domain splash advertisements are eliminated.
- VPN passthrough deliberately disables interception when a real VPN is active. Actual VPN-app compatibility is not certified by this session's simulated policy regressions.
- File-ad cleanup remains disabled by default. No unsafe guessed app directories or chat/database paths are cleared.
- Changed/damaged-policy repairs can still require a detach/rebuild transition; unchanged refresh is verified without destructive rebuilding.

## Reproducible validation

- `tests/device_dnsprobe.go`: static packet probe; explicitly selected authorized serial and non-root UIDs.
- `tests/device_dns_acceptance.py`: programmatic count/assertions and JSON per packet. Default covers 16 packets per UID; `--ipv6-udp-only` covers 12 and explicitly leaves the known link-local TCP path outside the passing set.
- `tests/AgHResolverProbe.java`: read-only Android platform resolver probe.
- `tests/run.sh`: retained full suite, native AGH DNS tests, installer/package checks and new safety/TPROXY regressions.
- Relay Go race/coverage tests run in a root **isolated network namespace**, with loopback enabled; they do not contend with host DNS port 53.

No existing tests were removed. The project has no measured full-shell coverage baseline, so no numeric claim about whole-project coverage retention is made. Critical DNS, lifecycle and firewall safety regressions are retained.

The parent repeated `tests/run.sh`, `tests/repair_regression.py`, BusyBox firewall regressions and the relay's complete `-race -cover -count=5` namespace suite. The relay reported **86.8% statement coverage** with no skips. This is helper coverage, not overall shell-module coverage.

## Artifact provenance

The final package reuses both ARM AdGuard Home binaries from the verified published `0.1.20` release, including its query-log refresh patch. New relay source is in `helper/dns-tproxy`; its ARM64/ARMv7 builds are static and checksummed. The package contains per-file `SHA256SUMS`; the delivered external SHA-256 must match the exact candidate ZIP, not an earlier local probe package.
