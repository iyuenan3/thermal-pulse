# MEMORY：ThermalPulse

> append-only。这里记录已经发生的事故、失败和踩坑，决策理由写入 DECISIONS。

当前为 pre-code，尚无运行时事故或实现踩坑。首次出现可复现失败后，按“现象、根因、结论/避免”记录，并附可验证证据边界。

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
