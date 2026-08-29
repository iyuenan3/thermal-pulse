# MEMORY：ThermalPulse

> append-only。这里记录已经发生的事故、失败和踩坑，决策理由写入 DECISIONS。

当前为 pre-alpha。可复现失败按“现象、根因、结论/避免”记录，并附可验证证据边界。

## AppleSMC 参数结构在 Swift 中得到 76 字节 stride · 2026-08-28

- 现象：首个 ABI 单元测试发现 Swift 逐字段声明的参数结构 stride 为 76，不符合 AppleSMC user-client 的 80 字节调用边界。
- 根因：Swift 对 C ABI 尾部填充的布局不构成可靠承诺，逐字段宽度相加不能替代真实 C 结构布局验证。
- 结论/避免：结构迁到唯一 C bridging header，并用 `_Static_assert(sizeof(...) == 80)` 与 Swift 测试双重锁定。不要在 Swift 或其他文件复制近似结构。

## Apple Silicon `flt ` 按大端解码得到极小伪值 · 2026-08-28

- 现象：真实风扇 key 的类型为 `flt `，按大端 IEEE 754 解码后得到接近零的极小值，导致实际和最大 RPM 合理性测试失败。
- 根因：当前 Apple Silicon 的 `flt ` payload 使用小端字节序，而整数及 `sp` / `fp` 定点类型沿用大端规则。
- 结论/避免：按数据类型决定字节序，并为小端浮点增加固定向量单元测试；实机验收必须同时校验实际 RPM、最大 RPM 与二者关系，不能只看调用成功。

## 扫描完成时 SwiftUI `List` 触发 NSTableView 重入警告 · 2026-08-28

- 现象：首次 App 冒烟启动后，一次性扫描结果刷新动态 `List` 时出现 NSTableView delegate reentrant operation 警告，并提示未来系统可能升级为断言。
- 根因：macOS SwiftUI `List` 基于 NSTableView，扫描结果一次插入大量候选行时触发了表格委托重入路径。
- 结论/避免：监控读数改用 `ScrollView` 与 `LazyVStack`，再次启动并完成扫描后不再出现警告。实时高频数据视图不默认使用 `List`。

## Release 长测约第 10 分钟出现未归因性能台阶 · 2026-08-29

- 现象：最终 Release App 的前 10 个一分钟监督样本中，`top` CPU 均值为 3.8%、物理内存均值为 213.3 MiB；第 11 个样本起抬升，后 50 个样本 CPU 均值为 13.0%、物理内存均值为 312.2 MiB。进程继续运行至 3605 秒，日志为空，RSS 没有持续单调上升。
- 根因：未知。长测期间允许用户操作曲线窗口，但没有记录界面动作时间戳，因此不能确认台阶来自展开高级候选、切换时间范围、重开窗口、Swift Charts 分配或其他原因。
- 结论/避免：后续性能验收要同时记录窗口状态、选择集合、时间范围和动作时间点，再与区间 CPU、内存对齐。缺少关联证据时，分段报告数据，不把台阶归因于某个具体交互。

## Release 无操作 12 分钟基线未复现性能台阶 · 2026-08-29

- 现象：加入本地性能标记后，Release App 在窗口可见、3 条默认曲线、5 分钟范围、原始候选收起且无任何交互的条件下运行 12 分钟。13 个 `top` 样本的 CPU 均值为 6.52%，范围为 4.9% 至 10.7%；内存均值为 211.62 MiB，范围为 206 至 215 MiB。第 10 分钟 CPU 为 9.0%，第 11 分钟回落至 5.3%，没有同步内存跃升。
- 根因：仍未定。本次反证表明“Release 无操作运行到约第 10 分钟必然触发台阶”不成立，上一轮现象更可能与当时交互状态、旧构建的运行条件或外部负载有关，但暂时不能区分。
- 结论/避免：后续使用单变量阶段，分别只展开原始候选、只切换到 1 小时、只重开窗口和只改变曲线选择，每段保留事件时间与区间资源样本。无操作基线未复现不等于原问题已解决。

## Tp 候选数量不能解释为 P 核数量 · 2026-08-29

- 现象：当前 Mac16,7 枚举到 102 个有效 `Tp` float 温度候选，远大于物理 P 核数量；其中最高 key 还会随负载变化。
- 根因：`Tp` 是动态温度传感器族前缀，不是一个“每个 P 核恰好一个 key”的公开稳定表。AppleSMC 又没有公开逐 key 语义，单看命名和数量无法建立具体核心映射。
- 结论/避免：只对整族计算平均值、最高值和候选数量，并用短时负载验证响应；界面写“P 核温度候选族”，不得把 102 写成核心数，不得给单个 key 编造核心编号。跨机型仍需重新验证。

## SMAppService 首次查询的 notFound 不等于 bundle 配置丢失 · 2026-08-29

- 现象：签名 Debug App 的 LaunchDaemon plist 和 helper executable 都位于正确 bundle 路径，`SMAppService.status` 首次仍返回 `notFound`，界面因此误报“当前 App 包内没有找到 Turbo helper 配置”。
- 根因：`status` 描述系统已经记录的服务状态，不验证 bundle 内 plist 是否存在。Apple DTS 的最小示例在注册前同样得到 raw status 3，调用 `register()` 后成功；`notFound` 在首次注册前可表示系统尚不知道该服务。
- 结论/避免：`notRegistered` 与首次 `notFound` 都可进入显式注册流程，但仍必须由用户确认后调用 `register()`。判断 bundle 布局要独立检查产物，不能从首次 status 反推 plist 缺失。

## HardwareProbe scheme 被 Debug configuration 覆盖后静默跳过 · 2026-08-29

- 现象：命令选择了 `ThermalPulseHardwareProbe` scheme，却又显式传入 `-configuration Debug`，结果硬件集成测试被普通测试环境门禁跳过，看起来像探针运行成功但没有产生真实设备证据。
- 根因：scheme 的 HardwareProbe configuration 被命令行 configuration 覆盖，测试进程没有获得硬件探针开关。
- 结论/避免：运行只读实机探针时使用 scheme 自带 configuration，不额外传 `-configuration Debug`；必须从 xcresult 确认探针实际通过，而不是只看 xcodebuild 退出码。

## 当前 M4 Pro 没有旧式全局 FS 模式 key · 2026-08-29

- 现象：当前 Mac16,7 读取旧式 `FS! ` 返回控制器错误 0x84，但 `F0Md`、`F1Md` 和 `Ftst` 都能稳定读取为 1 字节 `ui8 `；两个 `F{i}Tg` 与 `F{i}Mx` 都是 4 字节 `flt `。
- 根因：风扇控制 key 与数据类型会随平台变化，旧 Intel 或其他机型实现不能直接套用到当前 Apple Silicon。
- 结论/避免：模式 key 必须按动态风扇索引解析 `F{i}Md` 或 `F{i}md`，先验证类型和值；目标写入复制实时 `F{i}Mx` 原始字节。`FS! `、风扇数量和 RPM 都不得硬编码，全程先用只读探针建立目标机证据。

## 沙箱内 codesign 可能制造证书不受信任假象 · 2026-08-29

- 现象：加入新 helper 写入源码后的 Personal Team Debug 构建由 Xcode 成功产出，但在受限沙箱内对 App 与 helper 执行 strict 验证都返回 `CSSMERR_TP_NOT_TRUSTED`；对同一产物在沙箱外重跑后，两者都通过并满足 designated requirement。最终源码重新签名构建后也得到相同的沙箱外通过结果。
- 根因：受限执行环境无法完整访问系统证书信任服务，codesign 把环境限制表现为证书链不受信任，并非产物签名损坏。
- 结论/避免：签名完整性仍需独立验证，但出现 `CSSMERR_TP_NOT_TRUSTED` 时先用完全相同的只读命令在沙箱外复现，再决定是否阻断。构建、strict、系统注册、root 启动、XPC 实连和真实 SMC 写入继续分开验收。

## SMAppService 同步注销后立即注册留下未注册状态 · 2026-08-29

- 现象：用户授权升级 helper 后，App 同步调用 `unregister()` 再立即调用 `register()`。旧 root helper 被系统移除，但 App 显示升级失败，`launchctl` 确认 system 域没有新服务，租约文件仍不存在。
- 根因：注销与系统完成服务移除之间存在完成时序。同步 API 返回后立即重注册触发竞态，不能把两次调用顺序等同于系统生命周期已经完成切换。
- 结论/避免：使用 `SMAppService` 的异步 `unregister()` 并等待完成后再注册，升级前先失效旧 XPC。失败后先只读刷新实际注册状态，再从 notRegistered 明确重试；不要用延时猜测、手工 launchd 命令或直接覆盖文件补救。

## 首次真实 Turbo 在读回门禁失败并自动回退 · 2026-08-30

- 现象：启动前专用只读门禁确认两台风扇均为 automatic 且 `Ftst=0`。用户确认短时 Turbo 后，监控曲线观察到最高约 2234 RPM 的短时上升，但 helper 返回 failed-safe-auto 与 readback mismatch，没有进入 active。失败后持久租约已删除；独立 HardwareProbe 读回 `F0Md=0`、`F1Md=0`、`Ftst=0`、`F0Ac=1350.73 RPM`、`F1Ac=1462.07 RPM`，目标值也已回到苹果自动控制值。
- 根因：尚未确定。当前有限错误只说明模式、最大目标或实际 RPM 上升门禁之一不一致，不能从曲线中的单个峰值判断两台风扇是否都满足条件。较早的一次全量枚举还短暂读到 `F0Md=3`、`F1Md=3` 与两个实际 RPM 为 0，而紧接着的专用点读门禁通过；该非原子快照可能相关，但不是已证实根因。
- 结论/避免：本次可以确认失败保护后的 automatic 恢复，不能确认 Turbo 成功。下一次真实写入前先增加逐风扇、逐阶段、无设备标识的有限诊断，区分模式、目标和实际 RPM 失败点；完成新签名 helper 升级后再次取得用户明确授权。失败后不自动重试，也不以曲线峰值替代全部模式、目标和实际 RPM 读回。
