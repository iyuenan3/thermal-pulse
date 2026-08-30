# CORE：ThermalPulse

## 身份

ThermalPulse 是一款面向 macOS 26 以上 Apple Silicon MacBook Pro 的原生菜单栏小工具，用一个紧凑面板展示设备温度、风扇和系统热状态，并提供一次最多 10 分钟的 Turbo 全速散热。

## 使命 / 解决什么问题

帮助需要长时间运行高负载任务的 Mac 用户理解温度、风扇与系统热状态的变化，并在明确知情、时间受限的情况下临时获得最大风冷能力。

## Non-Goals（明确不做）

- 不用自定义温度曲线长期接管苹果自动风扇策略。
- 不承诺锁定 CPU 频率，也不把频率变化都解释为热降频。
- 不提供任意风扇转速、任意 SMC key 或脚本化写入能力。
- 首版不提供云同步、账户、远程控制、后台上传或跨设备看板。
- 不依据未经实机验证的 key 名称给传感器贴确定标签。
- 当前不承诺支持 Intel Mac、MacBook Air、Mac mini、Mac Studio、iMac 或 Mac Pro。
- 不因为一台或两台 MacBook Pro 通过就宣称全部 Apple Silicon MacBook Pro 的 Turbo 已验收。

## 绝不 / Hard Constraints（红线）

- 苹果自动模式是默认状态，也是任何失败和不确定状态的唯一回退状态。
- 只读监控不得要求 root，不得改变任何 SMC 值。
- Turbo 单次期限不得超过 600 秒，并由 privileged helper 独立持有截止时间。
- Turbo 只能设置所有已验证风扇为各自读回的最大值，绝不硬编码风扇数量、最低值或最高值。
- 到期、取消、App 退出、App 崩溃、XPC 断开、helper 启动或重启，以及休眠唤醒后发现期限已过，都必须恢复自动模式。
- helper 只接受经过身份校验的调用方。Developer Team 构建使用 Apple 签名锚点、固定 identifier 与相同 Team ID；公开 ad hoc 构建只接受管理员安装时固定到 root-owned manifest 的 App identifier、安装路径和精确代码目录哈希。两条路径都只暴露 Turbo 启动、停止和状态查询，不允许仅凭 bundle identifier 调用，也不暴露通用 SMC 写接口。
- 传感器数据类型、范围或身份不可信时，只能展示为未识别原始数据，不能参与安全决策。
- 不收集、上传或写入设备序列号、硬件 UUID、凭证、签名私钥或其他敏感数据。
- 未取得真实风扇模式和实际 RPM 读回证据，不得宣布 Turbo 或自动恢复验收通过。

## 生命周期

active，pre-alpha。当前工作树已把产品收敛为菜单栏单面板，只展示 P 核热点、E 核热点、电池平均温度、风扇与系统热状态，并提供一张固定 5 分钟温度曲线。Mac16,7、Apple M4 Pro 已实测 102 个有效 `Tp` float 候选、10 个有效 `Te` float 候选、两枚电池温度和 2 台风扇；Mac17,2、Apple M5 已实测 14 个有效 `Tp` 候选、4 个有效 `Te` 候选、两枚电池温度和 1 台风扇。菜单栏按动态风扇数量布局，单风扇在右列垂直居中，双风扇上下显示，不使用机型 key 表。协议 v6 helper 已在 Mac16,7 完成短时 Turbo 的快速接管、active 与主动停止恢复；协议 v7 的安全加固只完成源码、测试和 Personal Team 签名构建。协议 v8 为公开 ad hoc 构建增加管理员安装、root-owned manifest 与双向 CDHash 固定路径，并作为 v0.1.1 预发布安装测试候选交付；普通测试和临时 ad hoc requirement 验证已通过，但尚未安装 root helper、实连 XPC 或启动 Turbo。M5 当前只完成普通权限只读监控，探测时已有外部手动风扇控制，未安装 helper 或尝试 Turbo。v0.1.1 不代表公开 Turbo 已验收，系统级安装和实机控制由用户在发布后单独测试。旧 Release 页面与标签保留，旧版本二进制资产按保留策略移除。
