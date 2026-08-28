# CHANGELOG：ThermalPulse

> append-only，版本块倒序。这里只记录 release 或明确里程碑，原因指向 DECISIONS，未来方向写入 ROADMAP。

当前已有可执行的只读监控里程碑，尚无 release。

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
