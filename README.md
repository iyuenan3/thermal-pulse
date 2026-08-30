# ThermalPulse

ThermalPulse 是一个原生 macOS 本地热状态监控工具。目标是像活动监视器一样展示温度候选、风扇 RPM 和系统 thermal state，并在通过实机安全验收后提供用户显式触发、固定 600 秒、失效自动恢复的 Turbo 散热。

## 当前状态

项目处于 pre-alpha，当前支持 macOS 26 及以上的 Apple 芯片 MacBook Pro：

- 菜单栏左列上下显示 P 核与 E 核热点温度，右列按动态风扇数量显示实际 RPM。单风扇垂直居中，双风扇上下排列。
- 点击菜单栏图标即可一次看到 P 核、E 核、电池温度、5 分钟温度曲线、系统 thermal state 和全部风扇，无独立监控窗口。
- 普通权限只读 AppleSMC，每秒采样一次，每个序列最多保存 1 小时内存历史。
- 核心温度使用动态 `Tp*` 与 `Te*` 候选族，不硬编码机型 key，也不把单个 key 猜成具体核心。
- Turbo 源码只提供固定 600 秒全速、主动停止和失效恢复，不接受任意 RPM、时长或 SMC key。

Mac16,7、Apple M4 Pro 已验证双风扇监控和一次短时 Turbo；Mac17,2、Apple M5 已验证单风扇只读监控。其他 Apple 芯片 MacBook Pro 仍需要实机证据，不能从这两台机器直接外推。

## 安全边界

- 默认状态永远是苹果自动风扇控制。
- 普通监控不要求 root，不写任何 SMC 值。
- P 核、E 核只使用当前机器有效且合理的温度候选族；单个温度 key 不会被猜成具体核心身份。
- 两台机器的验证不能代表全部 Apple 芯片 MacBook Pro 已经通过。
- Turbo 写入路径按最小权限设计，必须在目标机型上分别取得模式、目标、实际 RPM 与恢复苹果控制的真实读回。
- App 使用 `io.github.iyuenan3.thermalpulse`，helper 与 Mach service 使用 `io.github.iyuenan3.thermalpulse.helper`。Developer Team 构建继续校验 Apple 签名锚点、固定 identifier 和相同 Team ID；当前协议 v8 源码为 ad hoc 分发增加管理员安装路径，把 App/helper 的固定路径与精确 CDHash 写入 root-owned manifest。任一路径都不接受仅凭 bundle identifier 的调用方。

完整产品边界、架构和决策见 [`AIREADME/`](AIREADME/INDEX.md)。

## 下载与安装

从 [GitHub Releases](https://github.com/iyuenan3/thermal-pulse/releases) 下载 `ThermalPulse-v0.1.1-macos-arm64.dmg`，打开后把 ThermalPulse 拖入 Applications。

`v0.1.1` 是由 GitHub Actions 构建的 ad hoc 签名预发布测试版，未经过 Apple 公证。首次启动可在 Finder 中右键点击 App，然后选择“打开”。普通只读监控不需要管理员权限。

要测试 Turbo，先确认没有其他风扇控制 App 正在使用手动模式，再在 ThermalPulse 面板中点击“打开管理员安装器”。Terminal 安装器只接受 `/Applications/ThermalPulse.app`，会请求管理员密码，并把当前 App 与受限 helper 的代码哈希固定到 root-owned manifest。安装完成后回到 App 点击“重新检查状态”。安装本身不会启动 Turbo，也不会写入 SMC。

协议 v8 的管理员安装、XPC 和真实 Turbo 尚未完成本版本的系统级验收。`v0.1.1` 只作为用户自行安装测试的候选版本，不代表其他 Apple 芯片 MacBook Pro 已通过 Turbo 验收。遇到任何身份、连接或读回异常时，Turbo 应保持不可用。

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
