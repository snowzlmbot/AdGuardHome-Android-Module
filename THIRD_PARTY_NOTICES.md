# Third-party notices

This file records provenance for code, binaries, documentation, and rule data distributed by releases. It is not legal advice.

## Module control scripts

The scripts in this repository are new implementation code and are licensed under the root `LICENSE` unless a file states otherwise.

- `410154425/AdGuardHome_magisk`: behavior and architecture reference only for the audited commit `0375eeafc5b42b14933cbc3f496c67ff84d9cd1c`. The audited tree did not contain a license file. No script from that tree is copied into this implementation without separate permission.
- `liuzq2002/Adguard-Home-For-Magisk-Mod`: behavior and lifecycle reference for commit `ce9c57268614ee939fa25426e9912b62eac9cfed`. The upstream repository declares MIT; this implementation does not assume that MIT covers unrelated third-party material.

## AdGuard Home

- Project: https://github.com/AdguardTeam/AdGuardHome
- License: GPL-3.0
- Release assets must record the exact upstream version/tag, SHA-256, source URL, and corresponding source-code availability.
- The module's root license does not replace the AdGuard Home license.

## Rule data

Every bundled rule snapshot must record its source URL, source revision or retrieval date, SHA-256, and license in the release manifest.

- anti-AD: https://github.com/privacy-protection-tools/anti-AD — MIT license stated by upstream.
- GOODBYEADS: https://github.com/8680/GOODBYEADS — verify the license and snapshot provenance for each release.
- URLHaus/Hostlists Registry: https://adguardteam.github.io/HostlistsRegistry/ — verify the license of the exact generated snapshot before redistribution.

## Distribution rules

- Do not include the old payment image or donation redirect from the first module.
- Do not include private credentials, tokens, cookies, device identifiers, or local paths.
- Release ZIPs must include the applicable notices and checksum metadata.
- A source archive without architecture assets is not an installable module.
