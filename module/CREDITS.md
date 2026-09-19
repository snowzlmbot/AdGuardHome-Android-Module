# Credits

## Original module

Thanks to top大佬 / @410154425 for the original AdGuardHome Magisk module:

- https://github.com/410154425/AdGuardHome_magisk

The original project was the reference for the initial Android integration, DNS redirection modes, local-network/VPN compatibility ideas, pause/resume behavior, and ARM architecture packaging.

## Continued development

Thanks to @liuzq2002 for the continued development project:

- https://github.com/liuzq2002/Adguard-Home-For-Magisk-Mod

The continued project was the reference for modular lifecycle organization, dynamic management ports, proxy integration direction, diagnostics, update metadata, and uninstall workflow.

## KernelSU

- KernelSU documentation: https://kernelsu.org/zh_CN/guide/what-is-kernelsu.html
- KernelSU module differences: https://kernelsu.org/zh_CN/guide/difference-with-magisk.html

## Upstream software and rules

- AdGuard Home by AdguardTeam: https://github.com/AdguardTeam/AdGuardHome
- anti-AD: https://github.com/privacy-protection-tools/anti-AD
- GOODBYEADS and other rule sources are listed in `THIRD_PARTY_NOTICES.md`.

This project uses an independent rewrite of its module control scripts. The first referenced repository did not provide a module-level license in the audited commit, so its scripts are not copied and relabeled under this project's license.
