# DEPLOYMENT：ThermalPulse

## 主机 + 环境

计划运行在 Apple Silicon MacBook Pro。Mac16,7、Apple M4 Pro 是首台开发与 Turbo 验收机；Mac17,2、Apple M5 是第二台只读监控与单风扇布局验收机。其他 Apple Silicon MacBook Pro 必须先经过只读探测，Turbo 还需独立真实写入与恢复验收后才能加入对应支持矩阵；其他 Mac 产品线当前不在范围内。

最低系统正式设为 macOS 26.0，不支持 macOS 25 及更早版本。工程的 Debug、Release 和 HardwareProbe configuration 统一使用 `MACOSX_DEPLOYMENT_TARGET = 26.0`，以 Xcode 26.6 构建和测试。

## 怎么起

当前支持关闭代码签名的本地测试构建、Personal Team 本机签名构建，以及 v0.0.1 GitHub Actions DMG 预览包。App bundle identifier 已固定为 `io.github.iyuenan3.thermalpulse`，helper identifier 与 Mach service 已固定为 `io.github.iyuenan3.thermalpulse.helper`。2026-08-30 协议 v6 Personal Team Debug helper 已由用户显式升级，并完成快速 `Ftst` 接管、短时 active、实际 RPM 上升和主动停止恢复读回；系统当前仅保留该 v6 root helper，本机 App 已退出，租约目录为空。代码审查后的 v7 只完成源码、测试、签名构建与只读恢复门禁，没有升级系统 helper 或执行新的 Turbo。公开 DMG 不替代 Personal Team 本机验收，也不代表 Developer ID、公证或其他机型 Turbo 已通过。

第二台 M5 验收机只从一次性 `/private/tmp` 工作目录构建和启动无签名 Debug App，没有复制到 Applications、注册登录项或安装 helper。该 App 已创建菜单栏状态项并完成首次只读扫描；无签名构建按设计不能连接 privileged helper。2026-08-31 已按用户要求发送正常退出信号，并复查确认没有残留 ThermalPulse 进程。临时运行不等于安装或分发验收。

### GitHub Actions DMG 发布

- 推送与工程 `MARKETING_VERSION` 一致的 `vX.Y.Z` tag 时，`.github/workflows/release.yml` 在 GitHub 官方 `macos-26` Apple Silicon runner 上运行。当前 runner 为 arm64，并以 Xcode 26.6 为默认版本。
- 工作流先执行普通测试，再构建 macOS 26 arm64 Release App。真实 AppleSMC 硬件测试不会在云端隐式运行。
- App 和内嵌 helper 使用 ad hoc 签名完成 bundle 完整性校验，然后打包为 `ThermalPulse-vX.Y.Z-macos-arm64.dmg`。工作流会校验 App 版本、deep strict 签名、DMG CRC、只读挂载结果、arm64 App 存在性，并生成 SHA-256 文件。
- GitHub Release 标记为 prerelease。公开 runner 没有 Developer ID 证书和私钥，产物未经公证，也没有可信 Team ID；普通监控可用，Turbo 必须按现有签名门禁保持不可用。禁止为让公开包启用 Turbo 而放宽 XPC 双向签名要求。
- v0.0.1 的 GitHub Actions run `33323101547` 已成功完成。Release API 读回非 draft prerelease 和两个 uploaded 资产；重新下载后，DMG 的 SHA-256、CRC、挂载内容、deep strict 完整性、版本与 arm64 架构均通过独立复验。

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
- helper 随签名 App Bundle 分发，使用 `SMAppService.daemon(plistName:)` 查询和注册 LaunchDaemon。当前实现把 `notRegistered` 与系统尚未记录服务时的 `notFound` 都映射为可注册状态；待批准时提供系统设置入口，只有 `enabled` 才连接 XPC。旧 helper 返回 write-path-unavailable 或协议不兼容时，App 只在用户再次确认后失效旧 XPC，等待异步 `unregister()` 完成，并连续观察未注册状态稳定后注册一次当前签名版本。
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
- 随后的第二次短测中，风扇短时转动后被系统接管，helper 到期恢复持续失败，root lease 仍存在。独立只读复验为 `F0Md=3`、`F1Md=3`、`Ftst=0`、目标和实际 RPM 全部为 0，说明当前硬件已由苹果 system 模式接管，但 helper 的恢复完成与 lease 清理没有验收通过。工作树现已加入 mode 3 恢复、`Ftst` 所有权先持久化和 300 毫秒 active 协调，协议 v3 的 Personal Team 签名构建及 strict 校验均已通过。当前不允许再次启动 Turbo，直到用户显式升级 helper 且不启动 Turbo，并确认旧 lease 删除、两台风扇为 Apple 管理模式、`Ftst=0` 与实际 RPM 有效。
- 用户随后完成协议 v3 helper 升级，旧租约被清除且当时只读门禁通过。最新一次启动尝试暴露 `Ftst` 异步生效时序：helper 在写 1 后立即读到旧值 0，恢复又在真正生效前跳过清除并删除租约。当前独立只读结果为两台风扇 mode 0、`Ftst=1`、租约文件不存在。工作树已升级协议 v4，写 1 和写 0 后都等待 3 秒稳定读回；67 项普通测试通过、4 项硬件测试按设计跳过，Personal Team Debug 构建和 strict 同 Team 校验通过。当前仍禁止启动 Turbo，先以单独授权恢复 `Ftst=0` 并只读确认，再由用户在 App 内显式升级 v4 helper。
- 重启恢复 `Ftst=0` 后，用户从 `notRegistered` 状态显式注册包含稳定替换门禁的协议 v4 helper。统一日志读回 `SMAppService.register()` 成功，launchd 读回服务由 ServiceManagement 管理、root 运行且 Mach endpoint 活跃；App 与 helper 已建立双向签名约束 XPC。租约不存在。注册后 HardwareProbe 共 4 项，3 项通过、1 项 Turbo active 读回按设计跳过；定向门禁读回风扇 0 和风扇 1 均为 mode 3，`Ftst=0` 断言通过。没有调用 `startTurbo()`，没有写 SMC，也没有重新执行已注册 helper 的替换路径。
- 随后一次用户授权的 v4 短测进入 active。独立读回 `Ftst=1`、两台风扇 mode 1、目标原始字节等于动态 5777 RPM 最大值，实际样本分别约为 5701 至 5855 RPM、5775 至 5778 RPM。主动停止后两台风扇 mode 3、`Ftst=0`、lease 不存在，helper 记录无错误恢复。工作树已把实际 RPM 可信上限调整为动态最大值 105%，修复 active 文案并升级协议 v5；v5 签名产物已验证，但未调用 `SMAppService` 升级，也未再次启动 Turbo。
- 用户随后从唯一运行的 v5 Personal Team 签名 App 完成 helper 升级并确认验收通过。升级后 App 与 helper 进程均来自指定 v5 构建，`launchctl` 读回新的 root helper 由 ServiceManagement 管理、Mach endpoint 活跃，租约目录为空。本轮独立读回不包含再次启动 Turbo、模式、目标或实际 RPM，因此不替代此前 v4 短测，也不覆盖故障恢复路径。
- 随后工作树将启动时 `Ftst=1` 的固定 3 秒等待改为 100 毫秒轮询、连续两次稳定读回和 3 秒失败上限，并把私有 XPC 协议升级为 v6。Personal Team Debug App 与内嵌 v6 helper 通过 strict 签名校验后，用户显式完成 helper 升级和一次短时 Turbo。日志显示从 `activation_started` 到 `thermal_manager_unlock_claimed` 约 0.98 秒，从启动到实际 RPM 上升确认约 8.78 秒；两台风扇当时分别约为 1321 RPM 和 1423 RPM，动态最大值均为 5777 RPM。用户主动停止后 helper 记录 `restoration_completed issue=none`，租约目录为空；后续独立只读门禁 1 项通过，确认两台风扇为 Apple 管理且 `Ftst=0`。该证据不覆盖 600 秒到期、App 崩溃、XPC 断开、helper 重启或休眠恢复。
- 对 v6 基线的代码审查发现恢复失败重试、未知 `Ftst` 写入和并发 XPC 请求隔离缺口。提交 `934721e` 修复这些问题并将协议提升到 v7。完整普通测试 74 项通过、4 项真实硬件测试按设计跳过，Personal Team v7 App 与内嵌 helper 均通过 strict 签名校验。当前系统仅运行 v6 helper，v6 App 已退出；本轮没有调用 `SMAppService` 升级、没有启动 Turbo，也没有写 SMC。未来首次运行 v7 App 时会按协议不兼容禁用 Turbo，必须由用户单独确认升级 helper。

## 备份 / 升级 / 回滚

- 首版不自动持久化传感器历史，因此没有用户数据备份要求。
- 升级前若存在 ThermalPulse 租约，必须先独立确认硬件处于 Apple 管理模式。修复恢复逻辑的 helper 升级可以用于清理已确认安全但卡住的旧 lease，升级动作本身不得启动 Turbo。无租约 `Ftst=1` 不能假定属于 ThermalPulse，也不能依赖 helper 升级自动清除，必须以本次日志证据和用户独立授权执行窄范围恢复。
- 更新已注册 helper 时必须先失效旧 XPC，等待 `SMAppService` 异步注销完成，并连续观察状态稳定为未注册后再注册一次当前签名版本。失败后回到只读状态，不自动重试；禁止用手工 `launchctl` 或直接覆盖系统文件绕过 ServiceManagement。
- 卸载顺序必须是停止 Turbo、恢复自动、注销 helper、确认服务停止，最后移除 App。
- helper 更新失败时回滚到已签名的兼容版本；无法确认兼容时禁用 Turbo，但保留只读监控。
- 具体安装、升级、卸载和回滚命令必须在真实签名构建验证后补充，禁止把未经验证的 sudo 命令写成操作手册。

## 运维约束

- 不创建网络监听端口，不上传遥测。
- 不在无人值守条件下自动启用 Turbo。
- 不在休眠唤醒后自动续跑 Turbo。
- 不与其他风扇控制工具争抢手动控制权，发现外部手动模式时拒绝启动。
- 任何 helper 注册、授权或系统级安装验收都需要用户知情，并与普通构建测试分开报告。
