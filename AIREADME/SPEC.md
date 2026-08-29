# SPEC：ThermalPulse

## 端点

v0.1 不提供网络端点、URL scheme、CLI 或第三方插件接口。产品是本地 macOS App，唯一的进程间接口是 App 与 privileged helper 之间的私有 XPC 协议。

## 鉴权

- 只读监控：无鉴权、无管理员权限，直接在当前用户进程读取允许访问的系统信息。
- Turbo：首次使用时按 macOS 标准流程注册并批准 privileged helper。
- XPC：App bundle identifier 固定为 `io.github.iyuenan3.thermalpulse`，helper identifier 和 Mach service 固定为 `io.github.iyuenan3.thermalpulse.helper`。双方都先严格验证自身签名，再动态取得自身 Team ID，并要求 peer 满足 `anchor apple generic`、固定 identifier 和相同 Team ID。未签名或签名无效时拒绝连接，不提供仅按 identifier 校验的回退。本文不记录 Team ID、私钥或证书材料。

## 产品能力契约

### 菜单栏

- 显示代表性热状态、风扇转速和系统 thermal state。
- 点击后可进入完整监控窗口。
- 数据不可用时明确显示未知，不用 `0°C` 或 `0 RPM` 伪装有效值。

### 监控窗口

- 传感器按 CPU、GPU、封装、内存、供电、电池、环境和风扇等已验证类别分组。
- 支持实时值、最小值、最大值、平均值和可选曲线。
- 目标采样周期为 1 秒，首版时间范围为 5 分钟、15 分钟和 1 小时。
- 未确认语义的 SMC key 只进入高级原始数据视图，不进入默认分组。

### Turbo

- 用户主动点击后启动固定 600 秒全速散热，不接受自定义时长或自定义 RPM。
- 所有风扇使用实时枚举得到的 `F{i}Mx`，不得只控制风扇 0。
- 活跃期间显示明确倒计时和“立即恢复自动”操作。
- 再次点击取消、600 秒到期或任一安全事件发生后，恢复所有由 ThermalPulse 接管的风扇为自动模式。
- 检测到风扇已被其他控制器置为手动，且不存在 ThermalPulse 自己的有效租约时，拒绝启动 Turbo，不抢占其他控制器。

## 当前 App 侧 Turbo 契约

- `TurboClient` 只定义无参数 `startTurbo()`、`stopTurbo()` 和 `getTurboStatus()`，没有 RPM、时长或 SMC key 参数。
- `TurboStatus` 包含 inactive、activating、active、restoring、failed-safe-auto、开始时间、绝对截止时间和有限错误类别。
- App 只接受带开始时间与未来截止时间、且两者相差不超过 600 秒的 active 响应。重复启动不再次调用 client，也不延长截止时间。
- stop 只有返回无错误 inactive 时才显示苹果自动。通信、写入或恢复状态不可信时显示 failed-safe-auto，不宣布恢复成功。
- 当前 `TurboXPCClient` 已接入固定 Mach service，并为 helper 设置代码签名 requirement。未签名构建返回 helper unavailable；只有系统注册状态为 enabled 时才查询 XPC。连接在 App 生命周期内保持，进程退出、连接中断或失效会触发 helper 按连接 owner 恢复。当前系统已运行最终写入版 helper。2026-08-30 首次调用 `startTurbo()` 因读回不一致返回 failed-safe-auto，没有进入 active；失败后独立确认全部模式与 `Ftst` 为 0、实际 RPM 有效且租约已删除。控件和写入通路可达仍不等于真实风扇控制已经验收。

## helper 注册状态契约

- App 启动和 Turbo 控件出现时只调用 `SMAppService.status`，不得自动注册 LaunchDaemon。
- `notRegistered` 与首次查询可能返回的 `notFound` 都表示可以展示注册入口。`notFound` 不得直接解释为 App 包内缺少 plist。
- 用户必须先点击“注册 Turbo helper”，再在确认弹窗中明确确认，App 才调用无参数 `SMAppService.register()`。注册动作本身不启动 Turbo，也不写 SMC。
- `requiresApproval` 时只提供打开系统设置和重新检查状态；`enabled` 时才允许继续查询 XPC 状态；签名无效或注册失败时显示有限错误，不绕过 macOS 校验。
- 不提供自动注册、自动升级或静默批准接口。旧 helper 返回 write-path-unavailable 时，用户可经过独立确认执行升级；App 先失效旧 XPC，等待 `SMAppService` 异步注销完成，再调用无参数 `register()`。2026-08-29 已由用户显式完成写入版升级，root 启动、Mach endpoint 和双向签名 XPC 状态查询均已实连；卸载流程与真实 SMC 写入仍待单独验收。

## 私有 XPC 协议 v1

允许的方法只有：

- `startTurbo(reply:)`：无业务参数。源码实现先拒绝外部或未知手动状态，再持久化固定 600 秒租约；每个动态风扇在模式写入前先记录接管范围，目标值复制本轮实时 `F{i}Mx` 原始字节，最后验证模式、目标和实际 RPM 上升趋势，才返回 active。重复请求不续时。
- `stopTurbo(reply:)`：无业务参数。源码实现反向恢复租约中所有已接管风扇，读回明确 automatic，并在需要时清除和读回 `Ftst`；全部确认后才删除租约并返回无错误 inactive。
- `getTurboStatus(reply:)`：无业务参数。返回 inactive、activating、active、restoring 或 failed-safe-auto，以及绝对开始时间、绝对截止时间和有限错误类别。

reply 使用单一 `NSSecureCoding` payload，字段只有 `protocolVersion`、`phaseRawValue`、`startedAt`、`deadline` 和 `issueRawValue`。协议版本固定为 1；未知版本、阶段或错误值被拒绝为不兼容或无效状态。客户端的启动、停止和状态查询超时分别为 70 秒、12 秒和 3 秒，任何超时都使连接失效，不返回伪 inactive。

helper 持有绝对截止时间与进程内单调截止时间，1 秒看门狗不依赖 App UI。到期、持有连接断开、唤醒或状态矛盾都会进入恢复；helper 启动发现任何持久租约时直接恢复，不续跑旧租约。租约只记录开始时间、绝对截止时间、已触碰风扇索引与模式 key，以及 ThermalPulse 是否接管 `Ftst`。

禁止的方法：任意 key 读写、任意 RPM、任意时长、关闭看门狗、跳过调用方校验。

错误至少区分：不支持的硬件、无风扇、传感器或风扇枚举失败、已有外部手动控制器、helper 不可用、helper 未批准、写入链路未启用、调用方未授权、协议不兼容、SMC 写入失败、读回不一致、安全恢复失败、无效状态响应和通信失败。App 与新 helper 的类型、transport、身份、租约和写入状态机已经实现并有自动化故障测试；首次真实写入已验证 readback mismatch 会阻断 active 并恢复 automatic，但错误类别尚不能指出是模式、目标还是实际 RPM 门禁失败，仍需增加逐阶段诊断后再做目标机复验。

## 配额 / 分组

- 无网络配额。
- 同一时刻最多存在一个 Turbo 租约。
- 重复启动请求不延长当前截止时间。用户应先取消，再显式重新启动。
- 传感器采样与图表刷新不得通过提高 root helper 调用频率实现，helper 只服务 Turbo 写入和状态。

## 版本 / 兼容

- pre-1.0 阶段不承诺私有 XPC ABI 稳定，但 App 与 helper 必须带同一协议版本并拒绝不兼容组合。
- 机型支持按真实设备验证逐台增加，不采用“M1 到 M5 默认兼容”声明。
- 破坏性产品行为变化需要更新 PRD、DECISIONS 和 CHANGELOG。
