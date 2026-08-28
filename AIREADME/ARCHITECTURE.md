# ARCHITECTURE：ThermalPulse

## 组件 + 数据流

### 普通用户进程

1. `SMCReadAdapter`：已实现。只读打开 AppleSMC，读取 key info、数据类型和原始值；C bridging header 固定校验 80 字节 user-client ABI。
2. typed sensor model + `SensorClassifier`：已实现首版。动态识别风扇数量、实际值和最大值；温度 key 仅作为未确认候选，不赋予部件名称。
3. `SMCProbeService`：已实现启动或手动刷新时的一次性全量 key 枚举、元数据缓存、动态采样白名单和逐项失败隔离。每秒采样直接复用已验证元数据，不重复枚举。
4. `TelemetrySampler`：已实现。使用单调时钟按 1 Hz 读取有效的风扇实际转速与温度候选，同时采集 `ProcessInfo.thermalState`；错过节拍时丢弃旧节拍，不追赶突发读取。
5. `TimeSeriesStore`：已实现。每个传感器用固定容量 3600 的内存环形缓冲保存有效样本，无效或不可用值只保留在最新帧，不污染统计历史。总数、最新值、最小值、最大值和总和随写入增量维护；只有淘汰当前极值时扫描单个环形缓冲重算极值。
6. `TelemetryPresentation`：已实现选择策略和显示降采样。默认只选运行时验证过的风扇实际 RPM，最多同时选择 6 项；原始温度候选必须手动加入。显示层按时间桶保留端点与局部极值，并按超过 1.75 秒的间隙拆段。
7. SwiftUI 监控界面：已实现菜单栏摘要、探测与采样状态、风扇读数、高级原始温度候选列表、统计，以及 5 分钟、15 分钟和 1 小时曲线。RPM 与摄氏度使用独立图表和纵轴，避免把不同单位画在同一数值尺度。
8. `TurboCoordinator`：待实现。维护用户可见状态和倒计时，通过私有 XPC 调用 helper，本身不写 SMC。

监控数据流：

`AppleSMC / ProcessInfo → SMCReadAdapter → SensorCatalog → TelemetrySampler → TimeSeriesStore → 选择与显示降采样 → 菜单栏与监控窗口`

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
- 全量枚举只在启动或用户手动刷新时执行。稳定白名单采样使用缓存元数据和单调时钟，避免每秒重新发现 key 或因延迟形成追赶突发。
- 曲线只从存储层读取用户选择的最多 6 个序列和当前时间窗口；图表像素预算决定显示点数，不改变内存中的原始 1 Hz 历史。
- 关键选择与取舍见 DECISIONS 的 ADR-001 至 ADR-009。

## 当前只读实现证据

- Xcode targets：`ThermalPulse`、`ThermalPulseCore`、`ThermalPulseTests`。
- `SMCReadAdapter` 只定义 read bytes、read index 和 read key info 三类命令，不定义写命令。
- 普通测试共 24 项，其中 23 项通过，1 项实机测试按设计跳过。覆盖 key 编码、80 字节 ABI、解码、分类、动态采样白名单、单项失败隔离、停止语义、环形覆盖、增量统计、传感器选择、显示降采样和采样间隙。
- `ThermalPulseHardwareProbe` 是显式硬件测试 scheme。2026-08-28 在当前 Mac16,7 上读到 3337 个 key、2 个风扇，并验证两个风扇的实际 RPM 不超过各自实时读回的最大 RPM。
- 全量扫描取得 3293 个 key 的元数据，按白名单采样 315 个候选；44 个不可读项被隔离计数，没有伪装为零或终止整轮扫描。
- 第二个只读切片从初始候选中动态选择 312 个有效实际值或温度项，使用缓存元数据连续读取两轮，失败数均为 0。
- 第三个只读切片用 312 个序列加速模拟 3601 秒的 1 Hz 数据写入，并在每秒生成统计摘要；测试在 5.538 秒内完成，每个序列保持 3600 点上限，窗口查询只返回指定序列和截止时间后的样本。该证据验证数据路径与容量，不等于真实运行 1 小时。
- Debug App 连续运行约 1 分 54 秒，未见崩溃或标准错误输出；该次观测约为 222 MiB RSS、3.2% CPU，只是短时调试版冒烟，不是性能基准或 GUI 人工验收。
- 上述证据只覆盖普通权限只读路径和曲线逻辑，不覆盖中文传感器语义、真实长时间运行、人工界面验收、SMC 写入或 Turbo 安全恢复。

## 禁改项 / Forbidden Refactors

- 禁止把 SMC 写入移动到普通 App 进程。
- 禁止为方便测试而给 helper 增加通用 key、RPM 或时长参数。
- 禁止把 600 秒恢复责任交给 SwiftUI Timer、菜单栏生命周期或 App 退出回调。
- 禁止以单一 P 核温度替代多传感器监控，或把未知 key 猜成确定硬件部件。
- 禁止硬编码单风扇、风扇 0、某一机型的 RPM 上下限或旧 PRD 的 M5 key 表。
- 禁止在没有 ThermalPulse 租约时主动重置外部控制器的手动模式。
- 禁止用日志中的“写入成功”替代风扇模式和实际 RPM 的独立读回。
- 禁止让监控失败自动触发 Turbo。Turbo 永远是用户显式操作。
