# Changelog

## 0.1.5

- Fixed modern Android network discovery without storing large `dumpsys connectivity` output in a shell argument.
- Added explicit Wi‑Fi, mobile-data, Ethernet, and VPN-over-Wi‑Fi/mobile detection and WebUI labels.
- Fixed iptables/ip6tables filter-table command syntax and fail closed when a rule cannot be installed.
- Added stricter command-recording firewall tests with injected failures.
- Added explicit filter-list readiness/count/size status.
- Apply real upstream profiles for LAN-compatible, encrypted-IP DoH, and Bootstrap modes; mode changes now validate and restart safely.
- Replaced unreachable Quad9 defaults with network-friendlier profiles and retained user-customized upstreams.

## 0.1.4

- Fixed the real first-run failure: initialize AdGuard Home from a missing config through the official install API instead of calling the unavailable install API on `users: []`.
- Wait up to 30 seconds for Web and DNS listeners and preserve precise failure reasons.
- Added a native AdGuard Home integration test that verifies the generated full YAML, bcrypt password hash, Web listener, and DNS listener.
- Discover network state independently when the core fails; block proxy adaptation until the core is ready.
- Added bilingual Chinese/English installation prompts, module status, WebUI text, state labels, error reasons, and action feedback with persisted automatic language detection.
- Disable the dashboard button until the core is actually ready.

## 0.1.3

- Preserve existing mode, feature toggles, ports, and credentials when upgrading older data without an install-options marker.

## 0.1.2

- Fixed the service entrypoint to start the supervisor daemon instead of an unsupported command.

## 0.1.1

- Fixed `SKIPUNZIP=1` installation so all lifecycle entrypoints are installed.
- Added first-install volume-key feature selection with safe defaults.
- Added persistent runtime adapter configuration and mode-schema upgrades.
- Added KernelSU native WebUI with status, mode, start, pause, resume, restart, adapter controls, credentials, and dashboard access.
- Added dynamic KernelSU module-card status and mode description.
- Fixed supervisor daemon startup and persistent pause behavior.
- Added end-to-end `customize.sh` installation simulation based on the actual installed module/data snapshots.

## 0.1.0

- Added A+ isolated worker architecture for core, network, firewall, proxy, file, and diagnostics.
- Added transactional migration from both referenced module layouts.
- Added owned, idempotent firewall chains and conditional adapter restoration.
- Removed runtime remote shell update behavior.
- Added attribution, third-party notices, and license provenance.

## Release policy

A public release is created only after package checks, hosted CI, and the documented device-validation boundary are reviewed.
