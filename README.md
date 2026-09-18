# AdGuardHome Android Module

A modular AdGuard Home integration for rooted Android devices using Magisk or KernelSU.

> This project is an independent implementation inspired by two public projects. It does not execute remote shell updates, does not automatically remove other modules, and does not touch optional adapters unless the user enables them.

## Features

- Magisk and KernelSU module layout.
- arm64 and armv7 release assets; unsupported ABI aborts installation.
- Three explicit DNS modes: LAN-compatible, encrypted-upstream, and bootstrap.
- Isolated core, network, firewall, proxy-adapter, file-adapter, and diagnostics workers.
- Random first-install management credential stored root-only.
- Owned, idempotent IPv4/IPv6 firewall chains.
- Optional IPv4/IPv6 DNS and DoT/DoQ leak-prevention switches.
- Transactional migration from the two referenced module layouts.
- Proxy and file adapters disabled by default and conditionally reversible.
- Redacted diagnostics and repeatable uninstall.
- Release-only updates with checksum/signature verification; no runtime remote shell execution.

## Compatibility

The first release target is Magisk and KernelSU on ARM64 and ARMv7 Android devices. APatch, x86, and x86_64 are not claimed as supported by the first release.

KernelSU users must install through the KernelSU manager. This module does not depend on a metamodule because it does not provide a `/system` overlay.

## Installation

1. Download a module ZIP from GitHub Releases.
2. Verify the published SHA-256/SHA-512 metadata.
3. Install the ZIP from Magisk or KernelSU.
4. Reboot when the manager requests it.
5. Open the module action page and use `open` to open the local AdGuard Home UI.
6. Store the generated credential in a password manager and change it through the AdGuard Home UI.

Do not install the GitHub Source ZIP as a module. Release ZIPs contain architecture-specific AdGuard Home assets that are intentionally not committed to the source tree.

## Optional adapters

Proxy integration is disabled by default. It only accepts explicitly allowlisted Box, `box_bll`, Clash, and Mihomo configuration paths, creates a backup manifest, and restores only when the file still matches the module-modified digest.

File-level ad cleanup is disabled by default. It requires an explicit target manifest, rejects protected paths and symlinks, never uses unconditional `chattr +i`, and stops at the first unsafe target. It must not be treated as a replacement for DNS filtering.

## Repository layout

See [`docs/MODULE_LAYOUT.md`](docs/MODULE_LAYOUT.md) for the standardized module-root layout and A+ component boundaries.

## Safety behavior

- A failed optional adapter does not stop AdGuard Home.
- A failed firewall worker does not stop the core; status becomes degraded.
- A failed core removes its DNS redirect before retrying.
- Uninstall never broad-kills processes by name.
- User-modified proxy or file targets are preserved and reported instead of silently overwritten.
- The default 53/853 leak-prevention settings can affect IPv6-only networks, legitimate DoT/DoQ clients, VPNs, and proxy modules. Disable them individually when required.

## Development

```sh
sh tests/platform_test.sh
sh tests/credentials_test.sh
sh tests/migration_test.sh
sh tests/core_worker_test.sh
sh tests/supervisor_test.sh
sh tests/network_test.sh
sh tests/firewall_test.sh
sh tests/proxy_adapter_test.sh
sh tests/file_adapter_test.sh
sh tests/diagnostics_test.sh
sh tests/uninstall_test.sh
BUSYBOX_BIN=busybox sh tests/static/check-shell.sh .
```

These are deterministic shell/fixture tests. They are not proof of real Android, Magisk, KernelSU, iptables backend, or SELinux compatibility; device validation remains required before a release is advertised as supported.

## Attribution and licenses

See `CREDITS.md`, `THIRD_PARTY_NOTICES.md`, and `licenses/`. The module's original scripts are licensed under the root `LICENSE`. AdGuard Home and filter data retain their own licenses.
