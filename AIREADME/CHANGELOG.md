# CHANGELOG：ThermalPulse

> append-only，版本块倒序。这里只记录 release 或明确里程碑，原因指向 DECISIONS，未来方向写入 ROADMAP。

当前已有可执行的只读监控里程碑，尚无 release。

## Unreleased · read-only Release soak and monitoring UX milestone · 2026-08-29

### Added

- 菜单栏新增“打开监控窗口”，关闭主窗口后可重新创建并置于前台。

### Changed

- 默认曲线在已验证风扇之外，增加枚举快照中数值最高的一个有效原始温度候选。该候选在本次会话固定，只显示原始 key，不赋予部件名称，见 ADR-010。

### Validated

- 最终 Release App 连续运行 3605 秒，未提前退出且日志为空；60 个一分钟监督样本间隔无缺口，结束后目标进程已回收。
- 普通测试 24 项，23 项通过、1 项实机测试按设计跳过；显式只读硬件探针另行执行 1 项并通过，读到 3337 个 key、2 个风扇，以及连续两批 312 路零失败采样。

### Observed

- 长测 `top` CPU 均值为 11.5%，范围为 2.5% 至 19.3%；物理内存范围为 207 至 323 MiB，最终为 323 MiB；RSS 范围约为 142.2 至 253.2 MiB，最终约为 253.2 MiB。
- 前 10 个样本与后 50 个样本之间出现性能台阶，但没有对应界面操作时间戳，不能归因于具体动作。该问题已记录到 MEMORY，并进入 ROADMAP。

### Not included

- 本里程碑不包含用户对菜单栏重开、两类曲线和交互观感的人工确认，也不包含温度部件语义、SMC 写入、helper、Turbo、签名、安装或 release。

## Unreleased · read-only performance milestone · 2026-08-29

### Fixed

- 将 actor 字典中的固定容量环形缓冲改为引用型原地更新，消除每次采样写入触发的 3600 槽数组写时复制。
- 将图表候选目录改为枚举后一次筛选、排序和缓存，消除 312 行原始候选各自重复处理完整目录的开销。

### Changed

- 高级原始温度候选默认折叠，用户可显式展开；折叠不停止后台 1 Hz 采样。

### Validated

- Release 120 秒短测未提前退出且日志为空。同口径 `top` 区间 CPU 均值从优化前约 20.2% 降至优化后约 4.0%，约降低 80%；物理内存从约 246 MiB 降至约 195 MiB。
- 312 个序列的一小时容量测试从 5.520 秒降至 1.689 秒，约降低 69%，容量与统计断言不变。普通测试 24 项执行、1 项实机测试按设计跳过、0 项失败。
- 显式 `ThermalPulseHardwareProbe` 实际执行 1 项并通过，读到 3337 个 key、2 个风扇，以及连续两批 312 路零失败采样；全程没有 SMC 写入。

### Corrected

- 上一个里程碑记录的 Release `ps` 平均 46.6% 是包含启动阶段的衰减平均值，不能解释为稳定区间 CPU 占用。本次使用 `top` 区间采样建立了可比的优化前后基线。

### Not included

- 本里程碑不包含 Release 一小时持续运行、人工曲线验收、温度语义确认、SMC 写入、helper、Turbo、签名、安装或 release。

## Unreleased · read-only long-run validation milestone · 2026-08-29

### Validated

- Debug App 连续运行 3605 秒，未提前退出且日志为空；运行前后普通测试均为 24 项执行、23 项通过、1 项实机测试按设计跳过。
- 在真实运行窗口内叠加 14 核 CPU 满载 600 秒和 12 GiB 内存压力 300 秒。App 保持存活，系统没有发生 swap，312 个动态采样项继续取得连续两轮零失败读回。
- 全程保持只读。苹果自动控制下，两个风扇从 0 RPM 上升到 1352 RPM 和 1459 RPM，并在冷却后回到 0 RPM。

### Observed

- Debug 一小时稳定样本的 RSS 为 198640 至 255776 KiB，平均 239677.8 KiB；CPU 为 6.3% 至 65.9%，平均 36.2%。
- Release App 300 秒短测未提前退出且日志为空，但 10 个稳定样本的 CPU 平均为 46.6%，范围为 37.5% 至 53.8%；RSS 平均为 217038.4 KiB。进入 Turbo 前需要先完成性能剖析和 Release 长时验证。

### Not included

- 本里程碑不包含人工曲线验收、温度语义确认、性能问题修复、SMC 写入、helper、Turbo、签名、安装或 release。

## Unreleased · read-only charts milestone · 2026-08-28

### Added

- 新增最多 6 项传感器选择，以及 5 分钟、15 分钟和 1 小时 Swift Charts 历史曲线，见 ADR-009。
- 新增 RPM 与原始温度候选分图、保留端点和局部极值的显示降采样，以及采样间隙断线呈现。
- 新增选择策略、降采样、间隙、窗口查询和 312 序列一小时容量边界测试。

### Changed

- 环形缓冲改为增量维护总和与极值，摘要生成不再每秒遍历所有历史点。
- 曲线默认只选择运行时验证的风扇实际 RPM，原始温度候选必须手动加入。

### Not included

- 本里程碑不包含传感器中文语义确认、真实 1 小时运行与人工界面验收、SMC 写入、helper、Turbo、签名、安装或 release。

## Unreleased · read-only sampling milestone · 2026-08-28

### Added

- 新增一次枚举后的 1 Hz 动态白名单采样，并缓存 SMC 元数据，见 ADR-008。
- 新增每传感器 3600 点内存环形缓冲，以及最新值、最小值、最大值和平均值统计。
- 新增采样白名单、失败隔离、停止语义、环形覆盖和统计测试；实机探测增加两轮缓存元数据读回。

### Changed

- 菜单栏和监控窗口从一次性快照切换为持续只读读数，用户手动刷新会重新枚举并重建白名单。

### Not included

- 本里程碑不包含曲线绘制、传感器中文语义确认、长时间运行验收、SMC 写入、helper、Turbo、签名、安装或 release。

## Unreleased · 2026-08-28

### Added

- 新增原生 SwiftUI 菜单栏 App、监控窗口壳、`ThermalPulseCore` 静态库和 XCTest 目标。
- 新增普通权限只读 AppleSMC adapter、typed sensor model、证据分级分类器与全量扫描服务。
- 新增普通逻辑测试和显式 `ThermalPulseHardwareProbe` 实机只读验证 scheme。

### Fixed

- 用 C 结构和双重断言固定 80 字节 AppleSMC user-client ABI，见 ADR-005。
- 修正 Apple Silicon `flt ` 小端浮点解码，并取得当前 Mac16,7 两个风扇的实际与最大 RPM 关系证据。
- 将动态传感器列表改为 `ScrollView` 与 `LazyVStack`，消除扫描完成时的 NSTableView 重入警告。

### Not included

- 本里程碑不包含 1 秒持续采样、1 小时曲线、传感器中文语义确认、SMC 写入、helper、Turbo、签名、安装或 release。

### Changed

- 最低支持系统正式设为 macOS 26.0，所有工程 configuration 使用同一 deployment target，见 ADR-007。
