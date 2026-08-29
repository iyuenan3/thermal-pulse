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
- 曲线默认选择运行时验证过的风扇实际 RPM；仍有名额时，再选择枚举快照中数值最高的一个有效原始温度候选，并在本次会话保持该 key 稳定。温度候选仍显示原始 key 和未确认语义，同时最多选择 6 项。
- 图表候选目录只在全量枚举或手动刷新后筛选、排序并缓存；行级渲染只做常数时间成员判断，禁止为每一行重复处理完整目录。
- 高级原始温度候选默认折叠，折叠只减少界面节点，不停止后台 1 Hz 采样；用户需要检查原始值时可显式展开。
- RPM 与摄氏度必须分图显示。图表降采样保留首尾、局部极值和采样间隙，只影响显示点，不改写存储层原始历史。
- Turbo 使用 helper 持有的固定 600 秒绝对截止时间、进程内单调截止时间和持久租约；UI 倒计时只是展示，不是安全计时器。wall clock 回拨不能延长当前 helper 进程中的租约。
- 初始租约必须在任何 SMC 写入前成功持久化。每个风扇必须先把动态索引和已验证模式 key 加入租约，再尝试切手动；`Ftst` 也必须先记录由 ThermalPulse 接管，才能写 1。持久化失败时禁止任何 SMC 写入。
- 风扇模式 key 只能从本轮动态发现的 `F{i}Md` 或 `F{i}md` 取得，初始状态必须明确读回 automatic。manual、未知值或无法读回都按外部或不确定控制拒绝，不得假设全局 `FS! ` 存在。
- 最大目标写入必须复制本轮实时 `F{i}Mx` 的已验证原始字节到对应 `F{i}Tg`，不得重新编码调用方数值。active 前必须读回全部手动模式、最大目标和实际 RPM 上升趋势。
- App 侧 `TurboCoordinator` 只接受无参数 client，不传 RPM、时长或 key；active 响应必须校验开始时间、未来截止时间和不超过 600 秒的租约长度，重复启动不得再次调用 client。
- 私有 XPC identifier 只从 `ThermalPulseIdentity` 读取，不在 App、helper、plist 和测试中产生可漂移的第二份业务常量。LaunchDaemon plist 的固定值必须用构建产物读回验证。
- XPC 双方必须在 activate 或 resume 前设置 peer code-signing requirement，约束 Apple 签名锚点、固定 identifier 与从自身有效签名取得的相同 Team ID。签名无效、Team ID 缺失或 requirement 无法构造时直接拒绝，不允许放宽为 ad hoc 或仅 bundle id 校验。
- XPC payload 使用 `NSSecureCoding`、固定协议版本和有限枚举值。只允许三个无业务参数方法，不得借 reply block 之外的参数传入 RPM、时长或 SMC key。
- helper executable 和 LaunchDaemon plist 必须随 App bundle 分别位于 `Contents/Resources` 与 `Contents/Library/LaunchDaemons`。构建和布局验证不等于注册、root 启动或管理员批准。
- helper 升级必须先失效旧 XPC，等待 `SMAppService` 异步注销完成后再注册当前签名版本。升级动作需要独立确认，不得与 `startTurbo()` 合并，也不得用同步注销后立即注册制造竞态。
- 裸 helper executable 必须嵌入生成的 Info.plist section，使代码签名 identifier 由 `PRODUCT_BUNDLE_IDENTIFIER` 稳定决定。不能只检查 build setting，至少用一次签名产物读回实际 identifier。
- UI 只有在 stop 返回无错误 inactive 后才显示苹果自动。连接、写入、读回或恢复结果不可信时显示 failed-safe-auto，不把状态查询失败降级成 inactive。
- 恢复按租约中的风扇反向写 automatic，且只有所有模式明确读回 automatic、实际 RPM 有效、ThermalPulse 接管的 `Ftst` 已清除并读回后，才能删除租约。未知模式不能当成恢复成功。
- 持有租约的 XPC 连接断开、helper 启动发现旧租约或系统唤醒时立即恢复，不自动续跑。看门狗每秒检查绝对和单调截止时间，任一到期即恢复。
- 状态机、解析和边界验证优先纯逻辑测试；真实 SMC 写入使用显式人工授权的设备验收。
- 普通 `ThermalPulse` scheme 的测试默认跳过真实 AppleSMC；只读实机枚举使用显式 `ThermalPulseHardwareProbe` scheme，避免日常测试隐式依赖硬件。
- P 核摘要只动态聚合有效、有限、摄氏度、`flt` 类型且 key 以 `Tp` 开头的候选。不得硬编码候选表，不得把候选数称为核心数，不得给单个 key 添加具体核心编号；无有效输入时显示未知。
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
