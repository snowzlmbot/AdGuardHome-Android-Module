# Security policy

## Scope

Report security issues in this module's scripts, packaging, update verification, credential handling, firewall ownership, migration, or adapter rollback.

AdGuard Home itself is an upstream component with its own security process. Report upstream vulnerabilities to AdguardTeam through the upstream project.

## Security guarantees and limits

- Runtime workers never download or execute remote shell scripts.
- Module updates are complete Release ZIPs verified before installation; background self-replacement is not used.
- Core credentials are generated locally and stored root-only.
- The Web UI and DNS listener are configured on loopback by default.
- Diagnostics redact credentials, serial numbers, raw DNS histories, and private network identifiers.
- Optional adapters are disabled by default and use conditional restoration.

A root-capable module cannot protect against a malicious root process or a compromised boot chain. IPv4/IPv6 53 and 853 blocking may affect legitimate VPN, DoT, DoQ, and IPv6-only use cases.

## Reporting

Do not include passwords, tokens, private device identifiers, raw diagnostic dumps, or private host paths in a public issue. Use a minimal reproduction and redact `scripts/diagnostics.sh` output before sharing.
