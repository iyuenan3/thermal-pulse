# DEPLOYMENT：ThermalPulse

## 主机 + 环境

计划运行在带主动散热的 Apple Silicon Mac。首台开发与验收机为 Mac16,7、Apple M4 Pro；其他机型必须经过只读探测与真实写入验收后再加入支持矩阵。

最低系统正式设为 macOS 26.0，不支持 macOS 25 及更早版本。工程的 Debug、Release 和 HardwareProbe configuration 统一使用 `MACOSX_DEPLOYMENT_TARGET = 26.0`，以 Xcode 26.6 构建和测试。

## 怎么起

当前同时支持关闭代码签名的本地测试构建，以及使用当前开发机免费 Personal Team 的本机开发签名构建，不提供安装包。App bundle identifier 已固定为 `io.github.iyuenan3.thermalpulse`，helper identifier 与 Mach service 已固定为 `io.github.iyuenan3.thermalpulse.helper`。工作区 App bundle 已包含带受限写入链路的 helper executable 和 LaunchDaemon plist；同一签名产物已在当前开发机完成系统升级并由 ServiceManagement 运行。启动 App 只查询注册状态，显式注册或升级都不会自动启动 Turbo 或写 SMC。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ThermalPulse.xcodeproj -scheme ThermalPulse -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/thermal-pulse-derived CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

普通单元测试默认跳过真实硬件探测：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project ThermalPulse.xcodeproj -scheme ThermalPulse -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/thermal-pulse-derived CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test
```

需要在当前机器显式验证 AppleSMC 只读链路时，使用独立 scheme：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ThermalPulse.xcodeproj -scheme ThermalPulseHardwareProbe -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/thermal-pulse-derived CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -only-testing:ThermalPulseTests/SMCReadAdapterIntegrationTests test
```

该命令必须保留 scheme 自带的 HardwareProbe configuration。不要额外传入 `-configuration Debug`，否则硬件测试会按普通测试策略跳过。

所有命令只对单次调用设置 `DEVELOPER_DIR`，不得修改全局 `xcode-select`。

当前开发机登录相应 Apple Account 后，可使用项目内已配置的 Automatic Signing 做本机签名构建。本文不记录实际 Team ID：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ThermalPulse.xcodeproj -scheme ThermalPulse -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/thermal-pulse-personal-team-derived ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -allowProvisioningUpdates build
```

## 域名 / 入口

N/A。项目是本地菜单栏 App，不提供服务器、域名、远程访问或后台上传。

## helper 注册与运行

- 已验证的 bundle 布局为 `Contents/Resources/ThermalPulseHelper` 与 `Contents/Library/LaunchDaemons/io.github.iyuenan3.thermalpulse.helper.plist`。plist 的 `BundleProgram` 指向前者，`Label` 与唯一 Mach service 均为 helper identifier。
- helper 随签名 App Bundle 分发，使用 `SMAppService.daemon(plistName:)` 查询和注册 LaunchDaemon。当前实现把 `notRegistered` 与系统尚未记录服务时的 `notFound` 都映射为可注册状态；待批准时提供系统设置入口，只有 `enabled` 才连接 XPC。旧 helper 返回 write-path-unavailable 时，App 只在用户再次确认后失效旧 XPC，等待异步 `unregister()` 完成，再注册当前签名版本。
- 普通监控不依赖 helper。只有用户首次使用 Turbo 时才引导注册和批准。
- helper 以 root 权限运行，但接口仅覆盖固定 Turbo 租约，不承担采样、图表或网络职责。
- 持久租约路径固定为 `/Library/Application Support/ThermalPulse/turbo-lease.plist`。目录权限为 0755，租约文件权限为 0600；内容不含设备标识、RPM、凭证或用户数据。只有全部自动模式读回确认后才删除。
- App 与 helper 使用同一实际签名的 Team ID。App 要求 helper 满足 Apple 签名锚点、固定 helper identifier 与相同 Team ID；helper 对 App 执行对称校验。未签名构建无法取得可信 Team ID，因此拒绝 XPC 连接。
- helper executable 嵌入由 Xcode 生成的 Info.plist section，以保证裸 Mach-O 的代码签名 identifier 与 `PRODUCT_BUNDLE_IDENTIFIER` 一致。ad hoc 构建已完成 identifier 读回和 App deep strict 校验，但因没有 Team ID 只能证明 identity 布线正确，不能证明双向签名连接通过。
- 用户自用阶段已在 Xcode 中登录 Apple Account，并为 App 与 helper 配置同一个免费 Personal Team。Personal Team 的 App ID 与配置描述文件存在短期有效期限制，不作为发布方案；Developer ID 分发与公证需要付费 Apple Developer Program，当前不进入范围。
- 2026-08-29 较早的本机 Debug 签名基线实际读回 App 与 helper 的固定 identifier 和相同非空 Team ID，并由完整 Apple Development 证书链通过 App bundle 的 deep strict 验证。随后用户显式完成注册和系统允许，系统读回 LaunchDaemon 由 ServiceManagement 管理、root 运行且 XPC 活跃；App 收到旧安全 stub 的 write-path-unavailable，证明注册与双向签名 XPC 实连。
- Xcode 26.6 本机 SDK 明确要求包含 LaunchDaemon 的 App 完成公证。Personal Team 构建不作为发布方案，`spctl` 与 notarized 签名 requirement 仍未通过。
- 加入真实写入源码后的最终 Personal Team Debug 构建由 Xcode 成功产出。同一 App 与 helper 在沙箱外分别通过 `codesign --verify --deep --strict` 和 `codesign --verify --strict`。2026-08-29 用户明确授权升级但不启动 Turbo 后，旧安全 stub 被注销，当前签名版本完成重新注册；系统读回新 root helper 由 ServiceManagement 管理、Mach endpoint 活跃，App 通过 XPC 取得无错误 inactive 状态。升级前后租约文件均不存在，升级后只读硬件探测 57 项全部通过，`F0Md`、`F1Md` 与 `Ftst` 继续为 0。
- 2026-08-30 用户明确授权一次短时 Turbo 实机测试。启动前专用只读门禁通过；helper 随后以 readback mismatch 返回 failed-safe-auto，没有进入 active，也没有自动重试。失败后租约文件不存在，独立 HardwareProbe 再次通过并读回 `F0Md=0`、`F1Md=0`、`Ftst=0`、`F0Ac=1350.73 RPM`、`F1Ac=1462.07 RPM`，两个目标值已回到苹果自动控制值。系统仍读回同一 root helper 与活跃 Mach endpoint。本次只确认失败保护后的 automatic 恢复，未确认最大目标或 Turbo active。

## 备份 / 升级 / 回滚

- 首版不自动持久化传感器历史，因此没有用户数据备份要求。
- 升级前若存在 ThermalPulse 租约，必须先恢复自动模式并确认读回，再替换 App 或 helper。
- 更新已注册 helper 时必须先失效旧 XPC，并等待 `SMAppService` 异步注销完成后再注册当前签名版本。禁止同步注销后立即重注册，也禁止用手工 `launchctl` 或直接覆盖系统文件绕过 ServiceManagement。
- 卸载顺序必须是停止 Turbo、恢复自动、注销 helper、确认服务停止，最后移除 App。
- helper 更新失败时回滚到已签名的兼容版本；无法确认兼容时禁用 Turbo，但保留只读监控。
- 具体安装、升级、卸载和回滚命令必须在真实签名构建验证后补充，禁止把未经验证的 sudo 命令写成操作手册。

## 运维约束

- 不创建网络监听端口，不上传遥测。
- 不在无人值守条件下自动启用 Turbo。
- 不在休眠唤醒后自动续跑 Turbo。
- 不与其他风扇控制工具争抢手动控制权，发现外部手动模式时拒绝启动。
- 任何 helper 注册、授权或系统级安装验收都需要用户知情，并与普通构建测试分开报告。
