# DECISIONS：ThermalPulse

> append-only。重大产品或技术决策按编号追加，不重写已发生的决策。

## ADR-001 · 从持续风扇控制转为监控优先 · 2026-08-28

- Problem: 原 MacFanCurve 方向试图用单一温度曲线长期接管苹果自动风扇控制，但用户真正需要的是理解热状态并在重负载时获得可控的临时散热。
- Constraint: 苹果自动策略同时考虑多个热源；当前又只有单机草稿数据，无法证明自定义曲线更安全或能保证 CPU 频率。
- Decision: 产品改为多传感器热状态监控工具，默认只读，不实现长期自定义风扇曲线。
- Alternatives（否决）: 沿用激进曲线；只做现有 PRD 的 UI 包装；完全放弃项目只使用系统高功率模式。
- Tradeoff: 放弃长期自动干预能力，换取更小的 root 写入面、更可信的跨机型边界和更明确的用户价值。

## ADR-002 · Turbo 使用固定 600 秒 fail-safe 租约 · 2026-08-28

- Problem: 用户需要一个简单按钮临时获得最大散热，但普通 App Timer 无法覆盖崩溃、强杀、XPC 断开、helper 重启和休眠。
- Constraint: Turbo 不能无限续时，任何失效都不能把风扇永久留在手动状态，也不能抢占其他风扇控制工具。
- Decision: helper 提供固定 `startTurbo()`、`stopTurbo()` 和状态查询，独立保存 600 秒租约；重复启动不续时，安全事件触发自动恢复。
- Alternatives（否决）: App 内 10 分钟 Timer；用户自定义时长；任意 RPM；helper 启动时无条件重置所有手动风扇。
- Tradeoff: helper 和租约恢复逻辑更复杂，但时间上限、所有权和故障恢复变成可验证的不变量。

## ADR-003 · 传感器语义采用证据分级，不追求首版全识别 · 2026-08-28

- Problem: Apple Silicon 不同机型的 SMC key、数据类型和语义存在差异，旧草稿又与当前实际开发机不一致。
- Constraint: 错误标签会让用户对温度和硬件状态形成错误判断，但隐藏全部未知项也会阻碍后续兼容研究。
- Decision: 默认视图只展示经过验证的传感器；未知项进入高级原始视图，并保留 key、类型、单位猜测和有效性，不赋予确定部件名称。
- Alternatives（否决）: 复制网络 key 表；按最高温度猜 P 核；只支持一组硬编码 key；完全隐藏原始数据。
- Tradeoff: 首版默认传感器数量可能较少，但每个名称更可信，也能安全积累多机型证据。

## ADR-004 · 原生本地 App 加现代 privileged helper · 2026-08-28

- Problem: 菜单栏监控需要低常驻开销，Turbo 又需要受控 root 写入和系统级生命周期管理。
- Constraint: 监控不能依赖管理员权限，helper 必须最小权限、可签名验证、可由系统管理，项目不需要网络后端。
- Decision: 使用原生 Swift、SwiftUI 与必要的 AppKit，SMC 访问隔离到 adapter；Turbo helper 采用 ServiceManagement 和私有 XPC，首选 `SMAppService` 路线。
- Alternatives（否决）: Electron 常驻应用；整个 App 以 root 运行；setuid 工具；把已弃用 helper 安装 API 作为新项目首选；增加本地 HTTP 服务。
- Tradeoff: Xcode 签名和 helper 调试门槛较高，但运行时负担、权限边界和 macOS 集成更合适。
