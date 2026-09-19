# AdGuardHome Android Module

[中文](README.md) | **English**

[![CI](https://github.com/snowzlmbot/AdGuardHome-Android-Module/actions/workflows/ci.yml/badge.svg)](https://github.com/snowzlmbot/AdGuardHome-Android-Module/actions/workflows/ci.yml)
[![Latest Release](https://img.shields.io/github/v/release/snowzlmbot/AdGuardHome-Android-Module?display_name=tag&sort=semver)](https://github.com/snowzlmbot/AdGuardHome-Android-Module/releases/latest)
[![License](https://img.shields.io/github/license/snowzlmbot/AdGuardHome-Android-Module)](LICENSE)

A modular AdGuard Home integration for rooted Android devices using Magisk or KernelSU.

> Current version: **0.1.8**

## Project links

| Document | Link |
| --- | --- |
| Changelog | [`CHANGELOG.md`](CHANGELOG.md) |
| License | [`LICENSE`](LICENSE) |
| Credits | [`CREDITS.md`](CREDITS.md) |
| Security policy | [`SECURITY.md`](SECURITY.md) |
| Third-party notices | [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) |
| Module layout | [`docs/MODULE_LAYOUT.md`](docs/MODULE_LAYOUT.md) |
| Latest release | [GitHub Releases](https://github.com/snowzlmbot/AdGuardHome-Android-Module/releases/latest) |

## Features

- Magisk and KernelSU support;
- ARM64 and ARMv7 release assets;
- LAN-compatible, encrypted-upstream, and Bootstrap DNS modes;
- Wi‑Fi, mobile data, Ethernet, VPN, and proxy-module compatibility;
- KernelSU WebUI and Magisk action entry;
- Fixed ports after first installation;
- Local random management credentials;
- Optional Box/Clash/Mihomo and file adapters;
- Module-owned, idempotent firewall rules;
- Release packages with checksum verification.

## Installation

1. Download the ZIP from [Latest Releases](https://github.com/snowzlmbot/AdGuardHome-Android-Module/releases/latest).
2. Verify it with the matching `SHA256SUMS` file.
3. Install it through Magisk or KernelSU.
4. Select the desired options during installation.
5. Reboot the device.
6. Open the KernelSU WebUI or the Magisk action button.

Do not flash a GitHub-generated Source ZIP. It is not an installable release package.

## Runtime layout

```text
module/       installable Magisk/KernelSU module
build/        release packaging and pinned assets
tests/        shell, native-core, migration, and installation tests
docs/         architecture and layout documentation
.github/      CI and Release workflows
```

The installable module itself is kept under `module/`; its contents become the root of the final ZIP.

## Credits and licenses

Thanks to [@410154425](https://github.com/410154425) and [@liuzq2002](https://github.com/liuzq2002). See [`CREDITS.md`](CREDITS.md) and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for upstream projects and license information.
