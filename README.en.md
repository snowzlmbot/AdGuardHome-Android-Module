# AdGuardHome Android Module

A modular AdGuard Home integration for rooted Android devices using Magisk or KernelSU.

The project uses isolated workers for the core, network discovery, firewall, proxy integration, file-level cleanup, and diagnostics. Optional adapters are disabled by default. Runtime remote shell updates and broad process-name kills are intentionally not used.

## Scope

- Magisk and KernelSU.
- ARM64 and ARMv7 release assets.
- Three DNS modes: LAN-compatible, encrypted-upstream, and bootstrap.
- Random first-install management credentials.
- Transactional migration from both referenced module layouts.
- Idempotent module-owned firewall chains.
- Reversible, explicitly enabled proxy/file adapters.
- Release-only updates with cryptographic verification.

The first release does not claim APatch, x86, x86_64, or real-device compatibility until the corresponding validation evidence is published.

See `README.md` for installation, safety notes, development tests, attribution, and third-party license information.
