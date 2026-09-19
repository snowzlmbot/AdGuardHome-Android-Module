# AdGuardHome Android Module

面向 Magisk 与 KernelSU 的模块化 AdGuard Home DNS 过滤模块。

> 这是一个参考两份公开项目后独立重写的实现。不会在线下载并执行远程 Shell，不会自动删除其他模块；代理与文件级去广告仅在用户明确启用后运行。

> **0.1.0 / 0.1.1 已知问题：** 旧版 `SKIPUNZIP=1` 安装流程漏解压生命周期脚本，且 0.1.1 的 service 入口仍使用旧命令。请直接升级/重刷 `0.1.2`；现有随机端口和凭据会保留。

## 主要功能

- 支持 Magisk、KernelSU；首版支持 arm64、armv7。
- 刷入时使用音量键选择 DNS 模式及功能开关。
- KernelSU 原生 WebUI：状态、模式、组件、启动、暂停、恢复、重启、适配器开关。
- 三种 DNS 模式：内网兼容、纯加密上游、Bootstrap。
- 核心、网络、防火墙、代理、文件适配器相互隔离，单个可选功能故障不会拖垮全部模块。
- 首次安装随机生成管理密码；不再使用公开的 `root/root`。
- 自有且幂等的 IPv4/IPv6 防火墙链。
- 可分别控制 IPv6 DNS 和 853 防泄漏。
- 支持迁移两个参考模块的旧配置。
- 卸载时执行条件恢复，不盲目覆盖用户后来修改的文件。
- 发布包中的 AdGuard Home 二进制来自官方固定版本并校验 SHA-256。

## 安装

1. 从 [GitHub Releases](https://github.com/snowzlmbot/AdGuardHome-Android-Module/releases) 下载模块 ZIP。
2. 使用同一 Release 下的 `SHA256SUMS` 校验。
3. 从 Magisk 或 KernelSU 管理器安装 ZIP。
4. 按刷入界面提示使用音量键选择功能。
5. 重启设备。

不要安装 GitHub 自动生成的 Source ZIP；它不包含 AdGuard Home 架构二进制。

## 刷入时功能选择

- **DNS 模式**
  - 模式 1：内网兼容；
  - 模式 2：纯加密上游，默认推荐；
  - 模式 3：Bootstrap，适合域名形式的 DoH/DoT/DoQ 上游。
- **IPv6 DNS 防泄漏**：默认开启。
- **853 防泄漏**：默认开启。
- **代理适配器**：默认关闭。
- **文件级去广告**：默认关闭。

音量上表示开启/选择，音量下表示关闭/下一项。无法读取按键时使用安全默认值，不会阻塞安装。

## 怎么使用

### KernelSU

进入 KernelSU 管理器 → 模块 → `AdGuardHome Android Module` → 打开 WebUI。

WebUI 可查看：

- 当前运行状态；
- 当前 DNS 模式；
- 核心、网络、防火墙、代理、文件组件状态；
- AdGuard Home Web 管理地址；
- 启动、暂停、恢复、重启核心；
- 代理和文件适配器开关；
- 管理凭据（需要主动点击才显示）。

KernelSU 模块列表中的描述也会动态显示当前状态和模式。

### Magisk

点击模块的“操作”按钮，会打开本机 AdGuard Home 管理页。也可以在 root shell 中使用：

```sh
# 启动
sh /data/adb/modules/AdGuardHome/action.sh start

# 暂停 DNS 过滤；AdGuard Home 核心仍保持运行
sh /data/adb/modules/AdGuardHome/action.sh pause

# 恢复
sh /data/adb/modules/AdGuardHome/action.sh resume

# 查看状态
sh /data/adb/modules/AdGuardHome/action.sh status

# 打开管理页
sh /data/adb/modules/AdGuardHome/action.sh open
```

普通用户不需要手动运行 `scripts/` 目录中的内部脚本。

## AdGuard Home Web 管理界面

管理地址采用动态端口：

```text
http://127.0.0.1:<web_port>
```

实际地址可在 KernelSU WebUI 查看，也记录在：

```text
/data/adb/agh/state/ports.conf
```

用户名：

```text
admin
```

随机密码保存在 root-only 文件：

```text
/data/adb/agh/state/credentials.conf
```

建议首次进入 AdGuard Home 后修改密码，并保存到密码管理器。

## 持久化数据

```text
/data/adb/agh/
├── bin/
├── config/
├── data/
├── state/
├── backup/
├── logs/
└── run/
```

升级模块不会直接覆盖已存在的用户配置。安装器会补齐新字段，但保留用户已经选择的模式与适配器开关。

## 可选适配器

代理适配器只接受明确白名单中的 Box、`box_bll`、Clash、Mihomo 路径；修改前生成备份与摘要。卸载时只有文件仍等于模块修改后的版本才自动恢复，避免覆盖用户后来的修改。

文件级去广告默认关闭。它拒绝路径穿越、符号链接和受保护系统路径，不使用无条件 `chattr +i`，遇到不安全目标立即停止。它不能代替 DNS 过滤。

## 风险说明

默认 53/853 防泄漏可能影响：

- IPv6-only 网络；
- 合法 DoT/DoQ 客户端；
- 某些 VPN 或代理模块；
- 使用自带加密 DNS 的应用。

遇到网络兼容问题时，应先通过 WebUI 检查防火墙与网络状态，再关闭对应防泄漏开关或更换模式。

## 目录结构

参见 [`docs/MODULE_LAYOUT.md`](docs/MODULE_LAYOUT.md)。Release ZIP 根目录符合 Magisk/KernelSU 模块结构；`tests/`、`docs/`、`build/` 和 `.github/` 不会进入最终模块包。

## 验证边界

仓库包含静态检查、迁移、核心、故障隔离、网络、防火墙、适配器、诊断、卸载、WebUI 和真实安装模拟测试。这些测试不能代替真实 Android、Magisk、KernelSU、SELinux 和不同 iptables 后端的真机验证。

## 致谢与许可证

参见：

- [`CREDITS.md`](CREDITS.md)
- [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)
- [`licenses/`](licenses/)

感谢原作者 top大佬 / `@410154425` 与后续维护者 `@liuzq2002`。新控制脚本为独立重写；AdGuard Home 与过滤规则继续遵循各自许可证。
