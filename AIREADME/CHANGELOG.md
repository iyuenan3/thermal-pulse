# CHANGELOG：ThermalPulse

> append-only，版本块倒序。这里只记录 release 或明确里程碑，原因指向 DECISIONS，未来方向写入 ROADMAP。

当前为 pre-code，尚无 release 或可执行里程碑。创建首个可运行监控构建后再增加版本块。

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
