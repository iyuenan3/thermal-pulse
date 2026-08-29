# AGENTS.md

> ThermalPulse 的项目级 Codex 路由器。项目真相源位于 `AIREADME/`，本文件只负责启动顺序、任务路由、红线指针和维护责任。

## 当前状态

- 生命周期：active，pre-alpha。
- 产品定位：macOS 本地热状态监控工具，提供活动监视器式传感器曲线，以及一次最多 10 分钟的 Turbo 全速散热。
- 最低系统：macOS 26.0，不支持 macOS 25 及更早版本。
- 当前已有可构建的原生 SwiftUI App、只读 `SMCReadAdapter`、typed sensor model、1 Hz 动态白名单采样、1 小时内存环形缓冲、无侧栏单页监控窗口、紧凑分组式菜单栏弹窗、菜单栏 P 核温度与全部风扇 RPM、默认风扇和温度曲线、App 侧 Turbo 协调器、固定身份的私有 XPC transport、`SMAppService` 显式注册与升级界面，以及 helper 侧固定 600 秒租约、受限 FanWriteAdapter、持久租约、看门狗、唤醒恢复与故障测试。最终写入版 helper 已完成系统升级和 XPC 状态实连；首次真实短时写入尝试触发读回不一致并安全回退，Turbo 尚未通过，也没有安装产物或发布。
- 当前 Mac16,7 已用普通权限读回 2 个风扇的实际与最大 RPM，并对 312 个动态采样项完成连续两轮零失败读回；Debug App 已完成 3605 秒真实运行，并承受 14 核 CPU 满载与 12 GiB 内存压力，全程未提前退出或产生错误日志。
- 已用 312 个序列加速模拟 1 Hz、3601 秒的数据路径并验证容量上限。优化后的最终 Release App 已完成 3605 秒持续运行，取得 60 个无间隔缺口的监督样本，未提前退出且日志为空。加入标记后的无操作 Release 12 分钟基线未复现旧性能台阶。当前 Mac16,7 的 `Tp` 动态温度族平均值已在 35 秒 CPU 负载中从 33.8 °C 升至 75.3 °C；该证据只支持族级 P 核响应，不支持逐 key 核心命名。当前普通测试共 57 项，55 项通过、2 项硬件只读测试按设计跳过、0 项失败；显式 HardwareProbe 为 57 项全部通过。
- 2026-08-30 用户显式授权一次短时 Turbo 实机测试。helper 没有进入 active，而是以 readback mismatch 返回 failed-safe-auto；监控曲线在激活阶段观察到最高约 2234 RPM 的短时上升。失败后租约文件已删除，独立只读复验确认 `F0Md=0`、`F1Md=0`、`Ftst=0`，实际 RPM 分别约为 1351 和 1462，root helper 继续运行。该结果只验收了失败保护后的 automatic 恢复，未验收最大目标、active、主动停止、600 秒到期、崩溃、断连、重启或休眠恢复。
- 首台验收机是当前 Mac16,7、Apple M4 Pro。它只是首个验证对象，不代表已支持全部 Apple Silicon 机型。

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
