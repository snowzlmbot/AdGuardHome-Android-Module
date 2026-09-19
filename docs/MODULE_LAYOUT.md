# 模块目录规范

仓库根目录保存工程资料，`module/` 是真实的 Magisk/KernelSU 模块根。所有模块入口、Shell、配置、WebUI 和资源都在 `module/` 下。

```text
module/
├── module.prop
├── customize.sh
├── service.sh
├── action.sh
├── boot-completed.sh
├── uninstall.sh
├── scripts/
├── config/
├── targets/
├── webroot/
├── licenses/
└── sbom/
```

Release ZIP 由 `build/package.sh` 把 `module/` 内容放到 ZIP 根目录，不能把源码仓库根或 `module/` 目录本身再包一层。

## scripts 分层

```text
module/scripts/
├── core/          # AdGuard Home 进程和就绪状态
├── network/       # Android 网络/VPN/三模式状态发现
├── firewall/      # 本模块自有 IPv4/IPv6 规则
├── lifecycle/     # supervisor、control、migration、restore
├── adapters/      # 默认关闭的代理/文件适配器
├── diagnostics/   # 脱敏诊断
└── lib/           # POSIX/BusyBox ash 公共库
```

组件只能通过状态文件、请求文件和日志互相协调，不能跨组件直接修改其他组件的配置或进程。

## 仅源码工程内容

以下目录只存在源码仓库，不会进入最终模块 ZIP：

```text
docs/
tests/
build/
.github/
.cache/
dist/
```
