# ThermalPulse

ThermalPulse 是一个原生 macOS 本地热状态监控工具。目标是像活动监视器一样展示温度候选、风扇 RPM 和系统 thermal state，并在通过实机安全验收后提供用户显式触发、固定 600 秒、失效自动恢复的 Turbo 散热。

## 当前状态

项目处于 pre-alpha。当前切片已经包含：

- 原生 SwiftUI 菜单栏 App 与无侧栏单页监控窗口。
- 普通权限只读 AppleSMC adapter。
- 动态 key 和风扇枚举、typed sensor model、数据类型解码与有效性判断。
- 启动时建立动态采样白名单，之后以 1 Hz 读取有效风扇实际转速和温度候选。
- 每个传感器最多保存 3600 个内存样本，并展示最新值、最小值、最大值和平均值。
- 动态聚合有效 `Tp` float 温度候选，在概览和菜单栏显示 P 核温度族平均值、最高值与候选数量，不给单个 key 编造具体核心身份。
- 提供 5 分钟、15 分钟和 1 小时历史曲线，默认选择已验证风扇和当前最高的一个 `Tp` 温度候选，用户可手动调整并最多选择 6 项。
- RPM 与原始温度候选分图展示，高级原始候选默认折叠，显示前进行保留端点、极值和采样间隙的降采样。
- 菜单栏标题直接显示紧凑 P 核温度和所有已枚举风扇 RPM；弹出面板用蓝色温度主状态、紧凑分组信息行和底部主按钮展示逐风扇读数与“打开监控窗口”，主窗口关闭后可以重新打开并置于前台。
- 主窗口与菜单栏弹窗均提供固定 10 分钟 Turbo 控件。源码包含受限 helper 写入适配器、持久租约、独立看门狗、断连和唤醒恢复状态机；接口仍只有无参数启动、停止和状态查询。最终写入版 helper 已在当前开发机完成签名升级、root 启动与 XPC inactive 状态回读，界面现可进入启动确认；本轮没有调用 Turbo 或真实写入 SMC。
- 记录低频本地性能标记，用于将窗口、曲线和时间范围状态与 CPU、内存观测对齐。
- 普通逻辑测试，以及需要显式选择的当前 Mac 只读硬件探测测试。

当前不包含逐 key 传感器中文语义确认、真实 SMC 写入、已通过实机验收的 Turbo、安装包或发布版本。LaunchDaemon 升级、root 启动和最终 helper 的双向签名 XPC 已在当前开发机实际验证，但不能替代手动模式、最大目标、实际 RPM 和恢复 automatic 的实机读回。加速数据测试已经覆盖 312 个序列的 1 小时容量边界，Debug App 已完成 3605 秒压力运行，最终 Release App 也已完成 3605 秒真实运行并取得 60 个连续监督样本。当前 Mac16,7 上，`Tp` 温度族平均值已通过短时 CPU 负载响应验证。

## 安全边界

- 默认状态永远是苹果自动风扇控制。
- 普通监控不要求 root，不写任何 SMC 值。
- `Tp` 只作为当前机器有负载响应证据的 P 核温度候选族；单个温度 key 仍只显示原始名称，不会被猜成具体核心或硬件部件。
- 当前机器的只读验证不能代表其他 Apple Silicon 机型已经受支持。
- Turbo 写入路径已在源码中按最小权限设计、实现并完成 helper 系统升级，但在真实模式、目标、实际 RPM 和恢复 automatic 读回前不视为验收通过。
- App 使用 `io.github.iyuenan3.thermalpulse`，helper 与 Mach service 使用 `io.github.iyuenan3.thermalpulse.helper`。双方从自身有效签名动态取得 Team ID，并同时校验 Apple 签名锚点、固定 identifier 和相同 Team ID；未签名构建拒绝建立 XPC 信任。

完整产品边界、架构和决策见 [`AIREADME/`](AIREADME/INDEX.md)。

## 本地构建

需要 Xcode 26.6。ThermalPulse 只支持 macOS 26.0 或更高版本。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ThermalPulse.xcodeproj \
  -scheme ThermalPulse \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/thermal-pulse-derived \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  build
```

普通测试默认不会访问真实 AppleSMC：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
  -project ThermalPulse.xcodeproj \
  -scheme ThermalPulse \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/thermal-pulse-derived \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  test
```

不要为了构建修改全局 `xcode-select`。真实硬件探测的独立命令与证据边界见 [`AIREADME/DEPLOYMENT.md`](AIREADME/DEPLOYMENT.md)。

## 本地性能标记

性能事件使用 `ThermalPulse:MonitoringPerformance` 分类写入 macOS 统一日志。只记录样本数、曲线数量、时间范围和界面状态，不记录设备标识或原始 SMC key。

```bash
/usr/bin/log stream --style compact \
  --predicate 'subsystem == "ThermalPulse" AND category == "MonitoringPerformance"'
```
