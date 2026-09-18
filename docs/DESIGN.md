# AdGuardHome Android Module 设计草案

> 目标仓库：`snowzlmbot/AdGuardHome-Android-Module`
>
> 状态：A+ 模块化设计草案；实现、真机测试和公开发布尚未完成。

## 1. 目标与范围

本项目面向 Magisk 与 KernelSU，首版支持 arm64 与 armv7。项目结合两个参考模块的有效思路，但不直接拼接其高风险实现：

- 原始项目：`410154425/AdGuardHome_magisk`
- 后续维护项目：`liuzq2002/Adguard-Home-For-Magisk-Mod`
- AdGuard Home 上游：`AdguardTeam/AdGuardHome`

首版目标：

- DNS 层广告过滤；
- IPv4/IPv6 DNS 防泄漏；
- TCP/UDP 853 防泄漏；
- 内网兼容、纯加密上游、Bootstrap 三种模式；
- Magisk/KernelSU 通用模块结构；
- arm64/armv7 架构选择与安装前校验；
- 首次安装生成随机管理密码；
- 可迁移两个旧模块的数据；
- 可暂停、恢复、禁用、卸载并回滚本模块状态；
- 代理适配器和文件级去广告适配器默认关闭；
- GitHub Release 校验更新，禁止后台执行远程 shell。

非目标：

- 不自动删除或卸载其他 Root 模块；
- 不默认修改第三方应用数据；
- 不默认切换飞行模式；
- 不使用远程下载后直接执行的更新链；
- 不把未授权的第一版脚本直接复制到新仓库。

## 2. A+ 总体架构

A+ 采用“生命周期协调器 + 独立功能组件”：

```text
service.sh
└── scripts/lifecycle/supervisor.sh   # 仅控制面，不实现业务逻辑
    ├── scripts/core/core-worker.sh   # AdGuard Home 进程
    ├── scripts/firewall/firewall-worker.sh # 本模块专属 iptables/ip6tables 规则
    ├── scripts/network/network-worker.sh   # 网络/VPN/模式状态计算
    ├── scripts/adapters/proxy-worker.sh    # 默认关闭，代理配置适配
    ├── scripts/adapters/file-worker.sh     # 默认关闭，文件级去广告
    └── scripts/diagnostics/diagnostics.sh  # 按需执行
```

每个组件拥有独立的 PID、锁、状态、请求和错误文件。组件分别写入独立日志。supervisor 只负责启动、停止、健康检查、状态汇总和依赖协调。

### 2.1 组件故障隔离

- 核心进程失败：防火墙组件删除 DNS 重定向，防止请求进入死端口；其他可选组件不被强制停止。
- 防火墙失败：核心继续运行，状态标记为 `degraded`，不切换飞行模式。
- 网络识别失败：不应用不完整的新参数，特殊旁路规则降级或撤销；核心继续运行。
- 代理适配失败：停止该适配器，不停止核心、防火墙或文件适配器。
- 文件适配失败：停止当前文件任务，保留备份记录，不影响其他组件。
- 诊断失败：只影响诊断，不影响任何运行组件。

唯一强依赖是“核心健康 -> DNS 重定向”：核心失效时必须先撤销指向核心的规则。

## 3. 目录设计

模块代码：

```text
/data/adb/modules/AdGuardHome/
```

运行数据：

```text
/data/adb/agh/
├── bin/
├── config/
├── data/filters/
├── state/
├── backup/migration/
├── backup/proxy/
├── backup/file-adapter/
├── logs/
└── run/
```

升级只替换模块代码和经校验的核心资产，用户配置、状态和备份留在 `/data/adb/agh`。

## 4. 生命周期数据流

### 4.1 安装

`customize.sh` 负责：

1. 识别 Magisk/KernelSU 与 `ARCH`/ABI；
2. 只接受 arm64 或 armv7；不支持时明确中止；
3. 检测第一版和维护版旧路径；
4. 将迁移内容复制到临时目录；
5. 验证 YAML、过滤器、二进制 ELF 架构和 SHA-256；
6. 生成或迁移配置；
7. 验证通过后原子切换；
8. 只保留本模块自己的文件和状态。

安装失败不能留下“已安装但核心缺失”的伪成功状态。

### 4.2 开机

`service.sh` 只等待必要的系统启动条件并启动 supervisor。supervisor 依次启动核心、网络和防火墙组件；代理与文件组件只有配置启用时才启动。

核心组件必须先确认 Web 端口和 DNS 端口真正监听，防火墙组件才可以安装 DNS 重定向。

### 4.3 暂停

暂停请求由控制文件或 action 入口提交给 supervisor：

- firewall-worker 删除 DNS 重定向；
- proxy-worker 停止新的配置同步；
- file-worker 停止新的清理任务；
- core-worker 默认保持运行。

### 4.4 禁用

禁用顺序：停止可选适配器、删除本模块防火墙规则、停止网络组件、停止核心。配置和备份保留。

### 4.5 卸载

卸载必须是幂等的：

1. 请求所有组件有界退出；
2. 强制停止仍存在的本模块进程；
3. 循环删除所有本模块防火墙跳转与专属链；
4. 条件恢复代理文件；
5. 条件恢复文件适配目标；
6. 恢复本模块曾经修改的系统设置；
7. 删除本模块运行目录；
8. 将无法恢复的项目写入日志和诊断状态。

## 5. 核心组件

core-worker 使用显式路径和参数启动 AdGuard Home：

```text
AdGuardHome \
  --config /data/adb/agh/config/AdGuardHome.yaml \
  --work-dir /data/adb/agh/data \
  --no-check-update
```

进程确认同时使用 PID、`/proc/<pid>/exe`、精确命令行和工作目录，不使用模糊的 `pgrep AdGuardHome` 或 `pkill AdGuardHome`。

首次安装生成随机管理密码，并将必要凭据放在 root-only 状态文件中。管理面和 DNS 默认绑定回环地址。

## 6. 网络模式

首版保留三个用户可选模式：

1. 内网兼容模式；
2. 纯 DoH/加密上游模式；
3. Bootstrap 模式，支持 DoH/DoT/DoQ 域名上游。

network-worker 只负责计算结构化状态，不直接写防火墙。例如：

```text
mode=lan-compatible
vpn=detected
dns_source=wifi
bootstrap=disabled
state_version=1
```

不复制旧版基于固定文本行、魔法地址、规则计数和端口 9 的判断方式。网络状态只有发生变化时才触发防火墙组件重算。

## 7. 防火墙组件

防火墙只管理带有本模块唯一前缀的专属链，不使用通用 `ADGUARD` 或 `TOPHOME` 链名。规则操作必须满足：

- 创建、检查、清理、删除幂等；
- 只删除本模块创建的跳转和规则；
- 使用 `-w` 和明确的 `-C`/`-D`/`-N`/`-F`；
- 不依赖人类可读的规则表行号；
- 不用固定第三行或字符串计数判断状态；
- 清理失败时记录具体命令和返回值；
- 核心未就绪时不安装重定向；
- IPv4/IPv6/853 规则独立开关和独立状态。

默认开关：

```text
redirect_ipv4_dns=true
redirect_ipv6_dns=true
block_ipv4_dot=true
block_ipv6_dot=true
block_ipv4_doq=true
block_ipv6_doq=true
```

README 必须说明这可能影响 IPv6-only 网络、合法 DoT/DoQ 客户端以及部分 VPN/代理。

## 8. 代理适配器

proxy-worker 默认关闭，首版仅覆盖已有维护项目明确涉及的 Box、`box_bll`、Clash、Mihomo 路径。

每个文件修改前保存：

- 原始字节；
- SHA-256；
- 权限；
- 属主；
- 可读取的 SELinux context；
- 修改原因和时间。

只处理明确识别的 YAML。禁止使用 Bash 数组、here-string、函数外 `local` 和变量命令字符串。卸载时仅在当前文件仍匹配模块修改后的摘要时自动恢复；用户改动过的文件只提示，不覆盖。

## 9. 文件级去广告适配器

file-worker 默认关闭。维护版目标清单只作为候选来源，所有目标必须经过安全元数据声明、路径规范化、风险分类和备份。

默认禁止：

- `/data/system/ifw`；
- 数据库；
- `shared_prefs`；
- 应用 `files` 根目录；
- 全局 `*==deleted==`；
- 空变量 `rm -rf`；
- 无条件 `chattr +i`。

目标恢复采用 `if-unchanged` 策略：如果文件已被用户或应用修改，不自动覆盖。文件适配器的任何失败都不能影响 DNS 核心。

## 10. 升级与迁移

支持两类旧路径：

- 第一版：模块目录中的 `AdGuardHome.yaml`、`mode.conf`、过滤器；
- 维护版：`/data/adb/agh/bin/AdGuardHome.yaml`、`config.prop`、过滤器。

迁移过程先复制到临时目录，验证完成后原子切换。迁移失败时保留旧数据并中止，禁止半迁移。

迁移内容包括：

- 用户、上游、过滤器、自定义规则；
- 三种模式配置；
- 代理订阅配置；
- 过滤器快照；
- 可恢复的适配器备份。

## 11. 更新与供应链

- 正式包只通过 GitHub Release 发布；
- CI 固定获取官方 AdGuard Home 版本；
- 构建阶段校验官方 SHA-256/GitHub digest；
- Release 包提供 `SHA256SUMS`、第三方声明和 GPL 文本；
- 可选检查并下载完整 Release ZIP；
- 校验通过后只提示用户手动安装；
- 运行时不下载并执行远程 shell；
- 不允许后台替换脚本、二进制或配置；
- 不以第三方中转站作为唯一下载源。

## 12. 许可证与致谢

原始项目固定提交未发现模块级许可证，因此新项目不直接复制其脚本；采用行为级参考并在 `CREDITS.md` 中致谢。

维护项目的 MIT 许可证及版权声明必须在实际复用其代码时保留。AdGuard Home 二进制按 GPL-3.0 履行通知、版本和源码获取义务。过滤器逐项记录来源、版本、哈希和适用许可证。

计划交付：

- `LICENSE`；
- `CREDITS.md`；
- `THIRD_PARTY_NOTICES.md`；
- `SHA256SUMS`；
- `SBOM.spdx.json`；
- Release ZIP 中的对应许可证和来源文件。

## 13. 验证要求

静态验证：

- 所有 shell 通过 BusyBox ash 语法检查；
- 不能出现 Bash 数组、here-string、函数外 `local`；
- 检查危险删除命令和远程 shell 执行链；
- 验证所有模块文件路径、权限和元数据；
- 验证二进制 ELF 架构和 SHA-256。

行为验证：

- Magisk/KernelSU 冷启动；
- 软重启与核心已存活场景；
- arm64/armv7 安装选择；
- 不支持 ABI 明确失败；
- 三种 DNS 模式；
- IPv4/IPv6/853 独立开关；
- 外部清空防火墙规则后的自愈；
- 核心失败时规则安全撤销；
- 代理适配器失败不影响核心；
- 文件适配器失败不影响核心；
- 配置迁移失败时旧数据不变；
- 卸载后的规则、进程和备份恢复；
- SELinux enforcing 下的 AVC 观察；
- 私人 DNS 和飞行模式原值恢复。

当前限制：尚未执行真实 Android/Magisk/KernelSU 设备安装、iptables 后端验证、SELinux enforcing 验证和文件适配器恢复测试。
