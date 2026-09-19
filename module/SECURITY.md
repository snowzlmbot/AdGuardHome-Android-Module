# Security policy

本项目涉及 Root 权限、DNS 流量和本地配置，请在安装和使用前了解以下安全信息。

## 安全设计

- 管理密码在设备本地生成，并保存为 root-only 文件。
- Web 管理页面和 DNS 服务默认监听本机回环地址。
- 更新通过完整 Release ZIP 和校验文件完成。
- 日志查看功能会隐藏密码、Token、Cookie、Authorization 等敏感字段。
- 代理和文件适配器默认关闭，文件操作使用备份和条件恢复。
- 防火墙规则使用模块专属链，卸载时只清理本模块创建的内容。

## 使用注意

- IPv4/IPv6 53 和 853 防泄漏可能影响合法的 DoT、DoQ、IPv6-only 网络、VPN 或代理模块。
- 文件级去广告可能影响特定应用的缓存和启动资源，建议先保持关闭。
- Root 模块无法防护已经获得 Root 权限的其他应用，也无法替代可信的启动链和系统安全策略。
- 请从本仓库的 GitHub Releases 获取可安装包，并使用同一 Release 的校验文件验证下载内容。

## 安全问题反馈

请通过 GitHub Security Advisories 或 Issue 反馈安全问题。提交日志和截图前，请移除密码、Token、设备标识、完整 DNS 查询记录和私人网络信息。

AdGuard Home 本身的安全问题请同时参考上游项目的安全流程：

https://github.com/AdguardTeam/AdGuardHome
