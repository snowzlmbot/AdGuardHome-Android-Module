# 0.1.22 真机验收：按应用阻断 HTTPDNS 绕过端点

设备：小米 14 Ultra（24031PN0DC，HyperOS/Android 16，API 36，KernelSU），Wi-Fi，无 SIM。
安装包：`dist/AdGuardHome-Android-Module-0.1.22-agh-0.107.79.zip`
SHA-256：`c9f09da91f34eb73ed77ca876cd21db4d3132e00cf7900a6daaac453edd6f066`

## 背景现象

酷安官网 16.6.4（`com.coolapk.market`，UID 10319）在 0.1.21 及更早版本的过滤下仍能显示穿山甲商业开屏（用户截图：抖音“海量音乐 免费畅听”带跳过；真机录像：夸克开屏带跳过）。普通 DNS 路径已拦截穿山甲域名（`api-access.pangolin-sdk-toutiao.com` 等命中规则，UID 探针返回 0.0.0.0/::）。

链路证据：
- 酷安 `HTTPDNSFile.xml` 保存腾讯 HTTPDNS 端点；应用 UID 对 `119.29.29.87/.89/.91` 存在 TCP/443 连接。
- 端点限定抓包：TLS ClientHello 无 SNI（HTTPDNS 形态）。
- 穿山甲 `tt_ad/splash_image` 缓存存在与用户截图一致的素材（缓存存在不能单独证明投放路径）。
- 恢复原网络路径的对照冷启动复现抖音开屏；临时限制 4 个端点后 6 次冷启动均无开屏（视觉验证），首页正常。

## 0.1.22 功能

- `mode.conf` 新增 `block_app_httpdns`（默认 false，opt-in）。
- `config/httpdns-targets.conf`：`包名|IPv4|端口` 清单，随包默认带酷安 4 个实测端点；仅文件缺失时安装器写入，用户编辑可保留。
- 防火墙 v4 filter 链按包解析 UID（读 `/data/system/packages.list`，不经 binder——模块启动 SELinux 域调用 `cmd package` 会被拒绝，已实测确认并绕开）后追加精确 REJECT tcp-reset；沿用既有 verify/rebuild：不变免刷新、精确回滚、保留外来规则。
- 非法行/无 UID/root UID/超 64 条一律跳过并计数，不使防火墙回滚。仅 IPv4；IPv6 行跳过。

## 验收结果

1. 安装、重启后自启：core ready，firewall ready，`httpdns_block=true httpdns_rules=4 httpdns_skipped=0`。
2. 链读回：AGHADF4 内 4 条 `-d IP/32 -p tcp --dport 443 -m owner --uid-owner 10319 -j REJECT --reject-with tcp-reset`，位于 owner-0 RETURN 之后。
3. 实际拦截：3 次冷启动期间 REJECT 计数增长（3+9 包），证明应用确实尝试 HTTPDNS 且被切断。
4. 三次完整 MAIN/LAUNCHER 冷启动：录像 13–16s；启动 ~6s 时 UI 层级已出现“话题/关注/头条/首页”等首页元素、无“跳过/广告”节点；帧级饱和度序列无对照广告运行的 ~41 高平台（对照运行 2.5–8.5s 持续 ~41.6，三次托管运行分别为 17.4/5.7/7.8 峰值）。首页文字、图片正常加载，`end_home=true`。
   - 说明：本轮会话中视觉模型不可用，以上为层级+定量信号；早先视觉已验证的 A/B 对照（相同规则语义）作为机制基准。原始录像保留，可人工复核。
5. 开关往返：`false` → 链中 0 条 REJECT；`true` → 4 条恢复。
6. DNS 核心路径无回归：UID 2000 20/20；UID 10319 前台 20/20（v4/全局 v6 UDP/TCP、链路本地 v6 UDP × A/AAAA × 广告/正常），链路本地 TCP 按既有文档旁路。UID 10319 后台探针 EPERM 为 Android 后台数据限制（`netpolicy` blocked=APP_BACKGROUND，idle=true），不是过滤故障；前台即恢复。
7. 测试：主机 sh 回归 35/35；Colima VM busybox ash 回归 35/35；完整 `tests/run.sh` 通过；打包契约、校验和、installer 契约通过。

## 限制

- 仅 IPv4；端点清单为静态，应用轮换 IP 后需自行维护 `/data/adb/agh/config/httpdns-targets.conf`。
- 只覆盖清单内端点的 TCP 连接；不声称消除酷安全部广告（信息流/其他 SDK/DoH 等仍有边界）。
- 只对该包当前 UID 生效；卸载重装后 UID 变化，worker 每次循环重新解析并重建规则。
- 无 SIM，移动数据未实测；未验收 OEM 分身应用。
