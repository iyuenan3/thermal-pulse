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

## ADR-005 · 用 C 结构锁定 AppleSMC user-client ABI · 2026-08-28

- Problem: 直接用 Swift 声明 AppleSMC 参数结构时，字段表面宽度正确仍可能因尾部对齐得到错误 stride，导致 user-client 调用边界不可靠。
- Constraint: 原始 ABI 必须集中、可编译期验证，且普通监控只能暴露读取能力。
- Decision: 用唯一的 C bridging header 定义参数结构，以 `_Static_assert` 锁定 80 字节布局；Swift adapter 只实现 read bytes、read index 和 read key info，并用单元测试再次验证 stride。
- Alternatives（否决）: 仅靠 Swift 默认布局；每个调用点复制结构；为了复用第三方代码同时引入写命令。
- Tradeoff: 工程增加一个 C 桥接边界，但布局错误能在编译或测试阶段暴露，写入能力也不会随低层模板被意外带入。

## ADR-006 · 普通测试与真实硬件探测分离 · 2026-08-28

- Problem: SMC 解码和分类需要快速、确定的逻辑测试，真实 AppleSMC 枚举又只能在受支持的 Mac 上取得证据。
- Constraint: 日常测试不能因机器差异隐式失败，也不能把模拟数据当成实机成功；硬件探测仍必须保持普通权限只读。
- Decision: 普通 `ThermalPulse` scheme 默认跳过集成测试，另设显式 `ThermalPulseHardwareProbe` scheme 编译启用真实枚举、风扇数量及实际和最大 RPM 关系验证。
- Alternatives（否决）: 每次单元测试都访问 AppleSMC；只保留手工终端脚本；用环境变量作为唯一启用机制。
- Tradeoff: 多维护一个 build configuration 和 scheme，但自动逻辑证据与当前机器实测证据边界清晰，也能防止误跑硬件路径。

## ADR-007 · 最低系统设为 macOS 26.0 · 2026-08-28

- Problem: 暂定 macOS 13 会要求额外维护旧系统兼容分支，也与当前 Xcode 26 测试工具链的实际基线不一致。
- Constraint: 用户只要求支持 macOS 26 及更高版本，首版无需承担旧系统兼容成本。
- Decision: App、核心库、普通测试和硬件探测统一使用 macOS 26.0 deployment target，不支持 macOS 25 及更早版本。
- Alternatives（否决）: 继续兼容 macOS 13；将 App 与测试目标设置成不同的最低版本；等发布前再决定。
- Tradeoff: 放弃旧系统用户，换取更小的兼容面、统一工具链和使用 macOS 26 API 的自由度。

## ADR-008 · 持续监控采用一次枚举与无追赶的 1 Hz 采样 · 2026-08-28

- Problem: 每秒全量枚举 3000 余个 SMC key 会制造不必要开销，普通 Timer 在阻塞后补触发又可能形成集中读取。
- Constraint: 采样对象必须来自当前机器实测，不能硬编码 key；监控失败不能写 SMC，也不能用无效值污染 1 小时历史。
- Decision: 启动或手动刷新时全量枚举一次，缓存元数据，并从当时有效的风扇实际转速和温度候选形成稳定白名单；之后用单调时钟按 1 Hz 读取，错过节拍不追赶，每个序列只保留最近 3600 个有效内存样本。
- Alternatives（否决）: 每秒全量枚举；固定机型 key 表；阻塞后立即补齐所有遗漏样本；把读取失败写成零；首版直接落盘。
- Tradeoff: 运行期间新增或恢复的 key 要到手动刷新后才进入白名单，但稳态开销、失败隔离和历史上限更容易验证。
