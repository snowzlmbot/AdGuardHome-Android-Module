# Changelog

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
