# ThermalPulse

ThermalPulse 是一个原生 macOS 本地热状态监控工具。目标是像活动监视器一样展示温度候选、风扇 RPM 和系统 thermal state，并在后续提供用户显式触发、固定 600 秒、失效自动恢复的 Turbo 散热。

## 当前状态

项目处于 pre-alpha。当前切片已经包含：

- 原生 SwiftUI 菜单栏 App 与监控窗口壳。
- 普通权限只读 AppleSMC adapter。
- 动态 key 和风扇枚举、typed sensor model、数据类型解码与有效性判断。
- 启动时建立动态采样白名单，之后以 1 Hz 读取有效风扇实际转速和温度候选。
- 每个传感器最多保存 3600 个内存样本，并展示最新值、最小值、最大值和平均值。
- 普通逻辑测试，以及需要显式选择的当前 Mac 只读硬件探测测试。

当前不包含曲线绘制、传感器中文语义确认、SMC 写入、privileged helper、Turbo、签名、安装包或发布版本。

## 安全边界

- 默认状态永远是苹果自动风扇控制。
- 普通监控不要求 root，不写任何 SMC 值。
- 未确认语义的温度 key 只显示在高级原始候选视图，不会被猜成确定硬件部件。
- 当前机器的只读验证不能代表其他 Apple Silicon 机型已经受支持。
- Turbo 写入路径会在只读监控稳定后单独设计、实现和验收。

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
