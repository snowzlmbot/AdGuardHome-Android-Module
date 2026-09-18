# 模块目录规范

本仓库根目录同时作为“模块源码根”和“Release ZIP 的目标根”。

## 可进入最终 ZIP 的模块根文件

```text
module.prop
customize.sh
service.sh
action.sh
boot-completed.sh
uninstall.sh
scripts/
config/
targets/
licenses/
sbom/
```

这些路径必须保持在 ZIP 根目录，不能再包一层仓库名或 `module/` 目录；否则 Magisk/KernelSU 管理器无法按模块契约执行入口脚本。

## scripts 分层

```text
scripts/
├── core/          # AdGuard Home 进程和就绪状态
├── network/       # Android 网络/VPN/三模式状态发现
├── firewall/      # 本模块自有 IPv4/IPv6 规则
├── lifecycle/     # supervisor、control、migration、restore
├── adapters/      # 默认关闭的代理/文件适配器
├── diagnostics/   # 脱敏诊断
└── lib/           # POSIX/BusyBox ash 公共库
```

组件只能通过状态文件、请求文件和日志互相协调，不能跨组件直接修改其他组件的配置或进程。

## 仅源码仓库内容

以下目录不会被打包进入最终模块 ZIP：

```text
docs/
tests/
build/
.github/
.cache/
dist/
```

它们分别保存设计/使用文档、fixture 测试、可复现构建脚本、CI 工作流、临时资产缓存和本地构建产物。

## 兼容性原则

- 根入口脚本使用 Android `/system/bin/sh`。
- `scripts/` 下脚本只使用 BusyBox `ash` 可解析的语法。
- KernelSU 不使用 Recovery 专用 `META-INF` 安装器。
- 不通过 `.replace` 删除系统文件，也不依赖 metamodule；本模块不包含 `system/` 覆盖内容。
- `customize.sh` 负责解压和校验，`service.sh` 只启动生命周期控制面。
