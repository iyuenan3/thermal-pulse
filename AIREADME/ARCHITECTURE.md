# ARCHITECTURE：ThermalPulse

## 组件 + 数据流

### 普通用户进程

1. `SMCReadAdapter`：已实现。只读打开 AppleSMC，读取 key info、数据类型和原始值；C bridging header 固定校验 80 字节 user-client ABI。
2. typed sensor model + `SensorClassifier`：已实现首版。动态识别风扇数量、实际值和最大值；温度 key 仅作为未确认候选，不赋予部件名称。
3. `SMCProbeService`：已实现启动或手动刷新时的一次性全量 key 枚举、元数据缓存、动态采样白名单和逐项失败隔离。每秒采样直接复用已验证元数据，不重复枚举。
4. `TelemetrySampler`：已实现。使用单调时钟按 1 Hz 读取有效的风扇实际转速与温度候选，同时采集 `ProcessInfo.thermalState`；错过节拍时丢弃旧节拍，不追赶突发读取。
5. `TimeSeriesStore`：已实现。每个传感器用固定容量 3600 的引用型内存环形缓冲保存有效样本，避免从 actor 字典取回值类型时复制整块固定数组。无效或不可用值只保留在最新帧，不污染统计历史。总数、最新值、最小值、最大值和总和随写入增量维护；只有淘汰当前极值时扫描单个环形缓冲重算极值。
6. `TelemetryPresentation`：已实现动态 `Tp` 温度族聚合、选择策略和显示降采样。聚合只接收有效、有限、摄氏度、`flt` 类型且 key 以 `Tp` 开头的候选，输出平均值、最高值、最高 key 和候选数量，不把候选数解释成核心数。默认选择运行时验证过的风扇实际 RPM；仍有名额时优先选择 `Tp` 族中数值最高的 key，否则回退到所有温度候选中的最高项，并在本次会话保持该 key 稳定。最多同时选择 6 项。显示层按时间桶保留端点与局部极值，并按超过 1.75 秒的间隙拆段。
7. SwiftUI 监控界面：已实现无侧栏单页结构。顶部依次展示 P 核温度主状态、动态风扇 RPM、系统 thermal state、采样摘要和趋势；“传感器与曲线”区域默认收起，展开后按证据分组展示已验证风扇、`Tp` 候选族和其他原始温度候选。菜单栏标题直接显示紧凑 P 核平均温度和所有风扇 RPM；弹出面板采用蓝色温度主状态、紧凑分组信息行和底部主按钮，提供逐风扇读数、重新枚举、退出和重开窗口入口。图表候选目录在每次枚举后缓存，不在每一行重做全目录筛选和排序。RPM 与摄氏度使用独立图表和纵轴，避免把不同单位画在同一数值尺度。
8. 本地性能标记：已实现。在窗口显示与隐藏、菜单栏重开请求、原始候选展开与收起、曲线选择、时间范围切换和重新枚举时写一条统一日志，持续采样每满 60 个有效样本再写一条状态快照。标记不包含设备标识和原始 SMC key。
9. `TurboCoordinator`：已实现 App 侧纯逻辑边界。只接受无参数启动、停止和状态查询，拒绝重复启动，校验 active 响应必须同时包含开始时间与未来截止时间，且租约长度不超过 600 秒；停止只有在返回无错误 inactive 时才显示苹果自动。主窗口与菜单栏共享 `TurboControlView`，倒计时由 `TimelineView` 展示，不承担安全计时。
10. `TurboXPCClient`：已实现固定 Mach service 的私有持久 transport。连接只调用 `startTurbo(reply:)`、`stopTurbo(reply:)` 或 `getTurboStatus(reply:)`，响应使用 `NSSecureCoding` payload 并检查协议版本。客户端只在自身代码签名严格有效且能取得 Team ID 时连接，同时要求 helper 满足 Apple 签名锚点、固定 helper identifier 和相同 Team ID；未签名构建直接返回 helper unavailable。连接在 App 生命周期内保持，进程退出、断连、失效、远端错误或请求超时都会使连接失效，helper 据此恢复其租约。启动、停止、状态查询的超时分别为 70 秒、12 秒和 3 秒。
11. `TurboHelperRegistrationCoordinator` + `SMAppServiceTurboHelperRegistrationClient`：已实现 LaunchDaemon 状态查询、显式注册与显式升级边界。App 启动和控件出现时只读查询状态，不自动注册；`notRegistered` 与首次查询常见的 `notFound` 都显示注册入口，只有用户确认后才调用 `register()`。旧 helper 返回 write-path-unavailable 时，独立升级确认会先失效旧 XPC，等待异步注销完成，再注册当前签名版本。待批准状态提供系统设置入口，只有 `enabled` 才继续查询 XPC 状态。

监控数据流：

`AppleSMC / ProcessInfo → SMCReadAdapter → SensorCatalog → TelemetrySampler → TimeSeriesStore → 选择与显示降采样 → 菜单栏与监控窗口`

### privileged helper

1. `CallerValidator`：已实现。helper 启动时先严格验证自身签名并取得 Team ID，再由 `NSXPCListener.setConnectionCodeSigningRequirement` 在 delegate 前拒绝不满足 Apple 签名锚点、固定 App identifier 和相同 Team ID 的连接。协议 payload 另带固定版本并拒绝不兼容响应。
2. `TurboHelperService`：已实现每条 XPC 连接独立的 owner ID。服务只暴露三个无业务参数方法；持有租约的连接中断或失效时通知安全控制器恢复，状态查询不会接管所有权。
3. `TurboLeaseFileStore`：已实现 root-owned 最小持久租约。首次写 SMC 前先保存开始时间、绝对截止时间和空接管列表；每个风扇在切手动前先把其动态索引与模式 key 写入租约，`Ftst` 解锁也先记录所有权。租约不保存设备标识、RPM 或用户数据，只有全部恢复读回确认后才删除。
4. `SMCFanWriteAdapter`：已实现并只编入 helper target。它动态读取 `FNum`，验证每个 `F{i}Ac`、`F{i}Mx`、`F{i}Tg` 与 `F{i}Md` 或 `F{i}md` 的实时类型，只允许模式值 0 或 1，目标写入直接复制本轮实时最大值的原始字节，不接受调用方 key、RPM 或时长。当前机器需要时可通过 `Ftst` 处理系统 thermal manager 占用，但必须先持久记录并在恢复时清除和读回。
5. `TurboSafetyController` 与 watchdog：已实现固定 600 秒 helper 租约、绝对截止时间、进程内单调截止时间、1 秒看门狗、模式与目标读回、实际 RPM 上升门禁、反向恢复重试、helper 启动旧租约恢复和唤醒恢复。任何非自动初始模式都按外部或未知控制拒绝，不抢控制权；恢复只有读回明确 automatic 才能完成。

Turbo 注册与数据流：

`显式注册确认 → SMAppService → 系统批准 → Turbo 按钮 → TurboCoordinator → 签名校验 XPC → TurboLeaseStore → FanWriteAdapter → AppleSMC → 模式和 RPM 读回 → UI`

## Turbo 安全状态机

- `inactive`：没有 ThermalPulse 租约，绝不写风扇。
- `activating`：确认风扇数量、模式、最大值和外部控制冲突，持久化 600 秒租约后才切手动；每个风扇写入前先把接管范围持久化，再写本轮最大目标，并读回模式、目标和实际 RPM 上升趋势。
- `active`：helper 同时持有绝对截止时间和本进程单调截止时间，并由 1 秒看门狗验证租约与实际状态。App 只展示剩余时间。
- `restoring`：先对所有已接管风扇写自动，再读回模式，成功后删除租约。
- `failed-safe-auto`：任一环节不可信时尽最大努力恢复自动，记录可诊断错误并禁止再次 Turbo，直到重新验证。

helper 启动或重启时先检查自己的持久租约：存在旧租约则恢复自动并清理；不存在租约时不改动风扇，避免破坏其他风扇控制工具的状态。

## 关键技术选型

- 原生 Swift macOS App，界面使用 SwiftUI 与必要的 AppKit 桥接，减少常驻菜单栏工具的运行时负担。
- 低层 SMC ABI 隔离在独立适配层，不让原始 key 和二进制布局扩散到 UI 与业务逻辑。
- privileged helper 采用 ServiceManagement 的现代注册方式和 XPC，不使用已弃用安装链路作为首选。
- ServiceManagement 注册绝不在 App 启动时自动触发。首次系统状态为 `notFound` 只表示系统尚未记录服务，仍允许经过确认的显式注册；待批准时引导用户打开系统设置，未获 `enabled` 前不连接 helper。
- ServiceManagement 升级必须等待异步注销完成后再注册当前签名版本。升级确认与 Turbo 启动是两个独立动作，不用同步注销后立即重注册，也不使用手工 launchd 命令替代系统管理流程。
- App bundle identifier 固定为 `io.github.iyuenan3.thermalpulse`，helper identifier 与 Mach service 固定为 `io.github.iyuenan3.thermalpulse.helper`。LaunchDaemon plist 放在 `Contents/Library/LaunchDaemons`，helper executable 放在 `Contents/Resources`，与 `BundleProgram` 相互一致。
- XPC 采用双向签名约束。双方动态读取自身有效签名的 Team ID，要求 peer 同时满足 Apple 签名锚点、固定 identifier 和相同 Team ID，不为未签名或 ad hoc 构建提供宽松回退。
- 首版数据只保存在内存，先验证采样稳定性、传感器语义和界面价值，再决定是否持久化或导出。
- 全量枚举只在启动或用户手动刷新时执行。稳定白名单采样使用缓存元数据和单调时钟，避免每秒重新发现 key 或因延迟形成追赶突发。
- 曲线只从存储层读取用户选择的最多 6 个序列和当前时间窗口；图表像素预算决定显示点数，不改变内存中的原始 1 Hz 历史。
- 性能归因使用低频 OSLog 事件与每分钟状态快照，不为此持久化传感器样本或提高采样频率。
- 关键选择与取舍见 DECISIONS 的 ADR-001 至 ADR-017。

## 当前实现证据

- Xcode targets：`ThermalPulse`、`ThermalPulseCore`、`ThermalPulseHelper`、`ThermalPulseTests`。
- `SMCReadAdapter` 只定义 read bytes、read index 和 read key info 三类命令，不定义写命令。
- 当前普通测试共 57 项，其中 55 项通过，2 项实机只读测试按设计跳过，0 项失败。除只读数据路径外，覆盖固定租约、租约先于写入、动态多风扇、外部和未知模式拒绝、部分激活回滚、实际 RPM 上升门禁、wall clock 回拨、到期、断连、唤醒、helper 重启、持久化失败、恢复失败重试和显式 helper 替换门禁。
- `ThermalPulseHardwareProbe` 是显式只读硬件测试 scheme。2026-08-29 在当前 Mac16,7 上再次读到 3337 个 key、2 个风扇、315 个采样候选和连续两批 312 路零失败采样；两个风扇的实时最大值均为 5777 RPM。
- 同次只读探测确认 `F0Md`、`F1Md` 与 `Ftst` 都是 1 字节 `ui8 ` 且当前值为 0，`F0Tg`、`F1Tg`、`F0Mx`、`F1Mx` 都是 4 字节 `flt `。旧式全局 `FS! ` 在当前机器不存在，读取返回控制器错误 0x84。该证据只用于确定受限适配器契约，全程没有写 SMC。
- 全量扫描取得 3293 个 key 的元数据，按白名单采样 315 个候选；44 个不可读项被隔离计数，没有伪装为零或终止整轮扫描。
- 第二个只读切片从初始候选中动态选择 312 个有效实际值或温度项，使用缓存元数据连续读取两轮，失败数均为 0。
- 第三个只读切片用 312 个序列加速模拟 3601 秒的 1 Hz 数据写入，并在每秒生成统计摘要；测试在 5.538 秒内完成，每个序列保持 3600 点上限，窗口查询只返回指定序列和截止时间后的样本。该证据验证数据路径与容量，不等于真实运行 1 小时。
- 2026-08-29，Debug App 连续运行 3605 秒，取得 66 个等间隔稳定样本，未提前退出且标准输出和错误日志为空。RSS 为 198640 至 255776 KiB，平均 239677.8 KiB，最终 244496 KiB；CPU 为 6.3% 至 65.9%，平均 36.2%。这是 Debug 构建的进程观测，不是 Release 性能结论。
- 该长时运行中叠加了 14 个逻辑 CPU 满载 600 秒，以及实际触碰 12 GiB 内存并保持 300 秒的压力。系统没有发生 swap，App 保持存活；独立硬件探测仍对 312 个动态采样项取得连续两轮零失败读回。
- 全程没有 SMC 写入。苹果自动控制下，两个风扇从压力前的 0 RPM 上升到 1352 RPM 和 1459 RPM，冷却后回到 0 RPM；两个风扇的实时最大值均为 5777 RPM。该结果只证明被动读数跟随系统变化，不证明 Turbo 控制能力。
- 同日 Release App 完成 300 秒短测，取得 10 个 `ps` 样本，未提前退出且日志为空。该组 `%CPU` 平均为 46.6%，范围为 37.5% 至 53.8%，但 macOS `ps` 的 `%CPU` 是包含启动阶段的衰减平均值，不能作为稳定区间占用。后续用 `top` 区间采样建立的可比优化前基线为 18.8%、20.1% 和 21.6%，均值约 20.2%。
- 性能剖析定位到两处可消除热点：值类型环形缓冲每次写入触发 3600 槽数组的写时复制，以及 312 行原始候选各自重复筛选和排序完整图表目录。改为引用型缓冲、枚举后缓存目录，并默认折叠高级原始候选后，Release 120 秒短测未提前退出且日志为空；同口径 `top` 区间样本为 3.6%、4.3% 和 4.1%，均值约 4.0%，相对优化前降低约 80%。`top` 物理内存约为 195 MiB，优化前约为 246 MiB。
- 312 个序列的加速一小时容量测试在优化前耗时 5.520 秒，优化后耗时 1.689 秒，约降低 69%，且容量与统计断言不变。最终普通测试为 24 项执行、1 项实机测试按设计跳过、0 项失败；显式 `ThermalPulseHardwareProbe` 另行实际执行 1 项并通过，读到 3337 个 key、2 个风扇和连续两批 312 路零失败采样。
- 2026-08-29，包含菜单栏重开入口和默认原始温度候选曲线的最终 Release App 连续运行 3605 秒，未提前退出，标准输出和错误日志为空。监督脚本取得 60 个相隔 60 秒且无缺口的 `top` 样本，并在结束后确认回收目标进程。该间隔连续性是外部监督证据，不等于逐秒读取日志。
- 该 Release 长测的 `top` CPU 均值为 11.5%，范围为 2.5% 至 19.3%；物理内存范围为 207 至 323 MiB，最终为 323 MiB；RSS 范围约为 142.2 至 253.2 MiB，最终约为 253.2 MiB。前 10 个样本 CPU 均值为 3.8%、物理内存均值为 213.3 MiB；第 11 个样本起出现性能台阶，后 50 个样本 CPU 均值为 13.0%、物理内存均值为 312.2 MiB。缺少对应用户操作时间戳，不能把台阶归因于某个具体界面动作。
- 长测后普通测试仍为 24 项、23 项通过、1 项实机测试按设计跳过；显式硬件探针另行执行 1 项并通过，继续读到 3337 个 key、2 个风扇，以及连续两批 312 路零失败采样。全程没有 SMC 写入。
- 新增性能标记后，普通测试继续通过。短暂启动 Debug App 后，macOS 统一日志实际读回 `monitor_window_appeared`、`refresh_started` 和 `refresh_completed` 三条事件；完成事件记录 3 条默认曲线，且未记录设备标识或原始 key。
- 带标记的 Release App 在无界面操作条件下运行 12 分钟，13 个 `top` 样本的 CPU 均值为 6.52%，范围为 4.9% 至 10.7%；内存均值为 211.62 MiB，范围为 206 至 215 MiB。13 条连续每分钟快照都记录 3 条曲线、5 分钟范围、原始候选收起、窗口可见和 nominal thermal state。这一无操作基线未复现旧长测台阶，但不能证明问题已消失。
- 2026-08-29，当前 Mac16,7 在普通权限只读探测中取得 102 个有效 `Tp` float 候选。基线平均为 33.8 °C、最高为 75.6 °C；35 秒 14 线程 CPU 负载期间平均升至 75.3 °C、最高升至 94.5 °C。相同探针同时继续读回 2 个风扇，且负载脚本按时自行退出。该结果支持将 `Tp` 作为当前机器 P 核响应温度族，不支持逐 key 核心命名。
- 新 Release 界面已完成代码构建和本机截图检查，无侧栏单页中的温度主状态、紧凑信息行、热状态提示和趋势区在实际窗口尺寸内可见。通过 LaunchServices 标准启动后，顶部状态项实际显示紧凑 P 核温度与双风扇转速，证明核心摘要直接可见。由于 bundle identifier 尚未冻结，自动化工具仍无法寻址菜单栏弹窗内控件；主窗口截图检查不替代用户对弹窗和完整交互的人工验收。
- App 侧 Turbo 状态机纯逻辑测试覆盖 helper 不可用、固定 600 秒有效租约、超时租约拒绝、外部控制器拒绝、重复启动不续时、停止成功和恢复失败不误报。
- helper/XPC 骨架已完成未签名 Debug 与 Release 构建及 bundle 布局检查。产物包含 `Contents/Resources/ThermalPulseHelper` 和 `Contents/Library/LaunchDaemons/io.github.iyuenan3.thermalpulse.helper.plist`，App Info.plist 读回固定 bundle identifier。helper 通过嵌入 `__TEXT,__info_plist` 固定裸 executable 的签名 identity；独立 ad hoc 构建读回 App 与 helper identifier 均与冻结值一致，整个 App 通过 deep strict 签名校验，但 ad hoc 没有 Team ID，按设计不能建立 XPC 信任。普通测试共 39 项，38 项通过、1 项硬件测试按设计跳过。本阶段未调用 `SMAppService.register()`，未注册或运行 helper，未请求管理员授权，也没有 SMC 写入。
- 2026-08-29，当前开发机使用免费 Personal Team 完成 Debug 签名构建。代码签名读回 App 与 helper 的固定 identifier 和相同非空 Team ID，双方均由同一 Apple Development 身份签名，整个 App bundle 通过 deep strict 验证。普通测试仍为 39 项，38 项通过、1 项硬件测试按设计跳过、0 项失败。
- 同日新增 `SMAppService` 状态查询、显式注册确认和待批准系统设置引导。该阶段的签名 Debug App 自动化可访问性读回实际显示“系统尚未登记 Turbo helper”和可寻址的“注册 Turbo helper”按钮；当时普通测试共 43 项，42 项通过、1 项硬件测试按设计跳过、0 项失败。
- 随后由用户显式点击注册并完成系统允许，`launchctl` 读回 LaunchDaemon 由 ServiceManagement 管理、root 运行且 XPC 活跃；App 实际收到当时安全 stub 的 write-path-unavailable 状态，证明注册、批准和双向签名 XPC 通路可达。这个已注册 runtime 仍是旧 stub，没有 SMC 写入能力。
- 当前工作区进一步实现受限 `SMCFanWriteAdapter`、持久租约、每连接所有权、1 秒 watchdog 与恢复状态机。最终 Personal Team Debug 构建中的 App 与 helper 均在沙箱外通过独立 strict 校验，并在用户授权下完成系统升级。`launchctl` 读回新 helper 由 ServiceManagement 管理、以 root 运行且 Mach endpoint 活跃；App 通过双向签名 XPC 取得无错误 inactive 状态。升级前后租约文件均不存在。
- 升级后显式 `ThermalPulseHardwareProbe` 共 57 项、57 项通过、0 项跳过、0 项失败，包含当前机器所有动态风扇模式与 `Ftst` 都为 0 的只读门禁。上述证据覆盖普通权限只读路径、曲线逻辑、进程存活、新 helper 的合格签名、系统升级、root 启动与 XPC 状态实连。它不覆盖真实 SMC 写入、手动模式读回、最大目标读回、实际 RPM 达标或各恢复场景的实机验收，Turbo 仍未通过。
- 2026-08-30 首次短时真实写入尝试没有进入 active。helper 返回 failed-safe-auto 与 readback mismatch，监控曲线在激活阶段观察到最高约 2234 RPM 的短时上升，但没有取得全部风扇的手动模式、最大目标和实际 RPM 同时满足门禁的证据。失败后租约文件已删除；独立只读复验确认 `F0Md=0`、`F1Md=0`、`Ftst=0`，`F0Ac=1350.73 RPM`、`F1Ac=1462.07 RPM`，两个目标已回到苹果自动值，root helper 继续运行。该证据确认本次失败保护恢复，不确认 Turbo active 或最大转速。

## 禁改项 / Forbidden Refactors

- 禁止把 SMC 写入移动到普通 App 进程。
- 禁止为方便测试而给 helper 增加通用 key、RPM 或时长参数。
- 禁止把 600 秒恢复责任交给 SwiftUI Timer、菜单栏生命周期或 App 退出回调。
- 禁止以单一 P 核温度替代多传感器监控，或把未知 key 猜成确定硬件部件。
- 禁止硬编码单风扇、风扇 0、某一机型的 RPM 上下限或旧 PRD 的 M5 key 表。
- 禁止在没有 ThermalPulse 租约时主动重置外部控制器的手动模式。
- 禁止用日志中的“写入成功”替代风扇模式和实际 RPM 的独立读回。
- 禁止让监控失败自动触发 Turbo。Turbo 永远是用户显式操作。
