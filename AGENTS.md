# AGENTS.md

> ThermalPulse 的项目级 Codex 路由器。项目真相源位于 `AIREADME/`，本文件只负责启动顺序、任务路由、红线指针和维护责任。

## 当前状态

- 生命周期：active，pre-alpha。
- 产品定位：面向 macOS 26 以上 Apple Silicon MacBook Pro 的菜单栏温度小工具，集中展示 P 核、E 核、电池温度、风扇、系统热状态与一张曲线，并提供一次最多 10 分钟、可中途停止的 Turbo 全速散热。
- 最低系统：macOS 26.0，不支持 macOS 25 及更早版本。
- 当前工作树已有可构建的原生 SwiftUI 菜单栏 App、只读 `SMCReadAdapter`、typed sensor model、1 Hz 动态白名单采样、1 小时内存环形缓冲、P 核与 E 核热点、电池平均温度、一张固定 5 分钟温度曲线、固定 23 pt 高模板图片承载的紧凑菜单栏摘要、无滚动完整面板、单击启动 Turbo、倒计时与中途停止、私有 XPC，以及 helper 侧固定 600 秒租约、受限 FanWriteAdapter、持久租约、`Ftst` 接管的 100 毫秒稳定读回轮询与 3 秒失败上限、300 毫秒 active 看门狗、恢复失败立即重试、唤醒恢复与故障测试。菜单栏左列始终上下显示 P/E 核热点；右列动态适配风扇数量，单风扇垂直居中，双风扇上下排列，更多风扇只在展开面板完整显示。核心温度曲线会在展示前丢弃 10 至 120 °C 之外的原始哨兵点，并按真实时间间隙断线。不再创建独立监控窗口，没有安装包或发布版本。
- 当前 Mac16,7 已用普通权限读回 2 个风扇的实际与最大 RPM，并对 312 个动态采样项完成连续两轮零失败读回；Debug App 已完成 3605 秒真实运行，并承受 14 核 CPU 满载与 12 GiB 内存压力，全程未提前退出或产生错误日志。
- 已用 312 个序列加速模拟 1 Hz、3601 秒的数据路径并验证容量上限。优化后的最终 Release App 已完成 3605 秒持续运行，取得 60 个无间隔缺口的监督样本，未提前退出且日志为空。加入标记后的无操作 Release 12 分钟基线未复现旧性能台阶。2026-08-30 当前 Mac16,7 只读探测取得 102 个有效 `Tp` float 候选、10 个有效 `Te` float 候选和 `TB1T`、`TB2T` 两枚电池温度；这些证据只支持 P 核族、E 核族与电池族聚合，不支持逐 key 核心命名。
- 2026-08-30 用户已显式升级协议 v6 helper 并完成一次短时 Turbo。`Ftst` 从启动到连续稳定读回耗时约 0.98 秒，两台风扇在约 8.78 秒后取得实际 RPM 上升读回；用户主动停止后 helper 记录 `restoration_completed issue=none`，租约目录为空。后续只读门禁再次确认两台风扇处于 Apple 管理模式且 `Ftst=0`。本次只覆盖快速接管、active 和主动停止，不覆盖 600 秒到期、App 崩溃、XPC 断开、helper 重启或休眠恢复。
- 代码审查随后发现恢复失败只会在截止时间后重试、未知 `Ftst` 仍可能被写入、状态轮询可能与停止请求争用同一 XPC 请求槽，以及多风扇摘要可能继续变宽。提交 `934721e` 已修复这些问题并把协议升级为 v7；74 项普通测试通过、4 项硬件用例按设计跳过，独立只读恢复门禁 1 项通过，Personal Team v7 App 与内嵌 helper 均通过 strict 签名校验。当前系统仍运行已验收的 v6 helper，本轮没有升级 v7 helper、启动 Turbo 或写 SMC；未来运行 v7 App 时必须先单独授权升级 helper。
- 2026-08-30 第二台 Mac17,2、Apple M5 MacBook Pro 完成普通权限只读探测：动态读回 1 台风扇、小写 `F0md` 模式 key、6550 RPM 最大值、14 个有效 `Tp` 候选、4 个有效 `Te` 候选与两枚电池温度。单风扇布局与族级温度刻画已通过本机和 M5 测试，两台机器的完整普通测试均为 76 项通过、4 项硬件测试按设计跳过。M5 当时已有外部手动风扇控制，ThermalPulse 没有抢占、没有注册 helper 或启动 Turbo。
- 当前产品支持范围暂定为 macOS 26 以上 Apple Silicon MacBook Pro。Mac16,7、Apple M4 Pro 已验证双风扇监控和一次短时 Turbo；Mac17,2、Apple M5 已验证单风扇只读监控。其他 Apple Silicon MacBook Pro 仍须按能力发现和实机证据逐步加入支持矩阵，不能从这两台机器外推 Turbo 通过。

## 启动顺序

1. 读本文件。
2. 读 `AIREADME/INDEX.md`，按任务加载对应文件。
3. 开始任何实现前，至少读 `AIREADME/CORE.md`、`AIREADME/PRD.md`、`AIREADME/ARCHITECTURE.md` 和 `AIREADME/DECISIONS.md`。
4. 涉及 Turbo、root helper、SMC 写入、退出或休眠恢复时，再读 `AIREADME/SPEC.md` 与 `AIREADME/DEPLOYMENT.md`。
5. 当前系统、真实设备读回、代码和测试证据，高于历史草稿与推断。

## 任务路由

| 任务 | 必读 |
|---|---|
| 判断项目边界、安全红线 | `AIREADME/CORE.md` |
| 修改产品目标、交互和验收 | `AIREADME/PRD.md` |
| 修改组件、数据流、状态机 | `AIREADME/ARCHITECTURE.md` + `AIREADME/DECISIONS.md` |
| 修改本地接口或 XPC 契约 | `AIREADME/SPEC.md` |
| helper 注册、签名、安装、卸载 | `AIREADME/DEPLOYMENT.md` + `AIREADME/SPEC.md` |
| 安排功能先后 | `AIREADME/ROADMAP.md` |
| 写代码、测试、命名 | `AIREADME/CONVENTIONS.md` |
| 排查事故或复盘失败 | `AIREADME/MEMORY.md` |
| 发布或形成里程碑 | `AIREADME/CHANGELOG.md` |
| 跨项目依赖 | `AIREADME/RELATIONS.md` |

## 安全红线

完整定义见 `AIREADME/CORE.md` 的「绝不」和 `AIREADME/ARCHITECTURE.md` 的「禁改项」。实现时必须同时满足：

- 默认状态始终是苹果自动风扇控制。
- 监控功能不要求管理员权限，也不写 SMC。
- Turbo 只能把所有已验证风扇提升到各自最大转速，不能接受任意 RPM 或任意 SMC key。
- Turbo 单次最长 600 秒。到期、取消、App 退出、App 崩溃、XPC 断开、helper 重启和休眠唤醒后的过期检查，都必须恢复自动模式。
- 600 秒的安全期限由 privileged helper 独立执行，不能依赖 App 界面的 Timer。
- 任何状态不确定、传感器无效、风扇枚举失败或写入结果不可确认时，立即回到自动模式并禁用 Turbo。
- 不根据单台机器的 key、风扇数量或转速范围宣称跨机型支持。
- 不写入或提交密码、签名材料、设备标识、序列号和其他敏感信息。

## 证据边界

- 源码存在不等于 SMC 读写成功。
- 单元测试通过不等于 root helper 已获授权或能被 launchd 启动。
- helper 回复成功不等于风扇实际达到最大转速，必须读取实际 RPM 验证。
- App 正常退出恢复成功不等于崩溃、强杀、休眠和 helper 重启路径通过。
- 一台机器通过不等于其他 Apple Silicon 机型通过。
- 不把高功率模式、Turbo 或风扇全速描述成 CPU 频率保证。

## 工作方式

- 先做只读传感器探测与监控，再实现写入路径。
- 先验证原始 key、数据类型、合理范围和稳定性，再给传感器添加中文名称。
- root helper 使用最小权限和窄接口，拒绝通用 SMC 写入。
- 所有安全状态转换必须有自动化测试，涉及真实 SMC 写入的验收必须在目标 Mac 上人工授权并读回。
- 保留用户已有改动；提交时精确暂存目标文件，不默认使用 `git add -A`。
- commit、push、安装 helper、修改系统设置和发布是独立授权范围，不互相推断。

## 常用命令

```bash
git status --short --branch
bash ~/.agents/skills/aireadme/scripts/check.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ThermalPulse.xcodeproj -scheme ThermalPulse -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/thermal-pulse-derived CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project ThermalPulse.xcodeproj -scheme ThermalPulse -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/thermal-pulse-derived CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test
```

不要为了构建擅自修改全局 `xcode-select`。优先对单条命令设置 `DEVELOPER_DIR`。
真实 AppleSMC 探测只在明确需要硬件验收时运行 `ThermalPulseHardwareProbe` scheme；普通单元测试默认跳过它。

## 文档维护责任

- 定位、Non-Goals、安全红线变化：更新 `AIREADME/CORE.md`。
- 用户流程、成功指标、Turbo 产品行为变化：更新 `AIREADME/PRD.md`。
- 组件、数据流、状态机或关键选型变化：更新 `AIREADME/ARCHITECTURE.md`，重大理由追加到 `AIREADME/DECISIONS.md`。
- XPC 方法、参数、错误和兼容性变化：更新 `AIREADME/SPEC.md`。
- 签名、helper 注册、安装、卸载和回滚变化：更新 `AIREADME/DEPLOYMENT.md`。
- 编码和测试约定变化：更新 `AIREADME/CONVENTIONS.md`。
- 事故、失败和复盘：只追加 `AIREADME/MEMORY.md`。
- release 或明确里程碑：只追加 `AIREADME/CHANGELOG.md`。
- 任一 AIREADME 状态变化：同步 `AIREADME/INDEX.md`。

## 元信息

- slug：`thermal-pulse`
- 展示名：ThermalPulse
- 类型：macOS 本地产品 / code
- 目录：`~/Desktop/Projects/thermal-pulse`
- 文档标准：AIREADME v0.5-codex
