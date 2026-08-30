# CONVENTIONS：ThermalPulse

## 命名

- 项目 slug、仓库名和目录名统一为 `thermal-pulse`，展示名为 `ThermalPulse`。
- Swift 类型使用 UpperCamelCase，成员和方法使用 lowerCamelCase；SMC 原始 key 保持原始四字符大小写，不做自动规范化。
- 风扇通过动态索引 `i` 表示，业务代码使用稳定 `FanID`，不把 `F0` 当成唯一风扇。
- 传感器稳定身份与中文显示名分离。身份来自原始 key 与机型上下文，显示名必须带证据等级。
- 时间字段明确区分 sample timestamp、Turbo startedAt 和 absolute deadline。

## 偏好模式

- 原始 SMC 访问只存在于低层 adapter，业务层只接触 typed value、单位、有效性和错误。
- AppleSMC user-client 参数结构由单一 C bridging header 定义，并同时用 C `_Static_assert` 与 Swift 单元测试锁定 80 字节 ABI，不在 Swift 文件中复制近似布局。
- SMC 数据按类型解码：整数与 `sp` / `fp` 定点数使用大端，Apple Silicon `flt ` 使用小端 IEEE 754；禁止对所有类型套用同一字节序。
- 传感器值携带单位与有效性，不用特殊数值表示未知；温度统一摄氏度，转速统一 RPM，时长统一秒。
- 一个传感器失败只隔离该传感器，不中断整轮采样；风扇控制前置验证失败则阻断整次 Turbo。
- 全量 key 枚举只在启动或用户手动刷新时执行；持续采样必须使用由本轮有效读回动态形成的稳定白名单和缓存元数据。
- 采样节拍使用单调时钟，默认 1 Hz；错过节拍时等待下一个完整间隔，不追赶补采，防止集中读取 AppleSMC。
- 每个传感器历史最多保存 3600 个有效内存样本；不可用、非有限或越界值可出现在最新帧，但不得写入历史或统计。
- 历史统计随环形缓冲写入增量维护；只有淘汰当前极值时允许扫描该单个序列，禁止每秒为所有序列重新遍历 1 小时历史。
- 固定容量环形缓冲在 actor 字典中使用引用语义并原地更新，禁止通过值类型取出、修改、写回而触发整块存储的写时复制。
- 菜单栏温度曲线只选择 P 核 `Tp*`、E 核 `Te*` 与电池 `TB1T/TB2T` 三类中实际可用的稳定代表 key，固定显示最近 5 分钟，不提供原始 key、传感器选择或时间范围入口。
- 菜单栏状态项必须把 `P/E` 核心热点和动态风扇 RPM 预渲染为固定 23 pt 高模板图片，内部使用 10 pt 等宽字形和固定列坐标。0 或 1 台风扇时，右列显示垂直居中的占位或转速；2 台及以上时，右列上下显示前两台转速。禁止再次依赖 `MenuBarExtra` 对复合 SwiftUI 标签或多行 `Text` 的字体、行距和裁切行为。电池温度、完整标签、单位及所有动态风扇留在展开面板和辅助功能描述。风扇行必须来自本轮枚举结果，不得为单风扇或双风扇机器硬编码 SMC 索引；超过两台时不得继续扩张状态项宽度。弹出面板不得依赖滚动容器隐藏核心信息，正常状态下全部信息应一次展开可见。
- 正式 App 图标只通过 `Assets.xcassets/AppIcon.appiconset` 接入，覆盖 macOS 16、32、128、256、512 pt 的 1x 与 2x 槽位。源图保持方形、透明边角和小尺寸可辨认轮廓；发布构建必须读回 `AppIcon.icns` 与 `CFBundleIconName=AppIcon`，不能只凭资源目录存在宣布接入成功。
- P 核与 E 核历史在展示边界复用 10 至 120 °C 的合理范围，省略 0 和其他越界哨兵点；省略后按时间戳形成断线，禁止把缺失值替换为 0 或跨缺口连线。
- 图表代表 key 只在全量枚举或手动刷新后确定并缓存；行级渲染只做常数时间成员判断，禁止为每一行重复处理完整目录。
- 图表降采样保留首尾、局部极值和采样间隙，只影响显示点，不改写存储层原始历史。
- Turbo 使用 helper 持有的固定 600 秒绝对截止时间、进程内单调截止时间和持久租约；UI 倒计时只是展示，不是安全计时器。wall clock 回拨不能延长当前 helper 进程中的租约。
- 初始租约必须在任何 SMC 写入前成功持久化。每个风扇必须先把动态索引和已验证模式 key 加入租约，再尝试切手动；`Ftst` 也必须先记录由 ThermalPulse 接管，才能写 1。持久化失败时禁止任何 SMC 写入。
- 风扇模式 key 只能从本轮动态发现的 `F{i}Md` 或 `F{i}md` 取得。Apple Silicon 的 mode 0 与 mode 3 都属于 Apple 管理，mode 1 属于手动，未知值或无法读回按不确定状态拒绝。启动前只允许 Apple 管理模式，不得假设全局 `FS! ` 存在。
- 最大目标写入必须复制本轮实时 `F{i}Mx` 的已验证原始字节到对应 `F{i}Tg`，不得重新编码调用方数值。目标读回继续要求原始字节精确相等；实际 RPM 是独立反馈，允许不超过动态最大值 5% 的控制或量化超调。active 前必须读回全部手动模式、最大目标和实际 RPM 上升趋势，active watchdog 对非有限、负值或超过动态最大值 105% 的反馈立即恢复。
- 逐风扇控制文案必须从可信 `TurboStatus` 映射。只有无错误 inactive 可以写“苹果自动控制”，active 必须写“Turbo 全速控制”，状态查询或恢复不可信时写“控制状态待确认”。
- App 侧 `TurboCoordinator` 只接受无参数 client，不传 RPM、时长或 key；active 响应必须校验开始时间、未来截止时间和不超过 600 秒的租约长度，重复启动不得再次调用 client。
- 私有 XPC identifier 只从 `ThermalPulseIdentity` 读取，不在 App、helper、plist 和测试中产生可漂移的第二份业务常量。LaunchDaemon plist 的固定值必须用构建产物读回验证。
- XPC 双方必须在 activate 前设置 peer code-signing requirement。具备 Team ID 时约束 Apple 签名锚点、固定 identifier 与从自身有效签名取得的相同 Team ID；没有 Team ID 时只允许管理员安装器生成的 root-owned manifest 路径，并同时约束固定 identifier 与精确 CDHash。ad hoc 路径还必须确认自身 strict 签名、固定安装路径、manifest 与父目录属于 root 且不可由 group 或 other 写入。任一条件失败直接拒绝，不允许仅按 bundle identifier 校验。
- XPC payload 使用 `NSSecureCoding`、固定协议版本和有限枚举值。只允许三个无业务参数方法，不得借 reply block 之外的参数传入 RPM、时长或 SMC key。同一持久连接上的每个请求必须独立保存 continuation 和超时任务；单个 reply 只解除自身请求，只有连接失效才统一失败剩余请求。取消后的状态轮询不得覆盖主动停止结果。
- helper executable 和 ServiceManagement LaunchDaemon plist 必须随 App bundle 分别位于 `Contents/Resources` 与 `Contents/Library/LaunchDaemons`。ad hoc 路径的 `.command` 安装器和固定 `ProgramArguments` plist 必须位于 `Contents/Resources`，发布构建需读回可执行权限和 plist 语法。构建和布局验证不等于安装、root 启动或管理员批准。
- Developer Team 路径的 helper 升级必须先失效旧 XPC，等待 `SMAppService` 异步注销完成，并连续观察系统状态稳定为 `notRegistered` 或 `notFound` 后，才注册一次当前签名版本。ad hoc 路径必须拒绝现存租约和不明旧 job，使用固定系统路径、root ownership 与有界回滚；App 或 helper 代码哈希变化时重新安装。两条路径的升级动作都需要独立确认，不得与 `startTurbo()` 合并，失败后不得自动重试或继续 Turbo。
- 裸 helper executable 必须嵌入生成的 Info.plist section，使代码签名 identifier 由 `PRODUCT_BUNDLE_IDENTIFIER` 稳定决定。不能只检查 build setting，至少用一次签名产物读回实际 identifier。
- UI 只有在 stop 返回无错误 inactive 后才显示苹果自动。连接、写入、读回或恢复结果不可信时显示 failed-safe-auto，不把状态查询失败降级成 inactive。
- `Ftst` 写入按异步状态变化处理。启动前只有明确读回 0 才允许声明可接管；未知值不能视为未占用，也不能在风扇写入返回 thermal manager busy 后补写 `Ftst`。持久化所有权并写 1 后每 100 毫秒读回，只有连续两次为 1 才能继续，3 秒内仍不稳定就失败并恢复，不能用紧邻写入的旧值判断成功或失败。恢复时只要租约记录过接管，就始终写 0，保留 3 秒稳定等待和读回，之后才允许删除租约。
- 恢复按租约中的风扇反向处理。先读模式，mode 1 才写 automatic，mode 0 或 mode 3 跳过冗余模式写入。只有所有模式明确为 Apple 管理、实际 RPM 有效、ThermalPulse 接管的 `Ftst` 稳定为 0 且 lease 删除成功，才能返回 inactive。未知模式不能当成恢复成功。恢复失败必须保留租约；failed-safe-auto 且租约仍存在时，下一个看门狗 tick 立即再次恢复，不能等到 600 秒截止时间才重试。
- 持有租约的 XPC 连接断开、helper 启动发现旧租约或系统唤醒时立即恢复，不自动续跑。active 看门狗每 300 毫秒检查绝对和单调截止时间、`Ftst`、动态风扇集合、模式、实时最大目标与实际 RPM；只在 ThermalPulse 自己的有效租约内执行有界协调，任一状态无法重新确认或任一截止时间到期即恢复。
- 状态机、解析和边界验证优先纯逻辑测试；真实 SMC 写入使用显式人工授权的设备验收。
- 普通 `ThermalPulse` scheme 的测试默认跳过真实 AppleSMC；只读实机枚举使用显式 `ThermalPulseHardwareProbe` scheme，避免日常测试隐式依赖硬件。
- 发布 tag 必须使用 `vX.Y.Z`，并与工程 `MARKETING_VERSION` 完全一致。公开产物只允许 macOS 26 arm64 DMG 和对应 SHA-256；工作流必须先验证普通测试、Release App 版本、ad hoc deep strict 签名、DMG CRC 与挂载后 App，不得只上传未经读回的构建目录。
- GitHub Actions 没有 Developer ID 签名材料时，公开包必须明确标注 ad hoc、未公证和管理员安装风险。若包含 Turbo，App/helper 必须使用 hardened runtime ad hoc 签名，工作流必须验证双方 strict 完整性、固定 identifier、CDHash requirement、安装器语法和手动 LaunchDaemon plist；运行时必须使用 root-owned manifest 固定双方代码哈希。禁止把签名私钥提交到仓库，也禁止退化成任意无签名 helper、仅 bundle identifier、可变安装路径或通用 root 写接口。
- Apple Silicon MacBook Pro 的硬件刻画按动态 `Tp*`、`Te*`、电池和风扇能力族验收，不在测试中维护 M4、M5 或具体机型的候选 key 表。`F{i}Md` 与 `F{i}md` 都必须通过动态发现支持；探针读到外部 manual mode 时只能记录并阻断 Turbo，不能为完成测试而改写模式。
- P 核摘要只动态聚合有效、有限、10 至 120 °C、`flt` 类型且 key 以 `Tp` 开头的候选；E 核摘要使用相同约束并要求 key 以 `Te` 开头。P 核与 E 核向用户显示当前最高候选，电池显示 `TB1T` 与 `TB2T` 平均。不得硬编码候选表，不得把候选数称为核心数，不得给单个 key 添加具体核心编号；无有效输入时显示未知。
- 默认温度面板只允许三类证据映射：P 核 `Tp*` float 候选族、E 核 `Te*` float 候选族、电池 `TB1T/TB2T`。缺失类别显示不可用，不使用其他热区回退，也不根据当前数值猜身份。
- 性能归因日志只在界面状态变化、重新枚举和每满 60 个有效样本时记录；字段限于样本数、曲线数量、时间范围、界面布尔状态和系统 thermal state，不记录设备标识或原始 SMC key。
- 日志默认不记录设备标识和完整原始环境，只记录诊断所需的机型类别、key、数据类型、状态和错误码。
- 中文文档与界面使用中文标点，不使用破折号。
- 日期和验收时间使用 `Asia/Shanghai`，星期与日期映射必须由工具计算。

## 禁用模式

- 禁止散落裸 `IOConnectCallStructMethod` 调用或复制 SMC 结构体定义。
- 禁止把未知、NaN、越界或读取失败的数据渲染为零。
- 禁止按当前最高温度直接猜传感器身份。
- 禁止每秒重新枚举全部 SMC key，或在一次延迟后突发补采多个旧节拍。
- 禁止曲线一次复制全部传感器历史，或把 RPM 与摄氏度放在同一数值纵轴上。
- 禁止硬编码风扇数量、最低转速、最高转速和旧机型 key 列表。
- 禁止 public、distributed 或脚本接口暴露任意 SMC 写入。
- 禁止重复点击 Turbo 隐式延长截止时间。
- 禁止只测正常退出，不测强杀、连接断开、重启、休眠和冲突控制器。
- 禁止以源码、日志或 XPC 返回值代替风扇模式与实际 RPM 读回证据。
