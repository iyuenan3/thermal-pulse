# SPEC：ThermalPulse

## 端点

v0.1 不提供网络端点、URL scheme、CLI 或第三方插件接口。产品是本地 macOS App，唯一的进程间接口是 App 与 privileged helper 之间的私有 XPC 协议。

## 鉴权

- 只读监控：无鉴权、无管理员权限，直接在当前用户进程读取允许访问的系统信息。
- Turbo：首次使用时按 macOS 标准流程注册并批准 privileged helper。
- XPC：App bundle identifier 固定为 `io.github.iyuenan3.thermalpulse`，helper identifier 和 Mach service 固定为 `io.github.iyuenan3.thermalpulse.helper`。双方都先严格验证自身签名，再动态取得自身 Team ID，并要求 peer 满足 `anchor apple generic`、固定 identifier 和相同 Team ID。未签名或签名无效时拒绝连接，不提供仅按 identifier 校验的回退。本文不记录 Team ID、私钥或证书材料。

## 产品能力契约

### 菜单栏

- 标题使用固定 23 pt 高的模板图片形成紧凑摘要，图片内部以 10 pt 等宽字形和固定两列坐标绘制。左上显示 `P` 核心热点，左下显示 `E` 核心热点；动态枚举到 1 台风扇时，右列只显示一个垂直居中的实际 RPM，枚举到 2 台及以上时，右上和右下显示前两台实际 RPM。状态项省略风扇标签和单位，电池温度与完整动态风扇信息保留在展开面板。单风扇或双风扇结果都不得来自硬编码 SMC 索引。
- 点击后在无滚动条的单一紧凑面板中完整显示 P 核候选族、E 核候选族、电池、固定 5 分钟温度曲线、系统 thermal state、逐风扇 RPM 与 Turbo。
- 数据不可用时明确显示未知，不用 `0°C` 或 `0 RPM` 伪装有效值。
- P 核和 E 核曲线只展示 10 至 120 °C 的有效历史点；原始代表 key 返回 0 或其他越界哨兵值时省略该点，并保留采样间隙，不把间隙两侧连成连续数据。
- 不创建独立监控窗口，不在菜单栏面板中使用滚动容器，也不提供侧栏、原始 key 浏览、传感器选择或时间范围切换。
- P 核只聚合有效 `Tp` float 候选，E 核只聚合有效 `Te` float 候选，电池只接受 `TB1T`、`TB2T`。不命中时显示不可用，不做跨类别回退；候选数量不得解释为物理核心数量。

### Turbo

- 用户主动点击后启动固定 600 秒全速散热，不接受自定义时长或自定义 RPM。
- 所有风扇使用实时枚举得到的 `F{i}Mx`，不得只控制风扇 0。
- 活跃期间显示从 10:00 开始的明确倒计时和“停止 Turbo，恢复自动”操作。
- helper 可用时，用户单击启动按钮即调用 `startTurbo()`，不再显示二次确认。注册和升级仍使用各自的独立确认。
- 再次点击取消、600 秒到期或任一安全事件发生后，恢复所有由 ThermalPulse 接管的风扇为自动模式。
- 检测到风扇已被其他控制器置为手动，且不存在 ThermalPulse 自己的有效租约时，拒绝启动 Turbo，不抢占其他控制器。

## 当前 App 侧 Turbo 契约

- `TurboClient` 只定义无参数 `startTurbo()`、`stopTurbo()` 和 `getTurboStatus()`，没有 RPM、时长或 SMC key 参数。
- `TurboStatus` 包含 inactive、activating、active、restoring、failed-safe-auto、开始时间、绝对截止时间和有限错误类别。
- App 只接受带开始时间与未来截止时间、且两者相差不超过 600 秒的 active 响应。重复启动不再次调用 client，也不延长截止时间。
- stop 只有返回无错误 inactive 时才显示苹果自动。通信、写入或恢复状态不可信时显示 failed-safe-auto，不宣布恢复成功。
- 当前 `TurboXPCClient` 已接入固定 Mach service，并为 helper 设置代码签名 requirement。未签名构建返回 helper unavailable；只有系统注册状态为 enabled 时才查询 XPC。同一持久连接允许状态查询与停止请求并发存在，各请求独立完成；连接失效时才统一失败剩余请求。协议 v6 已完成快速 `Ftst` 接管、短时 active 和主动停止实机读回；当前协议 v7 强制已注册 v6 helper 显式升级，确保实际运行的 helper 包含恢复失败立即重试和未知 `Ftst` 拒绝写入。控件、源码、签名和写入通路可达仍不等于全部恢复场景已经验收。

## helper 注册状态契约

- App 启动和 Turbo 控件出现时只调用 `SMAppService.status`，不得自动注册 LaunchDaemon。
- `notRegistered` 与首次查询可能返回的 `notFound` 都表示可以展示注册入口。`notFound` 不得直接解释为 App 包内缺少 plist。
- 用户必须先点击“注册 Turbo helper”，再在确认弹窗中明确确认，App 才调用无参数 `SMAppService.register()`。注册动作本身不启动 Turbo，也不写 SMC。
- `requiresApproval` 时只提供打开系统设置和重新检查状态；`enabled` 时才允许继续查询 XPC 状态；签名无效或注册失败时显示有限错误，不绕过 macOS 校验。
- 不提供自动注册、自动升级或静默批准接口。旧 helper 返回 write-path-unavailable 或协议不兼容时，用户可经过独立确认执行升级；App 先失效旧 XPC，等待 `SMAppService` 异步注销完成，再以 100 毫秒间隔连续观察 10 次 `notRegistered` 或 `notFound`，最多等待 8 秒。只有状态稳定才调用一次无参数 `register()`，失败后不自动重试。升级成功也不调用 `startTurbo()`。

## 私有 XPC 协议 v7

允许的方法只有：

- `startTurbo(reply:)`：无业务参数。源码实现先拒绝外部或未知手动状态，以及不属于 ThermalPulse 的 `Ftst` 占用，再持久化固定 600 秒租约。当前机器从 mode 3 启动时必须明确读回 `Ftst=0`，未知值直接拒绝且不得写 `Ftst`；确认后才先持久化 `Ftst` 所有权，再设置 `Ftst=1`，每 100 毫秒读回一次，连续两次为 1 就立即继续，3 秒内仍不稳定则失败并恢复。每个动态风扇在模式写入前先记录接管范围，目标值复制本轮实时 `F{i}Mx` 原始字节。只有全部 mode 1、原始字节精确相等的最大目标，以及位于 0 至动态最大值 105% 内并呈上升趋势的实际 RPM 都读回后才返回 active。重复请求不续时。
- `stopTurbo(reply:)`：无业务参数。源码实现反向恢复租约中所有已接管风扇。mode 0 与 mode 3 都表示 Apple 管理，mode 1 才需要写 automatic；租约记录 ThermalPulse 接管过 `Ftst` 时始终写 0，等待稳定读回，并读回全部模式与实际 RPM；全部确认后才删除租约并返回无错误 inactive。
- `getTurboStatus(reply:)`：无业务参数。返回 inactive、activating、active、restoring 或 failed-safe-auto，以及绝对开始时间、绝对截止时间和有限错误类别。App 可每秒调用它刷新倒计时，但这不是安全计时器。

reply 使用单一 `NSSecureCoding` payload，字段只有 `protocolVersion`、`phaseRawValue`、`startedAt`、`deadline` 和 `issueRawValue`。协议版本固定为 7；未知版本、阶段或错误值被拒绝为不兼容或无效状态。版本 7 保留版本 6 的 `Ftst` 快速稳定读回，并强制系统 helper 升级到恢复失败立即重试和未知 `Ftst` 拒绝写入语义。客户端的启动、停止和状态查询超时分别为 70 秒、12 秒和 3 秒，任何超时都使连接失效，不返回伪 inactive；单个 reply 只完成对应请求，不能覆盖同连接上的其他未完成请求。

helper 持有绝对截止时间与进程内单调截止时间，300 毫秒 active 看门狗不依赖 App UI。它持续核对 `Ftst`、动态风扇集合、模式、实时最大目标和实际 RPM；实际 RPM 非有限、低于零或超过动态最大值 105% 时立即进入恢复。系统重写模式或目标时，只在 ThermalPulse 自己的有效租约内有界协调。到期、持有连接断开、`Ftst` 丢失、风扇集合变化、唤醒或无法重新确认状态都会进入恢复；helper 启动发现任何持久租约时直接恢复，不续跑旧租约。恢复失败时保留租约并进入 failed-safe-auto，下一次 300 毫秒看门狗 tick 立即重试，不等待原始截止时间。租约只记录开始时间、绝对截止时间、已触碰风扇索引与模式 key，以及 ThermalPulse 是否接管 `Ftst`。

禁止的方法：任意 key 读写、任意 RPM、任意时长、关闭看门狗、跳过调用方校验。

错误至少区分：不支持的硬件、无风扇、传感器或风扇枚举失败、已有外部手动控制器、helper 不可用、helper 未批准、写入链路未启用、调用方未授权、协议不兼容、SMC 写入失败、模式读回、目标读回、实际 RPM 读回、安全恢复失败、无效状态响应和通信失败。helper 日志进一步把恢复失败分为 fan mode、actual RPM、thermal manager unlock 与 lease removal 阶段，不记录设备标识。

## 配额 / 分组

- 无网络配额。
- 同一时刻最多存在一个 Turbo 租约。
- 重复启动请求不延长当前截止时间。用户应先取消，再显式重新启动。
- 传感器采样与图表刷新不得通过提高 root helper 调用频率实现，helper 只服务 Turbo 写入和状态。

## 版本 / 兼容

- pre-1.0 阶段不承诺私有 XPC ABI 稳定，但 App 与 helper 必须带同一协议版本并拒绝不兼容组合。
- 当前产品支持范围为 macOS 26 以上 Apple Silicon MacBook Pro。Mac16,7 已验证双风扇监控和短时 Turbo，Mac17,2 已验证单风扇只读监控；其他 Apple Silicon MacBook Pro 在实机证据进入支持矩阵前保持未验证，其他 Mac 产品线不在当前支持范围。
- 机型支持按真实设备验证逐台增加，不采用“M1 到 M5 默认兼容”声明。
- 破坏性产品行为变化需要更新 PRD、DECISIONS 和 CHANGELOG。
