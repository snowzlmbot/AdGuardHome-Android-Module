# Third-party notices

本项目包含或引用以下上游软件、规则数据和开发资料。各组件继续遵循其原始许可证。

## Related module projects

- [AdGuardHome_magisk](https://github.com/410154425/AdGuardHome_magisk) by [@410154425](https://github.com/410154425)
- [Adguard-Home-For-Magisk-Mod](https://github.com/liuzq2002/Adguard-Home-For-Magisk-Mod) by [@liuzq2002](https://github.com/liuzq2002)

本项目的模块控制代码根据公开项目的功能经验重新组织和实现；具体致谢见 [`CREDITS.md`](CREDITS.md)。

## AdGuard Home

- Project: https://github.com/AdguardTeam/AdGuardHome
- License: GPL-3.0
- Bundled release: `v0.107.79`
- Official license text: `licenses/AdGuardHome-GPL-3.0.txt`

AdGuard Home 基于上游 commit `05ba17b282da1c4393d6a4ba4db0cf519194a362` 和本仓库查询日志刷新补丁构建；0.1.21 真机候选复用已校验的 0.1.20 ARM64/ARMv7 成品核心。构建与分发校验 SHA-256，并保留 GPL-3.0 许可证和补丁来源。

## Module DNS helpers

- Static HTTPS fetcher: `helper/http-fetch`, source in this repository, MIT.
- IPv6 transparent DNS relay: `helper/dns-tproxy`, source in this repository, MIT; forwards DNS only to the module loopback core.
- Both helpers use the Go standard library and carry architecture-specific SHA-256 files in the module package.

## KernelSU

- Project: https://github.com/tiann/KernelSU
- Documentation: https://kernelsu.org/zh_CN/

## Rule data

- anti-AD: https://github.com/privacy-protection-tools/anti-AD — MIT
- GOODBYEADS: https://github.com/8680/GOODBYEADS
- Hostlists Registry / URLHaus: https://adguardteam.github.io/HostlistsRegistry/

- Bundled snapshot: `rules/anti-ad-easylist.txt`, upstream commit `8844e57276de1994b2f222c42d87dc7d9affee09`.
- Source: https://raw.githubusercontent.com/privacy-protection-tools/anti-AD/8844e57276de1994b2f222c42d87dc7d9affee09/anti-ad-easylist.txt
- SHA-256: `af74155ec0ee7cdf276d98129bc744695d3d3ed68d308c727bcc0c32fe83c46b`.
- License text: `licenses/anti-AD-MIT.txt`. Runtime subscription: https://anti-ad.net/easylist.txt

规则快照的来源、版本、校验和与许可证信息应随对应 Release 记录。

## Distribution files

发布包包含适用的许可证、来源说明和校验文件。不同组件的许可证独立适用，仓库根目录的 MIT License 不会替代上游组件许可证。
