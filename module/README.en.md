# AdGuardHome Android Module

[中文](README.md) | **English**

A modular AdGuard Home integration for rooted Android devices using Magisk or KernelSU.

> Current version: **0.1.8**

KernelSU users can open the module WebUI to view status, DNS mode, network/VPN state, firewall state, filter readiness, and recent redacted logs. Magisk users can use the module action button to open the local dashboard and view the generated login credential.

## Features

- DNS filtering with LAN-compatible, encrypted-upstream, and Bootstrap modes;
- Wi‑Fi, mobile data, Ethernet, VPN, and proxy-module compatibility;
- Persistent ports, credentials, user configuration, and filter data;
- Optional Box/Clash/Mihomo integration and file-level cleanup;
- KernelSU WebUI with start, pause, resume, restart, mode, and adapter controls;
- ARM64 and ARMv7 release assets;
- Release packages with checksum verification.

## Installation

1. Install the Release ZIP with Magisk or KernelSU.
2. Choose the desired options during installation.
3. Reboot the device.
4. Open the module WebUI or the Magisk action button.

The first installation creates the local management credential and port configuration. Later upgrades keep the existing ports, credential, mode, and adapter selections.

## Dashboard

The local AdGuard Home dashboard uses the fixed Web port saved in:

```text
/data/adb/agh/state/ports.conf
```

The username is `admin`; the generated password is stored in the root-only credentials file.

## Module directory

This directory is the installable module root. The repository root contains the project documentation, build scripts, tests, and CI configuration.
