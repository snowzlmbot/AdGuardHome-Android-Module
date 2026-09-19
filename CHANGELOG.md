# Changelog

## 0.1.12

- VPN passthrough is enabled by default when a VPN interface is active, keeping VPN servers usable on Wi‑Fi and mobile data.
- Added real-time policy toggles for IPv6 DNS, encrypted DNS ports, and VPN compatibility.
- Control actions trigger an immediate supervisor sync; background polling remains power-aware.
- Added query-log freshness and module-log viewing to the WebUI.
- Added fixed upstream profiles and safer adapter state persistence.

## 0.1.11

- Adds a separate native Android Manager app repository with Root-gated status/control and a stable module protocol.
- Keeps the installable module and project documentation clearly separated.

## 0.1.10

- Added VPN interface bypass for `tun`, `tap`, `wg`, `ppp`, and Tailscale-style interfaces.
- Keep Wi‑Fi/mobile DNS filtering active while allowing VPN DNS and encrypted DNS traffic through the VPN path.
- Added VPN-over-Wi‑Fi/mobile firewall tests and proxy coexistence behavior.

## 0.1.9

- Refined public project documentation and repository navigation.
- Added a separate native Android Manager repository with a documented module protocol.
- Added root-level license, credits, security, changelog, and third-party entry points.
- Added repository ownership metadata for @snowzlmbot.

## 0.1.8

- Refined public documentation and project navigation.
- Added repository-level license, credits, security, changelog, and third-party entry points.
- Added bilingual README navigation and clarified the installable `module/` directory.
- Added repository ownership metadata for @snowzlmbot.
