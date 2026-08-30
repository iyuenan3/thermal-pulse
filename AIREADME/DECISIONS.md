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

## ADR-018 · 产品收敛为菜单栏单面板 · 2026-08-30

- Problem: 独立监控窗口、侧栏、高级原始候选和多时间范围让一个个人温度小工具变得过重，用户的主要动作始终是点击菜单栏快速查看温度并偶尔启动 Turbo。
- Constraint: 菜单栏标题仍需显示 P 核温度与全部风扇 RPM；弹出面板必须容纳四类温度、趋势、系统热状态、逐风扇 RPM、Turbo 倒计时和中途停止，同时保持普通监控无 root、无网络。
- Evidence: 当前 Mac16,7 只读探测确认 CPU `Tp` 族、SSD `TH0x` 与电池 `TB1T`、`TB2T` 可用，常见 M4 内存附近 key 与全部 `Tm` 候选不可用。
- Decision: App 只创建 `MenuBarExtra`，不再创建独立监控窗口。面板固定展示 CPU P 核候选族、内存附近、SSD、电池、一张 5 分钟温度曲线、系统热状态、逐风扇 RPM 和 Turbo。缺失部件显示不可用，不提供高级原始数据、曲线范围或传感器选择入口。
- Alternatives（否决）: 保留完整窗口作为高级模式；将四类温度拆成多个页面；增加本地导出和告警；用 SoC 温度替代缺失的内存附近温度。
- Tradeoff: 用户失去原始 key 浏览和 1 小时可视化入口，但核心日常路径更直接，采样层仍保留 1 小时内存历史，后续确有需要再恢复展示能力。

## ADR-019 · Apple system 模式视为安全恢复状态，启动写入必须立即读回 · 2026-08-30

- Problem: 第二次短测中，风扇短时转动后被系统接管，`F0Md` 读回 automatic，恢复随后持续失败并留下 root lease。独立复验显示两台风扇为 mode 3、`Ftst=0`、目标与实际 RPM 为 0，硬件安全但 helper 把系统已经接管误判为恢复失败。
- Constraint: mode 1 才是 ThermalPulse 手动控制；未知值仍必须失败。恢复不得因为冗余 automatic 或 `Ftst=0` 写入被拒绝而卡住，但也不能只凭模式忽略实际 RPM 和 lease 删除。进入 active 前仍必须读回模式、目标和实际 RPM 上升。
- Evidence: [macos-smc-fan 的 M4 研究](https://github.com/agoodkind/macos-smc-fan/blob/main/docs/research.md)记录 mode 0 为 auto、mode 1 为 manual、mode 3 为 system，并指出 `Ftst=0` 后系统可回到 mode 3 和 0 RPM。[MacFanControl 的控制循环](https://github.com/raminsharifi/MacFanControl/blob/main/src/control.rs)在 `Ftst` 解锁后重试手动模式并持续核对系统是否重新接管。上述来源只作交叉参考，当前机器读回优先。
- Decision: mode 0 与 mode 3 都归类为 Apple 管理，mode 1 为手动，其他值拒绝。每次手动模式写入后立即读回 mode 1，`Ftst=1` 也必须读回后才继续。恢复时先读模式，已经为 0 或 3 就跳过冗余 automatic 写入；`Ftst` 已为 0 时跳过冗余清除。最终仍要求所有模式为 Apple 管理、实际 RPM 有效、`Ftst=0` 且 lease 删除成功。恢复失败日志必须标记具体阶段。
- Alternatives（否决）: 只接受 mode 0 才算恢复；无条件重复写 mode 0 与 `Ftst=0`；进入 active 后无限与系统争抢；看到风扇声音停止就直接删除 lease。
- Tradeoff: 状态模型多一个明确 system 分支，协议需要升级并重新签名 helper；换取的是不会把苹果已接管误判为危险手动状态，也不会降低最终读回门禁。

## ADR-020 · 首版温度界面只保留 P 核、E 核与电池 · 2026-08-30

- Problem: 用户希望它保持为简单的菜单栏温度工具，内存温度在当前机器没有可验证 key，SSD 也不是当前观察重点；继续保留四类卡片会用不可用或次要信息挤占核心状态。
- Constraint: 传感器命名必须基于当前机器实测证据，不能把候选数解释为物理核心数，也不能把一个原始 key 映射为具体核心编号。底层 1 Hz 动态白名单和 1 小时内存历史可以保留，但首版界面不应暴露高级原始数据。
- Evidence: 当前 Mac16,7 显式只读探测取得 102 个有效 `Tp` float 候选、10 个有效 `Te` float 候选，以及 `TB1T`、`TB2T` 两枚有效电池温度。P 核族、E 核族和电池族都能形成有限、有效的聚合；常见内存 key 与全部 `Tm` 候选仍不可用。
- Decision: ADR-018 的四类温度展示由本决策替代。菜单栏面板和固定 5 分钟曲线只保留 P 核 `Tp*`、E 核 `Te*` 与电池 `TB1T/TB2T` 三类。每类展示族平均温度，辅助信息可以显示最高值和候选数，但候选数不得称为核心数。内存和 SSD 不进入首版界面。
- Alternatives（否决）: 保留不可用的内存行；继续显示 SSD 以凑齐四类；按温度响应猜测其他 key；为每个 P 核或 E 核候选编造编号。
- Tradeoff: 用户看不到当前可读的 SSD 温度和原始传感器目录，但面板更符合实际使用重点，语义边界也更清楚。

## ADR-021 · Turbo active 期间在自有租约内协调系统重写 · 2026-08-30

- Problem: 第二次短测中，模式和目标被系统在数秒内改回，风扇只短时转动；一次性写入和激活读回不足以维持固定 10 分钟 Turbo。
- Constraint: Turbo 仍只能写动态枚举风扇的 mode 和实时最大目标，单次上限固定 600 秒，不得接受任意 RPM、时长或 key。启动前发现外部手动模式或已被占用的 `Ftst` 必须拒绝，任何状态无法重新确认都必须恢复苹果控制。
- Evidence: [MacFanControl](https://github.com/raminsharifi/MacFanControl)针对 M3、M4 的实现会在 mode 1 被拒绝时先持有 `Ftst`，等待后重试，并在控制期间核对模式；[Stats 的 Apple Silicon 传感器读取实现](https://github.com/exelban/stats/blob/master/Modules/Sensors/readers.swift)和其他开源控制器也显示新机型风扇状态会被系统热管理进程改写。上述项目只作实现交叉参考，当前 Mac16,7 的真实读回仍是验收依据。
- Decision: 对当前 mode 3 且 `Ftst=0` 的机器，先把 `Ftst` 所有权写入固定租约，再设置并读回 `Ftst=1`，等待系统稳定后逐风扇写 mode 1 和实时最大目标。进入 active 后，helper 每 300 毫秒核对 `Ftst`、动态风扇集合、mode、实时 `F{i}Mx`、目标和实际 RPM；系统重写 mode 或目标时只在 ThermalPulse 自己的有效租约内执行有限次数重写。`Ftst` 丢失、风扇集合变化、读回失败或截止时间到期都立即进入恢复。App 每秒查询只用于显示倒计时。
- Alternatives（否决）: 写一次后把系统接管当作 Turbo 成功；无限制高频争抢；绕过 `Ftst`；让 App Timer 负责维持控制；系统改写后继续显示 active 但不读实际 RPM。
- Tradeoff: Turbo active 的 root 读写频率和状态机复杂度提高，但仅持续在用户显式持有的最长 600 秒租约内。真实风扇持续最大目标、实际 RPM 和停止恢复仍必须在当前机器上独立读回后才能验收通过。

## ADR-022 · P 核与 E 核显示当前热点而非全族平均 · 2026-08-30

- Problem: 菜单栏把 102 个 `Tp*` 候选直接求平均后，P 核温度在空闲和核心休眠期间出现 20 °C 与 40 °C 附近的不自然跳变，无法作为简单热观察指标。
- Constraint: Apple 没有公开当前 Mac16,7 的逐 key 语义；不能把候选数当成核心数，也不能为了平滑而硬编码其他 M4 Pro 机器的 key 表。
- Evidence: 当前 Mac16,7 的 12 秒只读追踪中，102 项全族平均从 46.2 °C 降至 42.4 °C，最高值从 75.0 °C 随构建余热自然降至约 50 °C。公开 Stats 表列出的 8 个 M4 Pro P 核 key 在本机全部固定为 40.0 °C，而多个其他 `Tp*` 热区会随负载与冷却变化，证明不能把另一台 M4 Pro 的逐 key 表直接搬到 Mac16,7。
- Decision: 继续动态使用当前机器实际枚举的 `Tp*` 与 `Te*` float 族，核心候选只接受 10 至 120 °C。P 核与 E 核向用户展示族内当前最高候选，称为当前热点；电池继续显示 `TB1T` 与 `TB2T` 平均。曲线仍使用会话开始时选定的稳定代表 key，不每秒切换 key。
- Alternatives（否决）: 继续显示 102 项平均；硬编码 Mac16,8 的 M4 Pro key；用指数平滑掩盖语义错误；把一个当前最热 key 命名为具体物理核心。
- Tradeoff: 热点比全族平均更敏感，短时负载变化会更明显，但不会被大量空闲或占位热区稀释，也更符合用户判断是否需要散热的目标。

## ADR-023 · Turbo 启动以按钮点击作为唯一确认 · 2026-08-30

- Problem: helper 已经注册并可用时，再显示一次 Turbo 确认卡片增加了一次无价值点击，菜单栏小工具的主要操作因此显得拖沓。
- Constraint: Turbo 仍不得自动启动，注册、升级与实际写入必须保持独立授权，固定 600 秒和停止入口不变。
- Decision: 用户单击“启动 10 分钟 Turbo”时直接调用无参数 `startTurbo()`，这次明确点击本身就是写入确认。helper 注册和升级继续保留各自的独立确认，App 启动、状态刷新和监控异常都不能触发 Turbo。
- Alternatives（否决）: 保留启动二次确认；把首次注册后自动启动；允许键盘或监控阈值自动触发。
- Tradeoff: 误触保护减少一层，但按钮名称、10 分钟时长和运行中停止入口始终可见，交互更符合简单菜单栏工具。

## ADR-024 · `Ftst` 必须等待稳定读回并在恢复时重申清除 · 2026-08-30

- Problem: 协议 v3 helper 写 `Ftst=1` 后立即读回旧值 0，误判 mode readback mismatch；恢复又在异步写入真正生效前读到旧值 0 并删除租约，随后硬件才变为 `Ftst=1`，留下无租约占用。
- Constraint: 租约必须先于任何写入持久化；不能把紧邻异步写入的旧读数当成最终状态；也不能在无法确认 `Ftst=0` 时删除租约或宣布恢复完成。
- Evidence: helper 日志在 `activation_started` 后约 2 秒记录 `restoration_completed issue=modeReadbackMismatch`，没有记录 `thermal_manager_unlock_claimed`；随后独立只读读回两台风扇 mode 0、`Ftst=1`，而 root 租约文件不存在。源码顺序正是写 1 后立即读、恢复读 0 后跳过清除并删除租约。
- Decision: 协议升级到 v4。写 `Ftst=1` 后先等待 3 秒稳定，再检查所有权和读回 1。只要租约记录 ThermalPulse 接管过 `Ftst`，恢复就始终写 0，等待同样的稳定窗口并读回 0，之后才删除租约。自动化测试记录写入、等待与读回事件顺序。
- Alternatives（否决）: 继续立即读回并增加重试次数；恢复看到 0 就跳过写入；只延长 App 超时；无租约时自动清除任何 `Ftst=1`。
- Tradeoff: 启动和停止各增加约 3 秒，换取不再把异步旧值误当最终状态。对无租约 `Ftst=1` 仍拒绝自动抢占，当前遗留状态需要独立、明确授权的恢复操作。

## ADR-025 · helper 替换要求稳定未注册观察 · 2026-08-30

- Problem: 升级流程已经等待 `SMAppService.unregister()` 的异步完成，但实机仍在约 5 毫秒后调用 `register()` 时返回 ServiceManagement 错误 1。旧 helper 已被移除，新 helper 没有登记，界面此前的不兼容提示来自注销前的 v3 XPC 回复。
- Constraint: helper 升级必须继续由用户独立确认，失败后不得自动循环注册，不得使用手工 `launchctl` 绕过系统，也不得在升级过程中启动 Turbo 或写 SMC。
- Evidence: 统一日志显示旧 v3 helper 先连接并返回不兼容状态；用户确认升级后 `unregister()` 成功，紧接着的单次 `register()` 失败。独立 `launchctl` 读回确认当前 system 域没有该 helper，helper 进程也已退出。重启后的只读硬件探测此前已确认两台风扇为 mode 3、`Ftst=0` 且 root lease 不存在。
- Decision: 在异步注销完成后，以 100 毫秒间隔观察 `SMAppService.status`，要求连续 10 次为 `notRegistered` 或 `notFound`，最多等待 8 秒。只有状态稳定才调用一次 `register()`；超时或注册失败都返回升级失败并记录不含设备标识的错误域、错误码和状态，不自动重试。
- Alternatives（否决）: 只依赖异步回调完成；加入一次固定 sleep 后盲目注册；失败后循环调用 `register()`；要求用户手工操作 launchd；把注销成功直接当成升级成功。
- Tradeoff: 正常升级至少增加约 0.9 秒观察时间，最坏等待 8 秒后安全失败。换取的是不再把瞬时未注册状态当作系统生命周期已经稳定，也保留一次用户确认只对应一次注册尝试的边界。

## ADR-026 · 最大目标精确读回，实际 RPM 使用独立 5% 可信容差 · 2026-08-30

- Problem: 首次成功进入 active 的独立验收中，目标原始字节精确等于动态 5777 RPM 最大值，但实际反馈最高达到 5855 RPM。旧测试把实际反馈不得超过标称最大值当成绝对条件，因此在控制链路正常、风扇已接近全速时仍判失败；同一界面的逐风扇行又因硬编码继续显示“苹果自动控制”。
- Constraint: 不得放宽最大目标，helper 仍只能复制实时 `F{i}Mx` 原始字节；实际 RPM 是控制后的独立传感器反馈，必须允许有限控制或量化超调，同时拒绝非有限、负值或明显不可信的异常读数。界面只有在无错误 inactive 时才能宣称苹果自动。
- Evidence: 当前 Mac16,7 的 v4 短测读回两台风扇 mode 1、目标均为 5777 RPM，实际样本分别为 5701、5855、5811 RPM 和 5776、5775、5778 RPM。最高超调约 1.35%；主动停止后两台风扇 mode 3、`Ftst=0`、lease 删除，helper 无错误恢复。
- Decision: 目标读回继续要求与本轮动态最大值原始字节精确相等。实际 RPM 的统一可信范围设为 0 至动态最大值 105%，启动上升门禁、active watchdog 和 HardwareProbe 共用同一策略；超过上限或非有限值立即恢复。逐风扇文案由可信 `TurboStatus` 映射，active 显示“Turbo 全速控制”，不可信状态显示“控制状态待确认”。该安全语义升级到协议 v5，强制新 App 拒绝旧 v4 helper。
- Alternatives（否决）: 继续要求实际 RPM 永不高于标称最大值；完全取消实际 RPM 上限；硬编码当前机器的 5777 RPM 或固定加 100 RPM；只改测试而不让 watchdog 共用规则；active 期间继续显示苹果自动。
- Tradeoff: 5% 是基于当前机器 1.35% 实测留出的保守余量，不是 Apple 公布规格，其他机型仍需实机验证。协议升级要求用户再次显式替换 helper，但避免新 App 与旧安全语义混用。

## ADR-027 · 核心温度曲线在展示边界过滤哨兵值 · 2026-08-30

- Problem: P 核卡片已经按 10 至 120 °C 过滤动态候选并显示当前热点，但曲线仍读取会话开始时选定的单个稳定 `Tp` 代表 key。该 key 在核心空闲时周期性返回 0，图表把它画成 P 核温度瞬间跌到 0 °C。
- Constraint: 0 °C 不是当前运行中 Mac 的可信核心温度，不能作为真实数据展示；同时不得修改原始 1 Hz 内存历史、改成每秒切换 key 或用平滑动画掩盖缺失值。
- Evidence: 用户截图显示 P 核曲线反复垂直跌到 0，而同一时段 E 核与电池保持合理温度。源码确认当前卡片过滤 10 至 120 °C，但 `TimeSeriesStore` 会保存有效解码的 0，曲线此前直接使用该代表 key 的原始历史。
- Decision: P 核和 E 核代表序列在展示边界复用 10 至 120 °C 的合理范围，省略 0 和其他越界点。省略后继续按 1.75 秒最大连续间隔拆段，因此单个 0 哨兵形成可见缺口，不跨缺口连线。电池逻辑、采样、原始历史和 Turbo 均不变。
- Alternatives（否决）: 把 0 替换为上一个值；跨缺口直接连线；对整条曲线做平滑；每秒改选当前最热 key；从存储层删除所有低温候选。
- Tradeoff: 曲线在哨兵出现时会有短暂断线，但断线诚实表达该秒缺少可信读数，也保持稳定代表 key 的可解释性。

## ADR-028 · 状态栏采用双行摘要，面板一次展开全部信息 · 2026-08-30

- Problem: 单行状态栏把 P 核温度与多个风扇 RPM 横向拼接，占用宽度且缺少电池温度；弹出面板的固定高度和滚动容器又让一个信息量有限的小工具出现不必要的滚动条。
- Constraint: 状态栏仍需持续可读，风扇数量必须动态枚举；面板必须保留 P 核、E 核、电池、温度曲线、系统热状态、逐风扇 RPM 和 Turbo，不能通过删除核心信息来消除滚动。
- Decision: 状态栏改为两个并排的小字号双行分组，左侧上下显示 P 核热点和电池平均温度，右侧按动态风扇顺序逐行显示实际 RPM。弹出面板移除 `ScrollView` 和固定高度，通过缩短曲线、卡片内边距与区块间距，让正常状态的全部信息一次展开可见。
- Alternatives（否决）: 继续单行横向摘要；只显示一个风扇；硬编码两台风扇；保留滚动条；删除 E 核、系统热状态或 Turbo 来换取高度。
- Tradeoff: 状态栏字号更小，紧凑曲线的垂直精度略低，但用户无需横向扫描长文本或滚动弹窗，核心数据仍完整保留。

## ADR-029 · 2×2 状态摘要使用单个多行文本 · 2026-08-30

- Problem: ADR-028 使用嵌套 `HStack`、两个 `VStack` 和多个 `Text` 组成 2×2 状态项，实际菜单栏只显示第一个 P 核文本，电池与两台风扇全部消失。
- Constraint: 用户需要左上 P 核、左下电池、右上风扇 1、右下风扇 2 的稳定布局；仍需保留小字号、动态风扇枚举和 `MenuBarExtra` 单面板结构，不为一个状态标签改造整套 AppKit 状态项与弹窗生命周期。
- Decision: 用单个等宽 `Text(verbatim:)` 承载两行字符串。第一行拼接 P 核与偶数序号动态风扇，第二行拼接电池与奇数序号动态风扇；当前双风扇机器自然形成目标 2×2 布局。辅助功能描述继续提供全部温度和风扇值。
- Alternatives（否决）: 继续调整嵌套 SwiftUI 栈的 frame；只显示 P 核与一个风扇；硬编码风扇 0 和风扇 1；立即用 `NSStatusItem` 与 `NSPopover` 重写菜单栏宿主。
- Tradeoff: 单个文本不支持两列分别着色或画分隔线，但它符合系统状态项的实际渲染约束，布局更稳定，实现也保持简单。

## ADR-030 · 状态项省略重复标签并固定为 6 pt · 2026-08-30

- Problem: 单个两行文本恢复了四项信息，但 8 pt 字号加上 `F1/F2` 标签仍让状态项过宽，在实际菜单栏中放不下。
- Constraint: 左上 P 核、左下电池、右上风扇 1、右下风扇 2 的位置关系必须保留；完整风扇名称和单位已经在展开面板中可见，状态项只需要承担常驻快速读数。
- Decision: 状态项字号固定为 6 pt 等宽半粗体，温度压缩为 `P40°` 与 `B30°`，右侧只显示对应位置的 RPM 数值。辅助功能描述和展开面板继续保留完整温度、风扇编号与单位。
- Alternatives（否决）: 保留 8 pt 并让系统截断；只显示一个风扇；改回单行；继续缩小弹出面板内容；用滚动或轮播状态项隐藏部分读数。
- Tradeoff: 状态项需要用户理解 `B` 代表电池、右列代表风扇，但宽度和高度显著缩短，完整语义仍可通过展开面板和辅助功能取得。

## ADR-031 · 状态摘要预渲染为固定尺寸模板图片 · 2026-08-30

- Problem: 单个多行 `Text` 已设置 6 pt 字号和负行距，但真实菜单栏仍以接近系统默认字号显示，顶部被状态栏高度裁掉，四项数据无法完整看见。源码修饰、编译和签名均通过，实际宿主行为仍不符合预期。
- Constraint: 必须直接控制两行内容的像素边界与状态项占位，同时保留动态更新、浅色和深色菜单栏适配、辅助功能文本及现有 `MenuBarExtra` 弹出面板。
- Decision: 主线程使用 AppKit 把四个动态值绘制成固定 18 pt 高的模板 `NSImage`，字形固定为 7.5 pt 等宽半粗体，两行 y 坐标为 0 与 9 pt，两列分别预留 `P100°` 与四位 RPM 宽度。`MenuBarExtra` 只接收这一张模板图片，系统只负责着色，不再参与字体和换行布局。
- Alternatives（否决）: 继续降低 SwiftUI `.font`；继续使用负行距；进一步删除读数；让状态项继续裁切；立即用完整 `NSStatusItem` 和 `NSPopover` 重写宿主。
- Tradeoff: 每次摘要更新会在主线程生成一张很小的内存图片，但尺寸固定、开销有限，换取状态项布局不再受 SwiftUI 文本宿主重排影响。

## ADR-032 · 常驻摘要优先显示 P 核与 E 核热点 · 2026-08-30

- Problem: 固定图片已让四项摘要完整显示，但 7.5 pt 在真实菜单栏中仍略小；左下电池温度的变化较慢，也不如 E 核温度适合与 P 核并排观察 CPU 负载。
- Constraint: 2×2 布局、两台动态风扇读数和固定模板图片方案必须保留；电池温度仍需在展开面板可见；字号增加后不得再次发生顶部裁切或菜单栏占位过宽。
- Decision: 模板图片调整为 20 pt 高，使用 8.5 pt 等宽半粗体，两行 y 坐标为 0 与 10 pt。左上显示 P 核热点，左下显示 E 核热点，右侧继续按动态枚举顺序显示前两台风扇实际 RPM；电池温度不再占用常驻摘要，但继续显示在展开面板。
- Alternatives（否决）: 保留 P 核与电池；删除一个风扇为温度让位；恢复系统布局的 SwiftUI 多行文本；继续增加到接近单行系统字号并承担裁切风险。
- Tradeoff: 用户不能在不展开面板时直接看到电池温度，但可以同时观察 P 核和 E 核响应；状态项比上一版略宽、略高，换取更好的日常可读性。
- Follow-up: 20 pt 高、8.5 pt 字形实机完整但用户仍希望更大。后续把同一方案上调为 22 pt 高、9.5 pt 字形，两行坐标为 0 与 11 pt；P/E 与双风扇布局、动态枚举和展开面板均不变。
- Follow-up: 22 pt 高、9.5 pt 字形实机完整后，根据用户反馈再小幅上调为 23 pt 高、10 pt 字形和 11.5 pt 行高。真实菜单栏截图读回 P/E 与两个风扇值均完整，布局与产品内容不变。

## ADR-033 · Turbo 接管使用有界稳定读回轮询 · 2026-08-30

- Problem: 上次真实 Turbo 从 `activation_started` 到读回两台风扇实际 RPM 上升约需 8.9 秒，其中 `Ftst` 接管始终先固定等待 3 秒。固定等待解决了立即读到旧值的安全问题，但在硬件已经稳定时仍会白等。
- Constraint: 租约所有权必须先于 `Ftst=1` 写入持久化；不能用单次紧邻读回代替稳定判断；风扇模式、最大目标和实际 RPM 上升门禁均不能省略。恢复路径曾经出现延迟写入在租约删除后才生效的事故，因此不与启动优化同时改动。
- Evidence: 当前真实日志两次都显示固定等待约 3.1 秒，之后还需约 5 至 6 秒等待风扇物理起转。新定向测试明确记录接管前置读回、一次未接管读回、两次 100 毫秒轮询和连续两次已接管读回；超时用例确认在碰任何风扇前失败，重申 `Ftst=0` 并删除租约。
- Decision: 写入 `Ftst=1` 后每 100 毫秒读回，只有连续两次为 1 才能继续；轮询以 3 秒为硬上限，超时继续按读回错误恢复。恢复时的 `Ftst=0` 仍保留固定 3 秒稳定窗口与最终读回。Turbo 激活文案改为“正在接管并等待风扇起转”，不再把全部物理起转时间笼统称为租约验证。
- Alternatives（否决）: 直接把固定等待缩短为一个更小的常数；只读一次 `Ftst`；跳过实际 RPM 上升验证；同时缩短恢复稳定窗口；为了立即生效而自动升级系统 helper。
- Tradeoff: 正常启动可以在 `Ftst` 连续稳定后立即继续，但总时间仍受风扇物理起转限制，不承诺瞬时 active。已注册 helper 不会因为构建新 App 而自动更新，需要用户另行授权升级后才能用到该优化。
- Follow-up: 为确保当前 App 能识别并拒绝仍运行固定等待逻辑的旧 helper，私有协议从 v5 提升到 v6。当前签名 v6 App 只会提示显式升级，不会自动替换已注册的 v5 helper，也不会在协议不兼容时启动 Turbo。

## ADR-034 · failed-safe-auto 立即重试并隔离并发 XPC 请求 · 2026-08-30

- Problem: v6 代码审查发现三项安全或可用性缺口。恢复失败虽然保留租约，但 300 毫秒看门狗只在原始截止时间到期后才重试，可能把 failed-safe-auto 留到 600 秒；`Ftst` 读回未知时，后续风扇写入若报告 thermal manager busy，仍可能补写未知的 `Ftst`；App 每秒状态查询与用户停止共用一个 XPC 请求槽，竞态时停止可能被误判为通信失败。
- Constraint: 恢复必须持续由 helper 独立承担，未知硬件状态不得靠写入探测；状态查询不能阻止用户停止，也不能放宽三个无参数方法、签名要求或固定 600 秒租约。当前 v6 helper 已通过短时 active 和主动停止验收，系统升级仍需单独授权。
- Evidence: 原有 `testRecoveryFailureKeepsLeaseForWatchdogRetry` 只断言租约保留，没有调用 watchdog 证明重试，属于测试名与证据不一致。新增用例在截止时间前解除模拟恢复故障并调用下一次 tick，确认返回 inactive、删除租约且全部模式为 Apple 管理；另两组用例确认未知 `Ftst` 时没有解锁写入或租约泄漏。完整普通测试 74 项通过、4 项硬件测试按设计跳过，独立只读恢复门禁 1 项通过。
- Decision: failed-safe-auto 且租约存在时，watchdog 下一 tick 立即再次执行恢复；启动前只有明确 `Ftst=0` 才允许声明可接管，未知值直接拒绝且不能因 manual write busy 补写；`TurboXPCClient` 以请求身份分别跟踪 continuation 和超时，允许状态查询与停止共存，连接失效时才统一失败剩余请求。取消后的状态轮询结果不得覆盖停止结果。菜单栏模板图片只显示前两台动态风扇，完整枚举留在面板和辅助功能描述。
- Alternatives（否决）: 保持租约直到截止时间再重试；把未知 `Ftst` 当成 0；停止前等待状态轮询超时；为每种请求建立独立 XPC 连接；继续让第三台及更多风扇扩张状态项宽度。
- Tradeoff: 恢复故障期间 helper 会每 300 毫秒重试受限恢复，增加少量 AppleSMC 访问；持久连接状态管理从单请求变为按请求字典，但停止交互不再被后台轮询阻塞。安全语义变化把私有协议提升到 v7，当前已注册 v6 helper 不会被自动替换，也不会被 v7 App 当成兼容实现。

## ADR-035 · Apple Silicon MacBook Pro 使用能力发现适配单与双风扇 · 2026-08-30

- Problem: 首台 Mac16,7、Apple M4 Pro 有 2 台风扇，状态项据此形成右侧上下两行。第二台 Mac17,2、Apple M5 只有 1 台风扇，如果继续填充第二行占位，单个转速会贴在右上且视觉失衡；原硬件刻画测试还保留 M4 专属候选 key 表，无法作为其他 MacBook Pro 的通用验收。
- Constraint: 当前产品范围只覆盖 macOS 26 以上 Apple Silicon MacBook Pro；风扇数量、模式 key、最大值和温度族必须动态读取，不能新增按机型硬编码表。展开面板必须保留全部风扇；Turbo 仍要求逐机型实机写入和恢复证据，不能因为只读监控通过而自动开放。
- Evidence: M5 普通权限探针读回 `FNum=1`、小写 `F0md`、`F0Mx=6550 RPM`，并取得 14 个有效 `Tp` 候选、4 个有效 `Te` 候选和两枚电池温度。单风扇探针与 12 秒温度族刻画分别通过；M4 Pro 与 M5 的完整普通测试都为 76 项通过、4 项硬件测试按设计跳过。M5 当时风扇已处于外部 manual mode 1，ThermalPulse 没有抢占。
- Decision: 产品范围暂定为 macOS 26 以上 Apple Silicon MacBook Pro。菜单栏左列固定显示 P/E，右列按动态风扇数布局：0 或 1 台时显示垂直居中的占位或转速，2 台及以上时上下显示前两台；更多风扇只在展开面板和辅助功能描述完整呈现。温度刻画统一使用动态 `Tp*`、`Te*` 族级证据，模式 key 同时发现 `Md` 与 `md`，不按 M4 或 M5 建表。监控支持与 Turbo 支持分开记录。
- Alternatives（否决）: 为 M5 单独写一个界面分支；继续在单风扇机器显示空白第二行；按机型 identifier 保存风扇数量和 key；把两台设备的只读成功外推为全部 Apple Silicon MacBook Pro 或 M5 Turbo 通过。
- Tradeoff: 状态项保持紧凑且能覆盖已知单、双风扇 MacBook Pro，但其他 Apple Silicon MacBook Pro 仍需逐台积累目录证据。能力发现减少机型表维护，不能消除 AppleSMC 非公开接口和 Turbo 实机验收成本。

## ADR-036 · 首个公开版本以 ad hoc DMG 交付只读监控 · 2026-08-31

- Problem: 用户需要通过 GitHub Actions 发布 v0.0.1 DMG，但当前没有可供云端使用的 Developer ID Application 证书、私钥和公证凭证。Turbo 的 XPC 安全模型又要求 App 与 helper 具有 Apple 信任链、固定 identifier 和相同非空 Team ID。
- Constraint: 发布过程不能上传本机签名私钥，不能撤销或替换其他项目证书，也不能为公开构建放宽 helper 调用方校验。产物必须是 macOS 26 arm64 DMG，并能从构建结果独立读回版本、签名完整性和挂载内容。
- Evidence: GitHub 官方 `macos-26-arm64` runner 当前提供 Xcode 26.6；本机同口径普通测试与 Release 构建通过，ad hoc App 通过 deep strict 校验，DMG 通过 CRC、只读挂载、版本 `0.0.1` 和 arm64 Mach-O 读回。ad hoc 签名没有 Team ID，因此现有客户端会拒绝 helper。
- Decision: `vX.Y.Z` tag 触发 GitHub Actions，tag 必须与 `MARKETING_VERSION` 一致。工作流运行普通测试、构建 Release、ad hoc 签名 App 与 helper、生成并挂载验证压缩 DMG、生成 SHA-256，再创建 prerelease。v0.0.1 公开 DMG 明确只支持普通权限只读监控，Turbo 保持不可用。
- Alternatives（否决）: 把 Personal Team 私钥导出到仓库；撤销或复用其他项目证书；在无 Team ID 时只按 bundle identifier 信任 App；手工上传未经 CI 验证的 DMG；把源码 ZIP 当作桌面发布产物。
- Tradeoff: 用户可以从 GitHub 获得可重复构建的 DMG，但首次启动仍需接受未公证提示，公开包暂时不能使用 Turbo。正式分发需要未来加入 Developer ID 签名与 Apple 公证，不影响本机 Personal Team 的独立 Turbo 验收。
