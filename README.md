# AdGuardHome Android Module

一个面向 Magisk 与 KernelSU 的模块化 AdGuard Home 项目。

## 项目结构

- [`module/`](module/)：真实可安装模块目录；所有模块入口、脚本、配置、WebUI、许可证和资源均在这里。
- [`tests/`](tests/)：静态、迁移、核心、网络、防火墙、适配器和安装模拟测试。
- [`build/`](build/)：固定官方 AdGuard Home 资产并生成 Release ZIP。
- [`docs/`](docs/)：架构和目录设计。
- [Release](https://github.com/snowzlmbot/AdGuardHome-Android-Module/releases)：下载可刷入包。

请从 Release 下载模块 ZIP，不要把 GitHub Source ZIP 直接刷入 Magisk 或 KernelSU。

详细安装和使用说明见 [`module/README.md`](module/README.md)。

## Credits

感谢原作者 @410154425 与后续维护者 @liuzq2002；详见 [`module/CREDITS.md`](module/CREDITS.md)。
