# ARCHITECTURE：ThermalPulse

## 组件 + 数据流

### 普通用户进程

1. `SMCReadAdapter`：已实现。只读打开 AppleSMC，读取 key info、数据类型和原始值；C bridging header 固定校验 80 字节 user-client ABI。
2. typed sensor model + `SensorClassifier`：已实现首版。动态识别风扇数量、实际值和最大值；温度 key 仅作为未确认候选，不赋予部件名称。
3. `SMCProbeService`：已实现一次性全量 key 枚举、元数据扫描、候选白名单采样和逐项失败隔离。
4. `TelemetrySampler`：待实现。目标每秒采样一次，并读取 `ProcessInfo.thermalState`、风扇数量和实际 RPM。
5. `TimeSeriesStore`：待实现。内存环形缓冲保存最近 1 小时数据，不在首版自动写盘。
6. SwiftUI 监控壳：已实现菜单栏摘要、一次性探测状态、风扇读数和高级原始温度候选列表；统计值和多曲线仍待实现。
7. `TurboCoordinator`：待实现。维护用户可见状态和倒计时，通过私有 XPC 调用 helper，本身不写 SMC。

监控数据流：

`AppleSMC / ProcessInfo → SMCReadAdapter → SensorCatalog → TelemetrySampler → TimeSeriesStore → 菜单栏与监控窗口`

### privileged helper

1. `CallerValidator`：拒绝签名或协议版本不符合预期的 XPC 客户端。
2. `TurboLeaseStore`：保存 root-owned 的最小租约记录，包括是否由 ThermalPulse 接管、开始时间和绝对截止时间，不保存设备标识或用户数据。
3. `FanWriteAdapter`：只允许枚举风扇、读取模式和最大值、切换手动/自动、写各风扇最大目标值及读回。
4. `TurboWatchdog`：独立于 App UI 计时。到期、连接失效、状态矛盾或租约恢复时执行自动模式恢复。

Turbo 数据流：

`Turbo 按钮 → TurboCoordinator → 签名校验 XPC → TurboLeaseStore → FanWriteAdapter → AppleSMC → 模式和 RPM 读回 → UI`

## Turbo 安全状态机

- `inactive`：没有 ThermalPulse 租约，绝不写风扇。
- `activating`：确认风扇数量、模式、最大值和外部控制冲突，创建 600 秒租约后才切手动和全速。
- `active`：helper 持有绝对截止时间并持续验证租约。App 只展示剩余时间。
- `restoring`：先对所有已接管风扇写自动，再读回模式，成功后删除租约。
- `failed-safe-auto`：任一环节不可信时尽最大努力恢复自动，记录可诊断错误并禁止再次 Turbo，直到重新验证。

helper 启动或重启时先检查自己的持久租约：存在旧租约则恢复自动并清理；不存在租约时不改动风扇，避免破坏其他风扇控制工具的状态。

## 关键技术选型

- 原生 Swift macOS App，界面使用 SwiftUI 与必要的 AppKit 桥接，减少常驻菜单栏工具的运行时负担。
- 低层 SMC ABI 隔离在独立适配层，不让原始 key 和二进制布局扩散到 UI 与业务逻辑。
- privileged helper 采用 ServiceManagement 的现代注册方式和 XPC，不使用已弃用安装链路作为首选。
- 首版数据只保存在内存，先验证采样稳定性、传感器语义和界面价值，再决定是否持久化或导出。
- 关键选择与取舍见 DECISIONS 的 ADR-001 至 ADR-006。

## 当前只读实现证据

- Xcode targets：`ThermalPulse`、`ThermalPulseCore`、`ThermalPulseTests`。
- `SMCReadAdapter` 只定义 read bytes、read index 和 read key info 三类命令，不定义写命令。
- 普通测试验证 key 编码、80 字节 ABI、整数、定点数、Apple Silicon 小端浮点解码、分类和范围判断。
- `ThermalPulseHardwareProbe` 是显式硬件测试 scheme。2026-08-28 在当前 Mac16,7 上读到 3337 个 key、2 个风扇，并验证两个风扇的实际 RPM 不超过各自实时读回的最大 RPM。
- 全量扫描取得 3293 个 key 的元数据，按白名单采样 315 个候选；44 个不可读项被隔离计数，没有伪装为零或终止整轮扫描。
- 上述证据只覆盖普通权限只读路径，不覆盖持续采样、UI 人工验收、SMC 写入或 Turbo 安全恢复。

## 禁改项 / Forbidden Refactors

- 禁止把 SMC 写入移动到普通 App 进程。
- 禁止为方便测试而给 helper 增加通用 key、RPM 或时长参数。
- 禁止把 600 秒恢复责任交给 SwiftUI Timer、菜单栏生命周期或 App 退出回调。
- 禁止以单一 P 核温度替代多传感器监控，或把未知 key 猜成确定硬件部件。
- 禁止硬编码单风扇、风扇 0、某一机型的 RPM 上下限或旧 PRD 的 M5 key 表。
- 禁止在没有 ThermalPulse 租约时主动重置外部控制器的手动模式。
- 禁止用日志中的“写入成功”替代风扇模式和实际 RPM 的独立读回。
- 禁止让监控失败自动触发 Turbo。Turbo 永远是用户显式操作。
