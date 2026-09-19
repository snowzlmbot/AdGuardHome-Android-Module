# AdGuardHome Android Module

[![CI](https://github.com/snowzlmbot/AdGuardHome-Android-Module/actions/workflows/ci.yml/badge.svg)](https://github.com/snowzlmbot/AdGuardHome-Android-Module/actions/workflows/ci.yml)
[![Latest Release](https://img.shields.io/github/v/release/snowzlmbot/AdGuardHome-Android-Module?display_name=tag&sort=semver)](https://github.com/snowzlmbot/AdGuardHome-Android-Module/releases/latest)
[![License](https://img.shields.io/github/license/snowzlmbot/AdGuardHome-Android-Module)](LICENSE)

**中文** | [English](README.en.md)

一个面向 Magisk 与 KernelSU 的模块化 AdGuard Home Android DNS 过滤项目。

> 当前版本：**0.1.8**
>
> 直接下载：[AdGuardHome-Android-Module-0.1.8-agh-0.107.79.zip](https://github.com/snowzlmbot/AdGuardHome-Android-Module/releases/download/module-v0.1.8/AdGuardHome-Android-Module-0.1.8-agh-0.107.79.zip)

## 项目入口

| 文档 | 入口 |
| --- | --- |
| 更新日志 | [`CHANGELOG.md`](CHANGELOG.md) |
| 许可证 | [`LICENSE`](LICENSE) |
| 致谢 | [`CREDITS.md`](CREDITS.md) |
| 安全策略 | [`SECURITY.md`](SECURITY.md) |
| 第三方声明 | [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) |
| 模块目录规范 | [`docs/MODULE_LAYOUT.md`](docs/MODULE_LAYOUT.md) |
| 最新 Release | [GitHub Releases](https://github.com/snowzlmbot/AdGuardHome-Android-Module/releases/latest) |

## 项目定位

本项目将 AdGuard Home 集成到 Android Root 环境，提供 DNS 过滤、网络兼容、可选适配器和可视化控制功能。

- 原始项目：[@410154425](https://github.com/410154425) / [`AdGuardHome_magisk`](https://github.com/410154425/AdGuardHome_magisk)
- 后续维护项目：[@liuzq2002](https://github.com/liuzq2002) / [`Adguard-Home-For-Magisk-Mod`](https://github.com/liuzq2002/Adguard-Home-For-Magisk-Mod)

项目采用分层组件结构，让核心 DNS、网络发现、防火墙、代理适配、文件适配、诊断和生命周期可以独立运行和维护。

## 主要能力

| 能力 | 说明 |
| --- | --- |
| Root 管理器 | Magisk、KernelSU |
| CPU 架构 | arm64、armv7 |
| DNS 模式 | 内网兼容、纯加密上游、Bootstrap |
| 网络 | Wi‑Fi、移动数据、以太网、VPN 叠加、代理模块共存 |
| 控制 | 启动、暂停、恢复、重启核心、固定端口 |
| WebUI | KernelSU 原生 `webroot/` 控制台 |
| 凭据 | 首次本地生成随机管理密码，不使用 `root/root` |
| 适配器 | Box/Clash/Mihomo 代理适配；文件级去广告；默认关闭 |
| 更新方式 | GitHub Release 完整包与校验文件 |

## 安装与升级

1. 从 [Latest Release](https://github.com/snowzlmbot/AdGuardHome-Android-Module/releases/latest) 下载 ZIP。
2. 下载同一 Release 下的 `SHA256SUMS` 并校验：

   ```sh
   sha256sum -c SHA256SUMS
   ```

3. 在 Magisk 或 KernelSU 管理器中安装 ZIP。
4. 首次刷入按提示使用音量键选择模式和功能开关。
5. 重启设备。
6. KernelSU：进入模块页面打开 WebUI；Magisk：点击模块操作按钮。

不要直接刷 GitHub 自动生成的 Source ZIP。Source ZIP 不包含最终架构二进制，不是可安装成品。

### 首次安装选项

- DNS 模式 1：内网/校园网兼容；
- DNS 模式 2：纯加密上游，默认推荐；
- DNS 模式 3：Bootstrap；
- IPv6 DNS 防泄漏：默认开启；
- TCP/UDP 853 防泄漏：默认开启；
- 代理适配：默认关闭；
- 文件级去广告：默认关闭。

音量上键表示开启/选择，音量下键表示关闭/下一项。无法读取按键时使用安全默认值，不会卡住安装。

## 使用入口

### KernelSU WebUI

```text
KernelSU → 模块 → AdGuardHome Android Module → WebUI
```

可查看和操作：

- 运行状态和核心失败原因；
- Wi‑Fi/移动数据/以太网/VPN 状态；
- DNS 模式；
- 核心、防火墙、规则、代理、文件适配状态；
- 启动、暂停、恢复、重启核心；
- 打开 AdGuard Home 管理页；
- 打开查询日志：`/#logs?response_status=all`；
- 查看脱敏模块日志；
- 语言自动检测并持久化。

### Magisk 操作按钮

点击模块操作按钮后，会显示：

- 固定 Web 管理地址；
- 用户名；
- 随机密码；

随后自动打开浏览器。

日常使用无需手动执行 `scripts/` 中的模块脚本。

## 管理地址与数据

首次安装随机生成 Web/DNS 端口，之后升级和重启固定复用：

```text
http://127.0.0.1:<web_port>
```

端口文件：

```text
/data/adb/agh/state/ports.conf
```

管理用户名默认为：

```text
admin
```

随机密码只保存在：

```text
/data/adb/agh/state/credentials.conf
```

升级会保留已有端口、凭据、模式和适配器开关。

## 源码与成品目录

```text
AdGuardHome-Android-Module/
├── module/                 # 真实可安装模块根
│   ├── module.prop
│   ├── customize.sh
│   ├── service.sh
│   ├── action.sh
│   ├── boot-completed.sh
│   ├── uninstall.sh
│   ├── scripts/            # 所有模块 Shell 和公共库
│   ├── config/             # 默认配置与适配器配置
│   ├── targets/            # 文件适配目标清单
│   ├── webroot/             # KernelSU WebUI
│   ├── licenses/
│   └── sbom/
├── build/                  # Release 构建、资产和校验
├── tests/                  # fixture、原生核心和安装模拟测试
├── docs/                   # 架构和目录文档
├── .github/                # CI/Release workflow
├── LICENSE                 # 根目录许可证入口
├── CREDITS.md              # 根目录致谢入口
├── SECURITY.md             # 根目录安全策略
└── THIRD_PARTY_NOTICES.md  # 根目录第三方声明
```

详细目录规范：[`docs/MODULE_LAYOUT.md`](docs/MODULE_LAYOUT.md)

## 许可证、致谢与安全

- 许可证：[`LICENSE`](LICENSE)
- 致谢：[`CREDITS.md`](CREDITS.md)
- 安全策略：[`SECURITY.md`](SECURITY.md)
- 第三方声明：[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)
- AdGuard Home、过滤规则和 KernelSU 使用各自上游许可证。

感谢原作者 [@410154425](https://github.com/410154425) 与后续维护者 [@liuzq2002](https://github.com/liuzq2002)。
