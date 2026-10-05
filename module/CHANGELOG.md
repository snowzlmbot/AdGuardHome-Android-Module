# Changelog

## 0.1.22 (candidate)

- Add opt-in per-app HTTPDNS endpoint blocking (`block_app_httpdns` in mode.conf) that stops apps from bypassing ordinary DNS filtering through HTTPDNS over TLS/443, using precise `tcp-reset` REJECT rules scoped to the app UID. Ships with Coolapk endpoints measured on a Xiaomi 14 Ultra.
- Unchanged HTTPDNS rules reuse the existing journaled verify/rebuild path: no destructive refresh, exact rollback, and foreign rules stay untouched.
- Limits: IPv4 only; endpoints come from a static list (`/data/adb/agh/config/httpdns-targets.conf`, editable) that can go stale with app updates; blocking must be enabled in mode.conf; at most 64 targets are applied and invalid/unresolvable lines are skipped and logged, never failing the firewall.

## 0.1.21 (candidate)

- Fix false VPN detection from inactive system tunnels and Android VPN subscriptions; choose the active default network instead of stale agents and requests.
- Add a reversible, loopback-only IPv6 DNS TPROXY fallback for kernels without IPv6 NAT, including scoped link-local UDP routing. Link-local IPv6 TCP remains explicitly unfiltered because the tested kernel resets its recirculated handshake.
- Verify unchanged firewall rules without destructive refresh, keep listeners alive when removal cannot be proven, and preserve unrelated Android/module firewall rules.
- Distinguish requested and applied IPv6 policy in diagnostics/WebUI. Label mode 2 accurately as encrypted-preferred with plaintext availability fallback.
- Add real-device DNS probes, network/lifecycle regressions, a statically built DNS relay, checksummed installation and package verification.
- Preserve credentials, ports, custom configuration and disabled file-ad cleanup; do not disable global IPv6, rewrite Private DNS settings, or clear application data.

## 0.1.20

- Accept scoped IPv6 DNS addresses reported by Android without disabling a usable network.
- Re-execute file-backed workers in the manager's static BusyBox shell and remove unverified toybox dependencies; inherited environment markers cannot suppress setup.
- Quarantine incompatible module-owned downloaded manifests and recover the validated bundled baseline offline; explicit custom paths remain fail-closed.
- Add explicit DNS fallback for the static HTTPS downloader when Android exposes no working system resolver; certificate verification is unchanged.
- Keep persistent runtime directories private with 0700 permissions.

## 0.1.19

- Fix the VPN switch state-key mismatch and clear every VPN DNS exemption when disabled.
- Pin compatible cloud rules and migrate the old default URL without replacing custom sources.
- Separate cloud download from file cleanup and expose phase-specific errors.
- Replace optional flock with a portable PID/start-time cycle lock.
- Ship a static certificate-verifying HTTPS fetch helper to avoid BusyBox TLS build differences; reject plaintext, invalid certificates, insecure redirects and oversized payloads.

## 0.1.18

- Remove and verify module-owned DNS redirection before restarting, disabling, recovering, or changing the core mode; do not stop the listener when rule removal fails.
- Execute stop cleanup synchronously rather than leaving unconsumed component requests; a one-shot status cycle cannot revive a stopped service.
- Add a read-only core readiness check and lifecycle-order regressions for normal and injected-failure paths.

## 0.1.17

- Strengthened the KernelSU archive contract: validation rejects Source ZIPs, wrapper directories, missing runtime entries, and damaged payloads before delivery.
- Recovered stale supervisor locks and foreign PID files after reboot instead of silently skipping startup.
- Made workers use the KernelSU-provided BusyBox shell environment, logged startup failures, and made the Android CA path explicit for encrypted upstreams.
- Kept cloned-user DNS on the module-owned path, stopped globally exempting application DNS to upstreams, and disabled strict port-853 blocking by default because it can make Private DNS clients lose all connectivity.
- Added an offline, checksummed anti-AD seed with filtering enabled by default; explicit user filter removals and custom lists remain untouched.
- Extended file cleanup safety for Android user/profile paths and dedicated cache regeneration; no guessed Coolapk/WeChat paths or protected databases/app roots are cleared.

## 0.1.16

- Added WebUI URL fields for cloud rule resources, SHA-256 links, and GitHub parsed-file links; GitHub blob URLs are normalized to raw URLs.
- Made reboot startup invoke workers through `sh` for Android shell compatibility and clarified VPN passthrough as an explicit unfiltered state.
- Fixed rule-link persistence and diagnostics read-back for cloud-delivered resources.

## 0.1.15

- Reintroduced the full second-maintainer file-ad cleanup manifest with provenance and safe blocked entries for protected paths.
- Added signed-by-checksum remote rule refresh and persistent manifest delivery from the module WebUI.
- Added package-filtered one-shot cleanup for newly installed apps; absent apps never create placeholder folders.
- Changed changed-target handling to warn and continue processing other installed apps instead of blocking the whole adapter.
- Added file-rule metrics and Android toybox compatibility for state writes.

## 0.1.14

- Added a repository-built AdGuard Home 0.107.79 binary with guarded five-second query-log refresh for the legacy and current dashboards.
- Added encrypted-upstream fallback, shorter failure timeout, and optimistic-cache defaults to reduce cold-query stalls.
- Added network-readiness fail-open behavior, complete upstream firewall exemptions, and an explicit VPN-bypassed state.
- Fixed proxy/file adapter idempotency, Android command-environment compatibility, restore failure propagation, and safe uninstall behavior.

## 0.1.13

- Added one-tap configuration backup from KernelSU WebUI.
- Added persistent VPN and security-policy switches to the WebUI.
- Added immediate control synchronization and power-aware background polling.
- Improved public project documentation and separate Android Manager planning.

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
