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

## ADR-009 · 曲线采用有限选择、单位分图与显示降采样 · 2026-08-28

- Problem: 当前机器的动态白名单有 312 项，若同时复制并绘制全部 1 小时原始样本，会增加内存带宽和图表布局开销，也会让未经确认的温度候选看起来具有确定语义。
- Constraint: 存储层仍需保留每序列最多 3600 个原始有效样本；曲线不能混淆 RPM 与摄氏度，不能填平读取失败造成的时间缺口，也不能自动提升原始温度候选的证据等级。
- Decision: 默认只选择运行时验证的风扇实际 RPM，用户可手动选择最多 6 项；RPM 与摄氏度分图；只查询所选窗口与序列，并按像素预算保留端点、局部极值和采样间隙后绘制。
- Alternatives（否决）: 默认绘制全部 312 项；把所有单位放在同一纵轴；只保留均匀抽样点；在存储时永久降采样；默认选择未确认温度候选。
- Tradeoff: 用户需要手动挑选温度候选，且显示层不是每个原始点逐点绘制，但图表可读性、证据边界和长期渲染成本更可控。

## ADR-010 · 默认曲线加入一个未确认温度候选 · 2026-08-29

- Problem: 只默认显示风扇 RPM 时，首次打开窗口没有温度曲线，不能直接满足热状态监控的核心观察需求。
- Constraint: 当前机器尚未取得具体温度 key 的部件语义证据；默认选择不能猜测 CPU、GPU 或核心名称，也不能让曲线在每秒最高值变化时跳换传感器。
- Decision: 保留所有运行时验证风扇为默认曲线；仍有选择名额时，从枚举快照里选取数值最高的一个有效原始温度候选，并在本次会话固定该 key。界面明确显示原始 key 和语义未确认。本决策只替代 ADR-009 的默认温度选择部分，其他选择上限、单位分图和降采样约束不变。
- Alternatives（否决）: 继续要求用户手动加入温度；按网络 key 表赋予部件名称；每秒跟随最高温度切换 key；默认绘制全部温度候选。
- Tradeoff: 用户首次打开即可看到温度趋势，但该曲线只是动态选出的原始参考，不代表已确认的 CPU 或 GPU 温度。

## ADR-011 · 用动态 Tp 传感器族提供 P 核温度摘要 · 2026-08-29

- Problem: 用户需要在菜单栏直接看到 P 核温度，但当前机器没有可安全硬编码的逐核心 key 表，只显示任意最高温度候选又不能回答这一需求。
- Constraint: 不得复制旧机型 key 表，不得把一个原始 key 猜成具体核心，也不得把 `Tp` 候选数量解释成 P 核数量。聚合无有效输入时必须显示未知。
- Evidence: Stats 的 M4 Pro 实机调查把 `Tp` 前缀归为 P 核逐点温度候选；swift-soc-metrics 也采用动态 `Tp` 前缀聚合而非逐机型硬编码表。当前 Mac16,7 实测取得 102 个有效 `Tp` float 候选，35 秒 14 线程负载期间平均值从 33.8 °C 上升到 75.3 °C，最高值从 75.6 °C 上升到 94.5 °C，证明该族对 P 核负载有显著响应，但不能证明每个 key 的具体部件映射。
- Decision: 从当前读数中动态筛选有效、有限、摄氏度、`flt` 类型且 key 以 `Tp` 开头的候选，展示其平均值、最高值和候选数量。菜单栏标题使用紧凑平均值与所有动态风扇 RPM；默认温度曲线优先选择该族中当前最高的 key，并在会话内保持稳定，其他规则继续遵守 ADR-010。
- Alternatives（否决）: 硬编码当前机器 102 个 key；把候选数量当成核心数量；只显示族内最高值并称为 P 核温度；沿用所有温度候选中的任意最高项作为菜单栏 P 核温度。
- Tradeoff: 平均值更稳定且能跟随负载，但它是一个动态传感器族摘要，不是 Apple 官方公开的 die temperature，也不提供逐核心身份保证。后续机型仍需分别验证响应。

## ADR-012 · 主窗口采用单页结构，菜单栏弹窗承担快速查看 · 2026-08-29

- Problem: 当前监控窗口只有两个低层级页面，侧栏持续占用曲线所需的横向空间；用户日常更常从菜单栏快速确认温度和风扇，再决定是否打开完整窗口。
- Constraint: 主窗口仍需容纳多单位曲线和高级原始候选；菜单栏弹窗必须保持只读，不复制参考软件的电量控制或设备信息，也不能暴露设备标识。
- Decision: 移除主窗口侧栏，按摘要、趋势、可展开“传感器与曲线”的顺序组成单页。菜单栏弹窗采用一个蓝色 P 核温度主状态、若干紧凑分组信息行和一个底部“打开监控窗口”主按钮；次要的刷新与退出放在头部控件中。
- Alternatives（否决）: 保留概览与传感器侧栏；把曲线塞进菜单栏弹窗；为高级传感器另开常驻窗口；照搬电量管理软件的功能或设备字段。
- Tradeoff: 查看原始候选需要多一次展开操作，但曲线获得更完整的窗口宽度，菜单栏快速查看也形成清晰的单一视觉路径。

## ADR-013 · Turbo 先交付可验证的 App 侧契约，再接入签名 helper · 2026-08-29

- Problem: Turbo 交互需要开始、倒计时、取消和错误反馈，但真实风扇控制依赖尚未冻结的 bundle identity、签名 requirement、Mach service 和系统批准；直接把 UI 接到临时 root 写入会绕过既定安全边界。
- Constraint: 当前不能编造签名身份或服务名，不能安装 helper，也不能让占位按钮表现得像已经能控制风扇；未来接入又必须保持固定 600 秒、无任意参数和失败不误报。
- Decision: 先实现无参数 `TurboClient`、App 侧 `TurboCoordinator`、共享 Turbo 控件和明确禁用的 `UnavailableTurboClient`。协调器验证 active 租约不超过 600 秒、重复启动不续时，stop 只有收到无错误 inactive 才显示苹果自动；UI 倒计时只展示 helper 状态。
- Alternatives（否决）: 等 helper 完成后一次性交付全部界面；在 App 进程临时写 SMC；使用模拟倒计时假装 Turbo 已运行；先随意填写 bundle identifier 和 Mach service 名称。
- Tradeoff: 用户现在能看到完整交互位置但按钮暂不可用，换取可独立测试的状态边界和不越过安装、签名、管理员授权范围的开发顺序。

## ADR-014 · 固定 GitHub 反向域身份并要求双向同 Team 签名 · 2026-08-29

- Problem: App 与 privileged helper 必须先有稳定身份才能实现真实 XPC transport，但用户只在自己的 Mac 上使用且没有付费 Apple Developer Program，项目也不能把 ad hoc 签名当成长期可信身份。
- Constraint: helper 必须只接受预期 App，App 也不能连接被替换的 helper；当前未知实际 Personal Team ID，不能写入仓库；本阶段不获准注册 helper、请求管理员权限或写 SMC。
- Decision: App bundle identifier 固定为 `io.github.iyuenan3.thermalpulse`，helper identifier 与 Mach service 固定为 `io.github.iyuenan3.thermalpulse.helper`。双方从自身严格有效的签名动态取得 Team ID，并要求 peer 同时满足 Apple 签名锚点、固定 identifier 和相同 Team ID。未签名或无 Team ID 时拒绝连接。先交付安全编码协议、App client、只返回 write-path-unavailable 的 helper executable 与现代 bundle 布局，不调用 `SMAppService.register()`。
- Alternatives（否决）: 继续留空身份；把随机或临时 bundle id 写进工程；仅按 bundle id 校验；为本地开发接受任意 ad hoc peer；在同一切片内直接注册 root helper 或引入 SMC 写入。
- Tradeoff: 未签名命令行构建可以验证编译、协议和 bundle 布局，但不能实际连接 helper；用户需要用免费的 Personal Team 完成本机签名原型，且短期配置有效期会增加维护频率。换取的是开发签名和未来 Developer ID 签名都能沿用同一组稳定身份与同 Team 安全边界。

## ADR-015 · helper 注册必须显式确认并与 Turbo 启动分离 · 2026-08-29

- Problem: Turbo 需要 root LaunchDaemon，但 App 启动时自动注册会把普通只读监控变成隐式系统变更；同时 `SMAppService.status` 首次可能返回语义容易误判的 `notFound`。
- Constraint: helper 注册、管理员批准和 SMC 写入是三个独立安全边界；普通监控不能依赖 helper；只有系统状态为 enabled 才能尝试 XPC。
- Decision: App 启动和 Turbo 控件出现时只读查询状态。`notRegistered` 与首次 `notFound` 都展示注册入口，用户点击后仍需经过确认弹窗才调用无参数 `register()`；`requiresApproval` 只引导系统设置，`enabled` 才同步 helper 状态。注册动作不自动启动 Turbo。
- Alternatives（否决）: App 启动时自动注册；点击 Turbo 时隐式注册并立即写 SMC；把 `notFound` 永久视为 bundle 损坏；未批准时反复尝试 XPC。
- Tradeoff: 首次使用多一步明确确认，且状态模型需要区分注册与运行，但普通监控保持无权限、无系统变更，用户也能判断 Turbo 卡在哪一层。

## ADR-016 · Turbo 写入采用动态逐风扇模式、持久所有权与双时钟租约 · 2026-08-29

- Problem: 旧 Intel 实现常用全局风扇模式 key，但当前 M4 Pro 的可读事实是每个风扇各有模式与目标；同时 App、XPC、helper 或 wall clock 任一失效都不能把风扇留在无主手动状态。
- Constraint: helper 不得接受任意 key、RPM 或时长；不得抢占外部手动控制；任何部分写入都必须可恢复；App 崩溃、断连、helper 重启、休眠唤醒和系统时间回拨都不能延长 600 秒安全边界。
- Evidence: 当前 Mac16,7 只读探测确认 `F0Md`、`F1Md` 和 `Ftst` 为 1 字节 `ui8 `，`F0Tg`、`F1Tg`、`F0Mx`、`F1Mx` 为 4 字节 `flt `，旧式 `FS! ` 不存在。[MacFanControl 的控制实现](https://github.com/raminsharifi/MacFanControl/blob/main/src/control.rs)也把 Apple Silicon 控制建模为逐风扇 `F{i}Md`、`F{i}Tg`，并在 M3、M4 路径处理 `Ftst`；该来源只作为实现交叉参考，最终支持仍以本机读回为准。
- Decision: 只在 helper target 中实现受限适配器。启动前要求所有动态风扇明确为 automatic，先持久化固定 600 秒租约，再在每个模式写入前记录该风扇；目标值复制本轮实时最大值原始字节。active 必须经过模式、目标和实际 RPM 趋势读回。helper 同时使用绝对截止时间和进程内单调截止时间；连接失效、唤醒或旧租约启动恢复都立即回 automatic，读回确认后才删除租约。
- Alternatives（否决）: 使用全局 `FS! `；硬编码双风扇或当前 5777 RPM；在 App 中保存唯一截止时间；先写后记租约；只验证目标写入不验证实际 RPM；把未知模式当作 automatic；helper 重启后继续剩余租约。
- Tradeoff: helper 的状态机、持久化和故障测试明显更复杂，Turbo 启动最长需要等待实际 RPM 趋势确认；换取的是写入面固定、部分失败可恢复、时钟回拨不续时，以及每个 active 或 inactive 结论都有明确读回条件。

## ADR-017 · helper 升级等待异步注销完成并与 Turbo 启动分离 · 2026-08-29

- Problem: 已注册安全 stub 需要替换为当前签名 helper，但同步调用 `unregister()` 后立即 `register()` 的首次实机尝试留下 notRegistered 状态，新服务没有登记。
- Constraint: 升级不能隐式启动 Turbo、不能写 SMC、不能手工篡改 launchd 状态，也不能在旧 XPC 仍存活时误认新 helper 已接管。
- Evidence: 首次同步替换后，旧 root helper 从 system launchd 域消失且租约文件不存在，App 回读升级失败。切换为等待 `SMAppService` 异步注销完成后，当前签名版本成功注册；系统读回新 root helper、活跃 Mach endpoint，App 经 XPC 取得无错误 inactive 状态，升级后全部只读硬件测试通过。
- Decision: helper 更新必须由用户独立确认。App 先把 Turbo 状态设为不可用并失效旧 XPC，再等待异步 `unregister()` 完成，最后注册当前签名版本并重新查询 XPC。注册或升级成功都不调用 `startTurbo()`。
- Alternatives（否决）: 同步注销后立即注册；直接覆盖 helper executable；手工 `launchctl bootout` 与 `bootstrap`；把升级并入首次 Turbo 点击；旧服务仍运行时直接宣布更新成功。
- Tradeoff: 升级路径需要异步状态和失败恢复界面，首次竞态还会暂时留下未注册状态；换取的是 ServiceManagement 完整拥有生命周期，升级与 SMC 写入授权保持严格分离。
