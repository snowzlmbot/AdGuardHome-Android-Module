# Android/KSU verification and troubleshooting

## Archive errors

Install the inner `AdGuardHome-Android-Module-<version>-agh-0.107.79.zip`, not GitHub Source ZIP or the Actions artifact container ZIP. KSU reads `module.prop` at the archive root before loading customize.sh. The message `specified file not found in archive` occurs when that lookup fails.

Validate the exact file with `python3 tests/validate_module_zip.py path/to/module.zip` and compare its SHA-256. The old v0.1.16 Release inspected during this repair has a root module.prop; without the user's exact ZIP we cannot claim its archive caused their message.

## Startup and filtering

After installation reboot once. Confirm core=ready, firewall=ready and VPN=false in WebUI. Read-only redacted status:

```sh
su -c 'sh /data/adb/modules/AdGuardHome/scripts/diagnostics/diagnostics.sh'
```

Do not share credentials.conf, the complete YAML, or raw query logs. Startup worker failures are retained in the local supervisor/core worker logs.

For DNS interception, turn Android Private DNS off and disable application-provided DoH during the test. The module does not change system settings automatically. With VPN passthrough enabled, a running VPN deliberately bypasses this module: use filtering inside the VPN or explicitly disable passthrough after backing up configuration. Port 853 blocking cannot force strict Private DNS clients to downgrade; port 443 blocking would also break ordinary HTTPS.

The offline anti-AD seed blocks independent ad domains, including gdt.qq.com, without blocking all qq.com or weixin.qq.com. Existing custom lists and deliberately disabled/removed filters are preserved. Shared-domain HTTPS feed ads (for example WeChat Moments/video feeds) cannot reliably be removed by DNS. No TLS interception or deletion of chat databases is included.

## Android runtime recovery

Scoped IPv6 DNS values (for example `fe80::1%wlan0`) are valid Android link-local addresses, not disconnected networks. Workers use the manager-provided static BusyBox directly; setting ASH_STANDALONE in mksh alone is not enough. Persistent module directories are private (0700).

The module may quarantine an incompatible module-owned cloud-rule cache and restore its validated bundled baseline without internet access. Explicit custom manifest paths are never silently replaced. The static HTTPS fetcher tries discovered DNS/bootstrap endpoints if Android's default resolver points to a non-listening loopback port; TLS certificates and payload checks remain mandatory.

## IPv6 NAT capability and 0.1.21 fallback

Some Xiaomi kernels ship `CONFIG_IP6_NF_NAT` disabled. A listening IPv6 AGH socket alone does not intercept the Android resolver's IPv6 DNS destinations. Version 0.1.21 adds a narrowly scoped IPv6 TPROXY relay for plain UDP/TCP port 53 on kernels that support IPv6 TPROXY and policy routing. It forwards DNS only to the module's loopback AdGuard Home port; IPv6 network connectivity and AAAA answers are not disabled. Root upstream traffic remains exempt to avoid recursion.

The fallback leaves **link-local IPv6 TCP DNS (`fe80::/10`) unfiltered**. On the tested Xiaomi kernel, recirculated scoped TCP resets during handshake; leaving this path unchanged is safer than blackholing it. Link-local UDP (the system resolver's observed path) and global IPv6 UDP/TCP are intercepted. Diagnostics expose `ipv6_linklocal_tcp=false`; this is not complete IPv6 DNS leak protection.

Read `ipv6_dns_applied` and `ipv6_dns_method`, not only the saved IPv6 toggle. Missing capabilities, occupied routing scope, failed setup, or a dead helper must remain visible as degradation, never a successful filtering claim. Pause/disable/stop must detach the owned forwarding rules before terminating listeners. Failed inspection means unknown state, not absent rules.

DNS mode 2 is **encrypted preferred with plaintext fallback**, not encrypted-only: the availability fallback preserves ordinary connectivity if the encrypted upstream fails. Application DoH and strict Private DNS are separate bypass paths.

The device acceptance command in `tests/device_dns_acceptance.py` requires a locally built `tests/device_dnsprobe.go` installed at `/data/local/tmp/agh-test/dnsprobe`, an explicitly chosen authorized serial and literal DNS destinations. It exercises real UDP/TCP A/AAAA queries under selected non-root UIDs and saves every result. A synthetic clone UID is not proof of a running OEM clone profile, and the probe's KernelSU execution context is not a browser/app SELinux-context test.

## Device validation still required

Cloud tests exercise real AdGuard Home queries over IPv4/IPv6 UDP/TCP, A/AAAA, normal domains, burst traffic, installer payloads, simulated firewall ordering, and BusyBox startup. They do not prove Android netd/eBPF behavior, OEM clone profiles, or KSU SELinux/device compatibility. Test a normal app and its clone on Wi-Fi/mobile and IPv6, then repeat with Private DNS/VPN as separate cases.
