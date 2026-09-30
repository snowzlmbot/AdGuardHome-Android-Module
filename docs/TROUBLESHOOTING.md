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

## Device validation still required

Cloud tests exercise real AdGuard Home queries over IPv4/IPv6 UDP/TCP, A/AAAA, normal domains, burst traffic, installer payloads, simulated firewall ordering, and BusyBox startup. They do not prove Android netd/eBPF behavior, OEM clone profiles, or KSU SELinux/device compatibility. Test a normal app and its clone on Wi-Fi/mobile and IPv6, then repeat with Private DNS/VPN as separate cases.
