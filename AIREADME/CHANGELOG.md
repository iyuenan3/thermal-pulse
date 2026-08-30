# CHANGELOG：ThermalPulse

> append-only，版本块倒序。这里只记录 release 或明确里程碑，原因指向 DECISIONS，未来方向写入 ROADMAP。

当前已发布版本为 v0.1.0。

## v0.1.1 · 协议 v8 管理员安装测试候选 · 2026-08-31

### Added

- 公开 ad hoc 构建加入用户显式打开的管理员安装器、固定路径 LaunchDaemon plist 和 root-owned 安装身份 manifest。
- App 与 helper 在没有 Team ID 时使用固定 identifier 与精确 CDHash 双向校验；具备 Developer Team 时继续使用 Apple 签名锚点与同 Team 路径。

### Changed

- 工程 `MARKETING_VERSION` 升级为 `0.1.1`，build number 升级为 3，私有 XPC 协议升级为 v8。
- GitHub Actions 使用 hardened runtime ad hoc 签名，并在发布成功后只删除其他 Release 中匹配版本化命名规则的 DMG 与 `.sha256`；旧 Release 页面和 tag 保留。

### Release gates

- 普通测试、macOS 26 arm64 Release 构建、安装器 `bash -n`、手动 plist lint、App/helper deep strict、固定 identifier 与精确 CDHash requirement、DMG CRC、只读挂载、版本和 arm64 架构必须全部通过。
- Release 保持 prerelease，并明确标注 ad hoc、未公证、首次和每次升级需要管理员重新固定哈希。

### Validated

- 本地普通测试共执行 83 项，79 项通过、4 项真实硬件测试按设计跳过、0 项失败。
- 本地 macOS 26 arm64 Release 构建通过。临时 DMG 完成 hardened runtime ad hoc 签名、双方 40 位 CDHash requirement、CRC、只读挂载、版本 `0.1.1 (3)`、AppIcon 与 arm64 主程序回读。
- 本地测试 DMG 为 4,202,360 字节，SHA-256 为 `ba68fb553ca2ab5a012b1a807175790f461205a9e482f587484aa7a016c9a521`。该值只对应本地临时产物，官方 GitHub Actions 资产必须发布后重新下载并独立计算。

### Not included

- 发布过程不执行 sudo，不写入 `/Library`，不登记或替换系统 helper，不连接 root XPC，不启动 Turbo，也不写 SMC。
- v0.1.1 是用户自行安装测试候选。CI 与 DMG 回读不代表管理员安装、XPC inactive、真实 Turbo、失败回滚或安全卸载已经验收。

## Unreleased · ad hoc Turbo helper 安装身份 · 2026-08-31

### Added

- 新增协议 v8 的管理员安装路径。公开 ad hoc App 可显式打开 Terminal 安装器，把受限 helper、固定 `ProgramArguments` LaunchDaemon plist 和安装身份写入标准 root 路径。
- 新增 root-owned manifest，记录固定 App/helper identifier、安装路径、20 字节 CodeDirectory hash 和可执行文件 SHA-256。App 与 helper 分别校验自身身份后，要求 peer 满足固定 identifier 与精确 CDHash。
- 保留 Developer Team 构建的同 Team `SMAppService` 路径；没有 Team ID 时才选择管理员安装路径。

### Changed

- 私有 XPC 协议从 v7 提升到 v8，旧 helper 不会被新 App 当成兼容实现。
- GitHub Actions 发布构建改用 hardened runtime ad hoc 签名，并新增安装器语法、手动 plist、双方 identifier 与 CDHash requirement 校验。未来 Release 说明会明确未公证、管理员安装和每次更新重新固定哈希的限制。

### Validated

- macOS 26 arm64 无签名 Debug 构建通过，普通测试在沙箱外通过。
- `Install Turbo Helper.command` 通过 `bash -n`，手动 LaunchDaemon plist 通过 `plutil -lint`，App 构建资源读回安装器为可执行文件。
- 临时 App/helper 使用 hardened runtime ad hoc 重签后通过 deep strict 校验；双方实际 CDHash 均为 40 位，固定 identifier 与精确 CDHash requirement 的双向 `codesign --verify -R` 验证通过。

### Not included

- 本轮没有运行 sudo 安装器，没有写入 `/Library`、登记或替换 launchd 服务、连接 root helper、启动 Turbo、写 SMC、提交、push 或发布新版本。
- 管理员安装、失败回滚、XPC inactive、真实 Turbo 与安全卸载仍需分别验收；已发布 v0.1.0 不会因此获得 Turbo。

## v0.1.0 · 正式 App 图标 · 2026-08-31

### Added

- 新增用户确认的 ThermalPulse 正式 App 图标，以温度脉冲和三叶风扇作为单一识别符号。
- 新增 macOS AppIcon Asset Catalog，覆盖 16、32、128、256、512 pt 的 1x 与 2x 槽位，所有 PNG 均保留透明边角。

### Changed

- 工程 `MARKETING_VERSION` 升级为 `0.1.0`，build number 升级为 2；README 下载入口和 GitHub Release 说明同步更新。

### Validated

- 普通测试共 80 项，76 项通过、4 项真实硬件测试按设计跳过、0 项失败。
- macOS 26 arm64 Release App 构建通过，Info.plist 读回版本 `0.1.0 (2)` 与 `CFBundleIconName=AppIcon`，资源目录生成 `AppIcon.icns` 和 `Assets.car`，主可执行文件读回 arm64。
- 本地同口径测试 DMG 完成 helper 与 App ad hoc 签名、deep strict 校验、CRC、只读挂载、Applications 快捷入口、图标、版本和 arm64 架构复验。

### Published

- GitHub Actions run `33324533793` 在 tag commit `cf85878` 上完成全部步骤并返回 success，Release API 读回 v0.1.0 为非 draft 的 prerelease。
- Release 包含 `ThermalPulse-v0.1.0-macos-arm64.dmg` 和对应 `.sha256` 文件。GitHub 记录的 DMG 大小为 4,195,525 字节，SHA-256 为 `f5f4487904e2660fddf37568b0aa97ffd28b8290759a2a5b63ca97129af2afff`。
- 从 GitHub Release 重新下载两个资产后，SHA-256 文件校验、DMG CRC、只读挂载、Applications 快捷入口、`AppIcon.icns`、版本 `0.1.0 (2)`、deep strict 完整性与 arm64 Mach-O 读回全部通过。
- v0.1.0 验证通过后，按用户确认的保留策略删除 v0.0.1 的旧 DMG 和 `.sha256`。API 回读 v0.0.1 资产列表为空，旧 Release 页面与 tag 保留。

### Not included

- 本版本仍未使用 Developer ID 签名或 Apple 公证，公开 DMG 的 Turbo 按既有非空同 Team 门禁保持不可用。
- 本轮没有升级系统 helper、启动 Turbo 或执行新的真实 SMC 写入。

## v0.0.1 · 首个公开 DMG 预览版 · 2026-08-31

### Added

- 新增由 `vX.Y.Z` tag 触发的 GitHub Actions 发布流程，使用 macOS 26 arm64 runner 构建 `ThermalPulse-vX.Y.Z-macos-arm64.dmg`，见 ADR-036。
- 工程加入 `MARKETING_VERSION=0.0.1` 与 build number 1。工作流强制 tag 与工程版本一致，并同时发布 DMG 的 SHA-256 文件。
- DMG 包含 ThermalPulse App 与 Applications 快捷入口。发布门禁包含普通测试、Release 构建、App 和 helper ad hoc 签名、deep strict 校验、DMG CRC、只读挂载、App 版本和 arm64 架构读回。

### Included

- macOS 26 及以上 Apple 芯片 MacBook Pro 的菜单栏只读监控。
- P 核、E 核热点、电池平均温度、固定 5 分钟曲线、系统 thermal state，以及动态单风扇或双风扇 RPM 展示。

### Published

- GitHub Actions run `33323101547` 在 tag commit `1e60cc9` 上完成全部步骤并返回 success，Release API 读回 v0.0.1 为非 draft 的 prerelease。
- Release 包含 `ThermalPulse-v0.0.1-macos-arm64.dmg` 和对应 `.sha256` 文件。GitHub 记录的 DMG 大小为 1,009,631 字节，SHA-256 为 `c7bffd934a18cf4b3a1162e161e8cf0db8193b71fc3f2f0521e2198a8a713f0d`。
- 从 GitHub Release 重新下载两个资产后，SHA-256 文件校验通过；DMG CRC、只读挂载、App deep strict 完整性、版本 `0.0.1` 与 arm64 Mach-O 读回全部通过。

### Not included

- 公开 runner 没有 Developer ID 证书、私钥和公证凭证。v0.0.1 DMG 使用 ad hoc 签名且未公证，没有可信 Team ID，因此 Turbo 按安全设计不可用。
- 本版本不代表 M5 Turbo、全部故障恢复场景或其他 Apple 芯片 MacBook Pro 已通过实机验收。

## Unreleased · Apple Silicon MacBook Pro 单风扇适配 · 2026-08-30

### Changed

- 当前产品范围收敛为 macOS 26 以上 Apple Silicon MacBook Pro。监控使用动态能力发现，不按 M4、M5 或机型 identifier 保存风扇数量、温度 key 和 RPM 表，见 ADR-035。
- 菜单栏左列继续上下显示 P/E 核热点。右列动态枚举到 0 或 1 台风扇时显示一个垂直居中的占位或转速，2 台及以上时上下显示前两台，完整风扇列表继续保留在展开面板和辅助功能描述。
- HardwareProbe 温度刻画移除 M4 Pro 专属候选 key 表，改为复用产品的动态 `Tp*` 与 `Te*` 族级策略。

### Validated

- 第二台 Mac17,2、Apple M5 MacBook Pro 普通权限探针读回 2778 个 SMC key、1 台风扇、小写 `F0md`、6550 RPM 动态最大值、14 个有效 `Tp` 候选、4 个有效 `Te` 候选和两枚电池温度。单风扇探针与 12 秒温度族刻画分别通过。
- 临时无签名 App 在 M5 登录桌面成功创建菜单栏状态项，首次扫描完成并选择 P 核、E 核和电池三条曲线。无签名构建不能连接 helper，未写 SMC。
- Mac16,7、Apple M4 Pro 与 Mac17,2、Apple M5 的完整普通测试均为 80 项，其中 76 项通过、4 项真实硬件测试按设计跳过、0 项失败。M5 无签名 Debug App 构建成功。

### Not included

- M5 探测时风扇已处于外部 manual mode 1。本轮没有识别或停止外部控制工具，没有注册、升级或连接 helper，也没有尝试 Turbo。
- 当前证据不代表其他 Apple Silicon MacBook Pro 已验收，也不代表 M5 的 Turbo、停止或故障恢复通过。

## Unreleased · Turbo v6 实机短测与 v7 安全审查 · 2026-08-30

### Changed

- 协议 v6 helper 已由用户显式升级。快速接管短测中，`Ftst` 从启动到连续稳定读回约 0.98 秒；从启动到两台风扇实际 RPM 上升确认约 8.78 秒，说明剩余等待主要来自物理起转和实际 RPM 安全门禁，而不是固定租约等待。
- 代码审查后把私有协议提升到 v7。failed-safe-auto 且租约仍存在时，300 毫秒看门狗会在下一 tick 立即重试恢复，不再等待原始 600 秒截止时间；未知 `Ftst` 直接拒绝启动且不得写解锁 key。
- App 的持久 XPC transport 改为按请求身份跟踪 continuation 和超时，状态查询与停止可以并发存在；取消后的状态轮询不能覆盖主动停止结果。
- 菜单栏模板图片只显示动态枚举结果中的前两台风扇，超过两台时完整信息继续保留在展开面板和辅助功能描述，不再扩张常驻状态项。

### Validated

- v6 短测进入 active。两台风扇从 0 RPM 基线分别上升到约 1321 RPM 和 1423 RPM，动态最大值均为 5777 RPM；用户主动停止后 helper 记录 `restoration_completed issue=none`，租约目录为空。
- 事后独立只读恢复门禁 1 项通过，确认两台风扇处于 Apple 管理模式且 `Ftst=0`。该用例使用 scheme 自带的 HardwareProbe configuration，没有被普通 Debug 配置跳过。
- v7 完整普通测试共 78 项，74 项通过、4 项真实硬件测试按设计跳过、0 项失败。Turbo 安全、协调器与 XPC 协议定向测试 45 项全部通过。
- macOS 26 arm64 Personal Team v7 签名构建成功，App bundle 与内嵌 helper 分别通过 strict 签名校验。

### Not included

- 当前已注册 helper 和运行 App 仍为协议 v6。本轮没有升级 v7 helper、启动新的 Turbo 或写 SMC。
- v6 短测只覆盖快速接管、active 和用户主动停止。600 秒到期、App 崩溃、XPC 断开、helper 重启和休眠唤醒恢复仍未完成独立实机验收。

## Unreleased · faster Turbo claim and 10 pt status summary · 2026-08-30

### Changed

- 菜单栏 P/E 与双风扇摘要从 22 pt 高、9.5 pt 字形小幅上调为 23 pt 高、10 pt 字形和 11.5 pt 行高，布局与动态枚举不变，见 ADR-032 Follow-up。
- Turbo 写入 `Ftst=1` 后不再固定白等 3 秒，改为每 100 毫秒读回，连续两次为 1 就继续，3 秒作为失败上限。恢复时的 `Ftst=0` 仍保留原有 3 秒稳定窗口，模式、最大目标与实际 RPM 门禁不变，见 ADR-033。
- Turbo 启动中文案改为“正在接管并等待风扇起转”，区分安全状态读回与风扇物理起转。
- 私有协议从 v5 提升到 v6，确保当前 App 会拒绝仍使用固定等待逻辑的旧 helper，并引导用户显式升级。

### Validated

- 优化前的 `TurboSafetyControllerTests` 基线在沙箱外通过；优化后的 Turbo 安全控制器与 XPC 协议定向测试共 29 项全部通过，0 失败、0 跳过。新用例自证 100 毫秒轮询和连续两次稳定读回真实执行，并验证超时时没有碰风扇、租约可安全清理。
- macOS 26 arm64 Personal Team 签名 v6 构建通过，App 与内嵌 helper 均通过 strict 签名校验。新 App 已作为唯一 ThermalPulse 实例启动，真实菜单栏截图读回 `P64°`、`E50°` 与两台风扇数值，四项完整无裁切；当前系统 v5 helper 保持不变并被 v6 App 按协议不兼容拒绝。

### Not included

- 本轮没有注册、升级或替换已运行的系统 v5 helper，没有调用 Turbo，也没有 SMC 写入。更快启动路径只位于新构建的内嵌 v6 helper，需要用户后续单独授权升级才会生效。

## Unreleased · larger P/E status summary refinement · 2026-08-30

### Changed

- P/E 与双风扇 2×2 布局保持不变，模板图片从 20 pt 增至 22 pt 高，等宽半粗体从 8.5 pt 增至 9.5 pt，两行固定坐标调整为 0 与 11 pt，见 ADR-032 Follow-up。

### Validated

- macOS 26 arm64 Personal Team 签名构建通过，App 与内嵌 helper 均通过 strict 签名校验。
- 新构建已作为唯一 ThermalPulse 实例启动。真实菜单栏截图读回 `P43°`、`E42°` 与两台风扇数值，四项完整且没有上下裁切；root 租约目录为空，本轮没有升级 helper、调用 Turbo 或写入 SMC。

### Not included

- 本轮不改变温度聚合、采样、展开面板与 Turbo 安全逻辑。

## Unreleased · P/E status summary refinement · 2026-08-30

### Changed

- 菜单栏左列从 P 核与电池改为 P 核与 E 核热点，电池温度继续保留在展开面板，见 ADR-032。
- 模板图片从 18 pt 增至 20 pt 高，等宽半粗体从 7.5 pt 增至 8.5 pt，两行固定坐标同步调整为 0 与 10 pt。

### Validated

- macOS 26 arm64 Personal Team 签名构建通过，App 与内嵌 helper 均通过 strict 签名校验；P/E/电池聚合定向测试通过。
- 新构建已作为唯一 ThermalPulse 实例启动。真实菜单栏截图读回 `P49°`、`E48°` 与两台风扇数值，四项完整且没有顶部裁切；root 租约目录为空，本轮没有升级 helper、调用 Turbo 或写入 SMC。

### Not included

- 本轮不改变 P 核或 E 核热点聚合、1 Hz 采样、Turbo helper 与安全租约。

## Unreleased · fixed-size status image milestone · 2026-08-30

### Fixed

- 修复 `MenuBarExtra` 忽略多行文本 6 pt 字号并裁掉顶部的问题。四项摘要现在预渲染为固定 18 pt 高模板图片，见 ADR-031。
- 图片内部使用 7.5 pt 等宽半粗体与固定两行、两列坐标，在完整容纳四项摘要的前提下提高菜单栏可读性；系统状态项只负责模板着色，不再参与字体与换行布局。
- 状态栏标签出现时立即启动普通权限只读采样，不再要求用户先展开面板才能看到实时摘要。

### Validated

- macOS 26 arm64 无签名 Debug 构建与 Personal Team 签名构建均通过；App 与内嵌 helper 通过 strict 校验。
- 固定图片构建已作为唯一菜单栏实例启动，现有 root helper 进程保持不变且租约目录为空。本轮没有升级 helper、调用 Turbo 或写入 SMC。

### Not included

- Computer Use 无法附着无窗口的 `MenuBarExtra` 或 `SystemUIServer` 状态项，最终实际菜单栏外观仍需以用户当前屏幕读回为准。

## Unreleased · micro menu bar summary milestone · 2026-08-30

### Changed

- 状态项从 8 pt 缩小为 6 pt 等宽半粗体，温度压缩为 `P/B` 前缀，右列省略 `F1/F2` 与 RPM 单位，只保留两台动态风扇的数值，见 ADR-030。
- 展开面板和辅助功能描述继续保留完整名称、编号与单位。

### Validated

- macOS 26 arm64 无签名 Debug 构建与 Personal Team 签名构建均通过；App 与内嵌 helper 通过 strict 校验。
- 紧凑构建已作为唯一菜单栏实例启动，现有 root helper 进程保持不变且租约目录为空。本轮没有升级 helper、调用 Turbo 或写入 SMC。

### Not included

- 6 pt 紧凑摘要在实际菜单栏中的最终尺寸和可读性仍需用户确认。

## Unreleased · two-line menu bar host fix milestone · 2026-08-30

### Fixed

- 修复复合 SwiftUI 状态项只显示第一个 P 核文本的问题。摘要改为单个两行等宽文本，目标布局为左上 P 核、左下电池、右上风扇 1、右下风扇 2，见 ADR-029。
- 风扇内容继续来自动态枚举并按行分配，没有硬编码当前机器的 SMC 风扇索引。

### Validated

- macOS 26 arm64 无签名 Debug 构建与 Personal Team 签名构建均通过；App 与内嵌 helper 通过 strict 校验。
- 新构建已作为唯一菜单栏实例启动，现有 root helper 进程保持不变且租约目录为空。本轮没有升级 helper、调用 Turbo 或写入 SMC。

### Not included

- 系统状态项中的最终 2×2 外观仍需用户直接查看菜单栏确认。

## Unreleased · compact menu bar presentation milestone · 2026-08-30

### Changed

- 状态栏改为两个并排的小字号双行分组，左侧上下显示 P 核热点与电池温度，右侧按动态枚举顺序逐行显示风扇实际 RPM，见 ADR-028。
- 菜单栏弹出面板移除滚动容器与固定高度，并缩短曲线、卡片内边距和区块间距，让核心信息一次展开可见。

### Validated

- macOS 26 arm64 无签名 Debug 构建通过。完整普通测试 75 项中 71 项通过、4 项硬件测试按设计跳过、0 项失败。
- 新 Personal Team 签名 App 与内嵌 helper 均通过 strict 校验；新 App 已作为唯一菜单栏实例启动，现有 root helper 进程保持不变且租约目录为空。
- 本里程碑只改展示层，没有升级 helper、调用 Turbo 或写入 SMC。

### Not included

- 双行状态项的字号和无滚动面板的实际屏幕可读性仍需用户在菜单栏中人工确认。

## Unreleased · core temperature curve sentinel filtering milestone · 2026-08-30

### Fixed

- P 核和 E 核曲线在展示前省略 10 至 120 °C 之外的原始哨兵点，0 °C 不再被画成真实核心温度，见 ADR-027。
- 省略哨兵后沿用时间间隙分段，避免直接连接缺口两侧而制造连续读数。

### Validated

- 新增定向回归测试，确认序列 `[48, 0, 50]` 显示为两个独立的有效点与两个分段。TelemetryPresentation 定向测试 9 项全部通过。
- 完整普通测试 75 项中 71 项通过、4 项硬件测试按设计跳过、0 项失败。没有运行真实 Turbo，也没有写 SMC。
- 新 Personal Team 签名 App 与内嵌 helper 均通过 strict 校验；包含曲线修复的 App 已作为唯一菜单栏实例启动，现有 v5 root helper 保持运行且租约目录为空。

### Not included

- 尚未经过足够长时间的人工曲线观察，用户仍需确认 P 核代表 key 再次返回 0 哨兵时界面只留下断线，不出现 0 °C 下坠。

## Unreleased · protocol v5 RPM readback and control-state milestone · 2026-08-30

### Fixed

- 修复 Turbo active 时逐风扇行仍显示“苹果自动控制”的问题。文案现在由可信 `TurboStatus` 映射，active 显示“Turbo 全速控制”，不可信状态不宣称已恢复。
- 修复实际 RPM 小幅高于标称最大值时被验收误判的问题。最大目标仍要求原始字节精确等于动态 `F{i}Mx`，实际反馈允许不超过动态最大值 5% 的控制或量化超调，见 ADR-026。

### Changed

- 启动上升门禁、300 毫秒 active watchdog 与 HardwareProbe 统一复用实际 RPM 可信范围；非有限、负值或超过动态最大值 105% 的读回会触发恢复。
- 私有 XPC 安全语义升级到协议 v5，防止新 App 继续连接没有该 active watchdog 规则的 v4 helper。

### Validated

- 修复前 v4 短测实际进入 active。独立读回 `Ftst=1`、两台风扇 mode 1、目标原始字节等于 5777 RPM 动态最大值，实际样本分别为 5701、5855、5811 RPM 和 5776、5775、5778 RPM。
- 主动停止后独立读回两台风扇 mode 3、`Ftst=0`，lease 不存在；helper 记录 `restoration_completed issue=none`。
- 修复后定向测试 35 项全部通过。完整普通测试 74 项中 70 项通过、4 项硬件测试按设计跳过、0 项失败；显式 HardwareProbe 4 项中 3 项通过、active 读回按设计跳过、0 项失败。
- v5 Personal Team Debug App 与 helper 构建成功，并通过 App deep strict、helper strict、固定 identifier 和非空同 Team 校验。

### Not included

- 系统中仍运行已注册 v4 helper。本里程碑没有升级、注册或启动 v5 helper，也没有再次执行真实 Turbo。v5 active 文案、5% 容差、主动停止以及到期、崩溃、断连、helper 重启和休眠恢复仍需后续独立授权与实机读回。

## Unreleased · protocol v4 helper registration milestone · 2026-08-30

### Fixed

- helper 替换在异步注销后增加稳定未注册观察门禁，连续确认 `notRegistered` 或 `notFound` 后只执行一次注册，见 ADR-025。

### Validated

- 用户从 `notRegistered` 状态显式注册包含稳定替换门禁的协议 v4 helper。统一日志读回 `SMAppService.register()` 成功；launchd 读回服务由 ServiceManagement 管理、以 root 运行且 Mach endpoint 活跃。
- App 与 helper 建立双向同 Team 签名约束 XPC。App 与 helper 的 strict 签名、固定 identifier 和非空同 Team 约束此前已由同一签名构建读回。
- root lease 不存在。注册后 HardwareProbe 共 4 项，3 项通过、1 项 Turbo active 读回按设计跳过；定向门禁明确读回风扇 0 与风扇 1 均为 mode 3，`Ftst=0` 断言通过。

### Not included

- 本里程碑没有重新执行已注册 helper 的替换路径，也没有调用 `startTurbo()` 或写 SMC，不确认 Turbo active、最大目标、实际 RPM、主动停止、600 秒到期或故障恢复。真实启动仍需要用户再次明确授权。

## Unreleased · first short Turbo hardware attempt milestone · 2026-08-30

### Validated

- 用户明确授权一次短时真实 Turbo 测试。启动前专用只读门禁确认两个动态风扇处于 automatic，`Ftst=0`，helper 由 ServiceManagement 管理、以 root 运行且 Mach endpoint 活跃。
- 激活阶段监控曲线观察到最高约 2234 RPM 的短时上升，但 helper 返回 readback mismatch 与 failed-safe-auto，没有进入 active，也没有自动重试。
- 失败后持久租约文件已删除。独立 HardwareProbe 读回 `F0Md=0`、`F1Md=0`、`Ftst=0`、`F0Ac=1350.73 RPM`、`F1Ac=1462.07 RPM`，两个目标值已回到苹果自动控制值；root helper 继续运行。

### Not included

- 本里程碑不确认两台风扇同时进入手动模式、目标达到各自 5777 RPM、实际 RPM 达标或 Turbo active。也没有验收主动停止、600 秒到期、App 崩溃、XPC 断开、helper 重启、休眠唤醒、卸载、公证或发布。
- 下一次真实写入前先增加能区分模式、目标与实际 RPM 门禁的有限诊断；代码和 helper 升级完成后仍需用户再次明确授权。

## Unreleased · signed helper upgrade milestone · 2026-08-29

### Added

- 新增独立的“升级 Turbo helper”确认流程。旧 helper 返回 write-path-unavailable 时，App 先失效旧 XPC，再由 ServiceManagement 替换当前签名版本；升级确认不调用 Turbo。
- 新增只读升级前后硬件门禁，动态枚举全部风扇模式 key 并确认 `Ftst`，不包含写命令。

### Fixed

- 修正同步 `unregister()` 后立即 `register()` 导致旧服务已移除而新服务未登记的竞态。升级路径改为等待异步注销完成后再注册，见 ADR-017。

### Validated

- 最终 Personal Team Debug App 与 helper 重新构建，并分别在沙箱外通过 deep strict 与 strict 代码签名校验。
- 用户明确授权升级且不启动 Turbo。系统读回新 helper 由 ServiceManagement 管理、以 root 运行且 Mach endpoint 活跃；App 经双向签名 XPC 取得无错误 inactive 状态并显示“苹果自动”。旧 helper PID 为 43656，新 helper PID 为 54765，证明运行实例已替换。
- 升级前后 `/Library/Application Support/ThermalPulse/turbo-lease.plist` 均不存在。普通测试共 57 项，55 项通过、2 项实机只读测试按设计跳过、0 项失败；升级后 HardwareProbe 共 57 项、57 项通过、0 项跳过、0 项失败，确认全部动态风扇模式与 `Ftst` 保持 0。

### Not included

- 本里程碑没有调用 `startTurbo()`，没有写 SMC，没有把风扇切入手动，也没有验收最大目标、实际 RPM、到期、崩溃、断连、helper 重启或休眠恢复。卸载、公证、发布仍不在本里程碑内。

## Unreleased · Turbo safety engine source milestone · 2026-08-29

### Added

- 新增 helper 侧 `SMCFanWriteAdapter`，动态枚举所有风扇，只接受实时验证的逐风扇模式、目标、最大值和实际 RPM key。写入接口仍不接受业务 key、RPM 或时长。
- 新增 root-owned 最小持久租约、固定 600 秒安全控制器、每连接 owner、1 秒看门狗、进程内单调截止时间、唤醒恢复和 helper 启动旧租约恢复。
- 新增模式与最大目标读回、实际 RPM 上升门禁、部分激活回滚、恢复重试和 `Ftst` 所有权记录。租约先于任何 SMC 写入，每个风扇也先记录接管范围再切手动。

### Changed

- App 的 `TurboXPCClient` 改为生命周期内持久连接，启动、停止和状态查询超时分别为 70 秒、12 秒和 3 秒。连接退出、断开、失效或超时会触发 helper 的所有者恢复路径。
- App 侧协调器保留 helper 返回的安全禁用与 failed-safe-auto 原因，不把有效失败状态改写成通用无效响应。
- 菜单栏头部和 Turbo 状态 badge 只有在无错误 inactive 时才显示苹果自动；helper 不可用、外部控制或状态异常时改为不接管、外部控制或待确认文案。

### Validated

- 用户此前已显式完成 LaunchDaemon 注册和系统允许。系统读回旧安全 stub 由 ServiceManagement 管理、root 运行且 XPC 活跃；App 实际收到 write-path-unavailable，证明注册与双向签名 XPC 通路可达。旧 runtime 没有 SMC 写入能力。
- 当前 Mac16,7 的显式只读探针实际通过，读到 3337 个 key、2 个风扇、315 个采样候选和连续两批 312 路零失败采样。`F0Md`、`F1Md`、`Ftst` 为 1 字节 `ui8 ` 且当前值为 0；`F0Tg`、`F1Tg`、`F0Mx`、`F1Mx` 为 4 字节 `flt `，两个实时最大值均为 5777 RPM；`FS! ` 不存在。全程没有写 SMC。
- 未签名 Debug 构建通过。普通测试共 55 项，54 项通过、1 项真实硬件探针按设计跳过、0 项失败，覆盖外部和未知模式拒绝、租约先行、动态多风扇、读回、回滚、到期、wall clock 回拨、断连、唤醒、重启与恢复失败。
- 最终 Personal Team Debug 构建由 Xcode 成功产出。同一产物中的 App 与 helper 均在沙箱外通过独立 strict 校验；沙箱内出现的 `CSSMERR_TP_NOT_TRUSTED` 已确认是受限信任服务造成的假失败。该产物没有用于升级已注册 helper。

### Not included

- 本里程碑没有替换、重新注册、重启或卸载系统中现有 helper，没有执行真实 SMC 写入，没有把风扇切入手动，也没有完成 Turbo 或恢复的实机验收。新 helper 升级和真实写入仍是独立门禁。

## Unreleased · helper registration UI milestone · 2026-08-29

### Added

- 新增 `SMAppService` LaunchDaemon 状态适配器、App 侧注册协调器、显式注册确认弹窗、待批准系统设置入口和重新检查状态操作。
- 注册状态与 XPC 状态分层：只有系统状态为 enabled 才查询 helper；App 启动和控件出现只读查询，不自动注册。

### Fixed

- 修正首次 `SMAppService.Status.notFound` 的解释。该状态可表示系统尚未记录服务，现与 notRegistered 一样展示显式注册入口，不再误报 App 包内缺少 helper 配置。

### Validated

- 未签名 Debug 测试构建与 Personal Team 签名 Debug 构建通过。普通测试共 43 项，42 项通过、1 项真实硬件探针按设计跳过、0 项失败。
- 签名 Debug App 的自动化可访问性读回实际显示“系统尚未登记 Turbo helper”和 `turbo.helper.register` 按钮；没有点击最终注册确认。
- 当前 Personal Team Debug App 通过代码签名严格校验，但未满足 notarized 签名 requirement，`spctl` 评估未通过。实际 LaunchDaemon 注册结果仍未知。

### Not included

- 本里程碑没有实际调用 `SMAppService.register()`，没有注册、批准、安装或启动 LaunchDaemon，没有完成双向 XPC 实连，也没有 SMC 写入、风扇控制或 Turbo 恢复验收。

## Unreleased · Personal Team signing baseline milestone · 2026-08-29

### Changed

- 为 App 与 helper 的 Debug、Release 和 HardwareProbe configuration 配置同一个免费 Personal Team，继续使用 Automatic Signing。AIREADME 不记录实际 Team ID、证书材料或账号凭证。

### Validated

- Xcode 26.6 在当前开发机完成本机 Debug 签名构建，实际读回 App identifier 为 `io.github.iyuenan3.thermalpulse`、helper identifier 为 `io.github.iyuenan3.thermalpulse.helper`，双方 Team ID 相同且非空。
- App 与 helper 均由同一 Apple Development 身份和完整 Apple 证书链签名，App bundle 通过 deep strict 验证。
- 普通测试共 39 项，38 项通过、1 项真实硬件探针按设计跳过、0 项失败。

### Not included

- 本里程碑没有调用 `SMAppService.register()`，没有注册、安装或启动 LaunchDaemon，没有请求管理员批准，没有验证真实双向 XPC 服务连接，也没有 SMC 写入、风扇控制或 Turbo 恢复验收。

## Unreleased · helper and XPC skeleton milestone · 2026-08-29

### Added

- 固定 App bundle identifier 为 `io.github.iyuenan3.thermalpulse`，helper identifier 与 Mach service 为 `io.github.iyuenan3.thermalpulse.helper`。
- 新增协议 v1 `NSSecureCoding` payload、实际 `TurboXPCClient`、固定 LaunchDaemon plist 和 `ThermalPulseHelper` executable target。
- App 与 helper 新增对称 peer requirement，均校验 Apple 签名锚点、固定 identifier 和从自身有效签名取得的相同 Team ID。未签名构建拒绝连接。
- helper 当前只返回 write-path-unavailable，三个 XPC 方法均没有 RPM、时长或 SMC key 业务参数。

### Validated

- Debug 与 Release 未签名构建通过。构建产物读回 App 固定 bundle identifier，并确认 helper 与 LaunchDaemon plist 分别位于 `Contents/Resources` 和 `Contents/Library/LaunchDaemons`，`BundleProgram`、`Label` 与 Mach service 相互一致。
- helper 嵌入生成的 Info.plist section 后，独立 ad hoc 构建实际读回 App 和 helper 的代码签名 identifier 均与冻结值一致，App 通过 deep strict 签名校验。ad hoc 签名没有 Team ID，因此仍按设计拒绝 XPC，不替代 Personal Team 实连。
- 普通测试共 39 项，38 项通过、1 项真实硬件探针按设计跳过、0 项失败。新增覆盖固定身份、签名 requirement 注入防护、安全编码 round trip、协议版本拒绝和 XPC interface 构造。
- 源码扫描确认没有 `SMAppService.register()`、helper 注册调用或 SMC 写入入口。

### Not included

- 本里程碑没有用 Personal Team 完成签名实连，没有注册或启动 LaunchDaemon，没有请求管理员批准，也没有 SMC 写入、真实风扇控制或 Turbo 恢复验收。

## Unreleased · app-side Turbo controls milestone · 2026-08-29

### Added

- 新增无参数 `TurboClient`、`TurboCoordinator`、固定 600 秒租约校验和有限错误模型。
- 主窗口与菜单栏弹窗新增共享 Turbo 控件，包含启动确认、展示型倒计时、立即恢复自动、处理中和失败状态。
- 新增 `UnavailableTurboClient`，在 helper 尚未配置时明确禁用控件并说明原因。

### Validated

- Turbo 状态机测试覆盖 helper 不可用、有效 600 秒租约、超长租约拒绝、外部控制器拒绝、重复启动不续时、停止成功、恢复失败和活跃期通信失败不误报自动模式。
- Debug 与 Release 构建通过。完整普通测试共 33 项，32 项通过、1 项真实硬件探针按设计跳过、0 项失败，不执行 SMC 写入。

### Not included

- 本里程碑不包含 helper target、bundle identity、签名 requirement、Mach service、SMC 写入、系统批准或真实风扇控制。由于未签名 App 尚无可寻址 bundle identifier，Turbo 卡片的本机自动化视觉检查未完成。

## Unreleased · single-panel and menu popover redesign milestone · 2026-08-29

### Changed

- 移除主窗口侧栏，将 P 核温度主状态、风扇与采样摘要、系统 thermal state、趋势和可展开的“传感器与曲线”合并为单页。
- 菜单栏弹窗改为蓝色温度主状态、紧凑分组信息行和底部“打开监控窗口”主按钮；只借鉴用户指定参考的视觉层级，不加入电量控制、设备序列号或其他无关功能。
- 图表卡片统一使用轻量材质、圆角边框和弱阴影，与菜单栏弹窗保持一致的信息层级。

### Validated

- Debug 与 Release 构建均成功。新 Release App 通过 LaunchServices 启动，菜单栏状态项实际显示 P 核温度和双风扇 RPM。
- 无侧栏主窗口完成本机截图检查，温度主状态、紧凑信息行、热状态提示和趋势区域在实际窗口尺寸内可见。

### Not included

- 自动化工具因 bundle identifier 尚未冻结而无法稳定寻址菜单栏弹窗，弹窗点击和完整交互仍等待用户人工确认。本里程碑不包含 SMC 写入、helper、Turbo、签名、安装或 release。

## Unreleased · monitoring product design and P-core summary milestone · 2026-08-29

### Added

- 主窗口重构为原生侧栏结构，概览页集中展示 P 核温度族、动态风扇 RPM、系统 thermal state 和趋势图，传感器页按证据分组展示读数。
- 菜单栏标题直接显示紧凑 P 核平均温度和全部已枚举风扇 RPM；弹出面板逐风扇显示完整读数，并保留重新枚举、重开窗口和退出入口。
- 新增动态 `Tp` 温度族策略，只聚合有效 `flt` 摄氏度候选，输出平均值、最高值、最高 key 和候选数量；默认温度曲线优先选择族内最高 key。

### Validated

- 新增 P 核温度族纯逻辑测试，覆盖过滤、平均值、最高值和无有效输入时的未知状态；普通测试全部通过，Release 构建成功。
- 当前 Mac16,7 普通权限只读基线取得 102 个有效 `Tp` 候选，平均 33.8 °C、最高 75.6 °C；35 秒 14 线程负载期间平均升至 75.3 °C、最高升至 94.5 °C。两个风扇同时保持正常只读回传，负载进程自行退出。
- 新 Release 主窗口完成本机截图检查，并根据实际宽度修正三列卡片布局和双风扇数值截断。通过 LaunchServices 标准启动后，顶部状态项实际显示 `P44° F1357/1486`。

### Not included

- 本里程碑不确认 102 个候选分别对应哪些具体核心，也不代表其他 Apple Silicon 机型已验证。菜单栏弹出面板和传感器页仍等待用户人工验收，不包含 SMC 写入、helper、Turbo、签名、安装或 release。

## Unreleased · local performance attribution markers milestone · 2026-08-29

### Added

- 新增 `ThermalPulse:MonitoringPerformance` 本地统一日志标记，覆盖监控窗口、菜单栏重开请求、原始候选展开与收起、曲线选择、时间范围和重新枚举。
- 持续采样每满 60 个有效样本写一条状态快照，便于与一分钟间隔的 CPU 和内存样本对齐。

### Validated

- 普通测试通过。短暂启动 Debug App 后，macOS 统一日志实际读回窗口显示、刷新开始和刷新完成事件，完成事件中的默认曲线数量为 3。
- 标记只包含样本数、曲线数量、时间范围、界面状态和系统 thermal state，不包含设备标识或原始 SMC key。
- Release App 无操作运行 12 分钟，取得 13 个 `top` 样本和 13 条连续每分钟状态快照。CPU 均值为 6.52%，范围为 4.9% 至 10.7%；内存均值为 211.62 MiB，范围为 206 至 215 MiB。本轮没有复现第 10 分钟后的持续台阶。

### Not included

- 本里程碑尚未完成 Release 一小时标记长测和单变量交互阶段，因此已知性能台阶仍未归因。也不包含人工曲线验收、温度语义、SMC 写入、helper、Turbo、签名、安装或 release。

## Unreleased · read-only Release soak and monitoring UX milestone · 2026-08-29

### Added

- 菜单栏新增“打开监控窗口”，关闭主窗口后可重新创建并置于前台。

### Changed

- 默认曲线在已验证风扇之外，增加枚举快照中数值最高的一个有效原始温度候选。该候选在本次会话固定，只显示原始 key，不赋予部件名称，见 ADR-010。

### Validated

- 最终 Release App 连续运行 3605 秒，未提前退出且日志为空；60 个一分钟监督样本间隔无缺口，结束后目标进程已回收。
- 普通测试 24 项，23 项通过、1 项实机测试按设计跳过；显式只读硬件探针另行执行 1 项并通过，读到 3337 个 key、2 个风扇，以及连续两批 312 路零失败采样。

### Observed

- 长测 `top` CPU 均值为 11.5%，范围为 2.5% 至 19.3%；物理内存范围为 207 至 323 MiB，最终为 323 MiB；RSS 范围约为 142.2 至 253.2 MiB，最终约为 253.2 MiB。
- 前 10 个样本与后 50 个样本之间出现性能台阶，但没有对应界面操作时间戳，不能归因于具体动作。该问题已记录到 MEMORY，并进入 ROADMAP。

### Not included

- 本里程碑不包含用户对菜单栏重开、两类曲线和交互观感的人工确认，也不包含温度部件语义、SMC 写入、helper、Turbo、签名、安装或 release。

## Unreleased · read-only performance milestone · 2026-08-29

### Fixed

- 将 actor 字典中的固定容量环形缓冲改为引用型原地更新，消除每次采样写入触发的 3600 槽数组写时复制。
- 将图表候选目录改为枚举后一次筛选、排序和缓存，消除 312 行原始候选各自重复处理完整目录的开销。

### Changed

- 高级原始温度候选默认折叠，用户可显式展开；折叠不停止后台 1 Hz 采样。

### Validated

- Release 120 秒短测未提前退出且日志为空。同口径 `top` 区间 CPU 均值从优化前约 20.2% 降至优化后约 4.0%，约降低 80%；物理内存从约 246 MiB 降至约 195 MiB。
- 312 个序列的一小时容量测试从 5.520 秒降至 1.689 秒，约降低 69%，容量与统计断言不变。普通测试 24 项执行、1 项实机测试按设计跳过、0 项失败。
- 显式 `ThermalPulseHardwareProbe` 实际执行 1 项并通过，读到 3337 个 key、2 个风扇，以及连续两批 312 路零失败采样；全程没有 SMC 写入。

### Corrected

- 上一个里程碑记录的 Release `ps` 平均 46.6% 是包含启动阶段的衰减平均值，不能解释为稳定区间 CPU 占用。本次使用 `top` 区间采样建立了可比的优化前后基线。

### Not included

- 本里程碑不包含 Release 一小时持续运行、人工曲线验收、温度语义确认、SMC 写入、helper、Turbo、签名、安装或 release。

## Unreleased · read-only long-run validation milestone · 2026-08-29

### Validated

- Debug App 连续运行 3605 秒，未提前退出且日志为空；运行前后普通测试均为 24 项执行、23 项通过、1 项实机测试按设计跳过。
- 在真实运行窗口内叠加 14 核 CPU 满载 600 秒和 12 GiB 内存压力 300 秒。App 保持存活，系统没有发生 swap，312 个动态采样项继续取得连续两轮零失败读回。
- 全程保持只读。苹果自动控制下，两个风扇从 0 RPM 上升到 1352 RPM 和 1459 RPM，并在冷却后回到 0 RPM。

### Observed

- Debug 一小时稳定样本的 RSS 为 198640 至 255776 KiB，平均 239677.8 KiB；CPU 为 6.3% 至 65.9%，平均 36.2%。
- Release App 300 秒短测未提前退出且日志为空，但 10 个稳定样本的 CPU 平均为 46.6%，范围为 37.5% 至 53.8%；RSS 平均为 217038.4 KiB。进入 Turbo 前需要先完成性能剖析和 Release 长时验证。

### Not included

- 本里程碑不包含人工曲线验收、温度语义确认、性能问题修复、SMC 写入、helper、Turbo、签名、安装或 release。

## Unreleased · read-only charts milestone · 2026-08-28

### Added

- 新增最多 6 项传感器选择，以及 5 分钟、15 分钟和 1 小时 Swift Charts 历史曲线，见 ADR-009。
- 新增 RPM 与原始温度候选分图、保留端点和局部极值的显示降采样，以及采样间隙断线呈现。
- 新增选择策略、降采样、间隙、窗口查询和 312 序列一小时容量边界测试。

### Changed

- 环形缓冲改为增量维护总和与极值，摘要生成不再每秒遍历所有历史点。
- 曲线默认只选择运行时验证的风扇实际 RPM，原始温度候选必须手动加入。

### Not included

- 本里程碑不包含传感器中文语义确认、真实 1 小时运行与人工界面验收、SMC 写入、helper、Turbo、签名、安装或 release。

## Unreleased · read-only sampling milestone · 2026-08-28

### Added

- 新增一次枚举后的 1 Hz 动态白名单采样，并缓存 SMC 元数据，见 ADR-008。
- 新增每传感器 3600 点内存环形缓冲，以及最新值、最小值、最大值和平均值统计。
- 新增采样白名单、失败隔离、停止语义、环形覆盖和统计测试；实机探测增加两轮缓存元数据读回。

### Changed

- 菜单栏和监控窗口从一次性快照切换为持续只读读数，用户手动刷新会重新枚举并重建白名单。

### Not included

- 本里程碑不包含曲线绘制、传感器中文语义确认、长时间运行验收、SMC 写入、helper、Turbo、签名、安装或 release。

## Unreleased · 2026-08-28

### Added

- 新增原生 SwiftUI 菜单栏 App、监控窗口壳、`ThermalPulseCore` 静态库和 XCTest 目标。
- 新增普通权限只读 AppleSMC adapter、typed sensor model、证据分级分类器与全量扫描服务。
- 新增普通逻辑测试和显式 `ThermalPulseHardwareProbe` 实机只读验证 scheme。

### Fixed

- 用 C 结构和双重断言固定 80 字节 AppleSMC user-client ABI，见 ADR-005。
- 修正 Apple Silicon `flt ` 小端浮点解码，并取得当前 Mac16,7 两个风扇的实际与最大 RPM 关系证据。
- 将动态传感器列表改为 `ScrollView` 与 `LazyVStack`，消除扫描完成时的 NSTableView 重入警告。

### Not included

- 本里程碑不包含 1 秒持续采样、1 小时曲线、传感器中文语义确认、SMC 写入、helper、Turbo、签名、安装或 release。

### Changed

- 最低支持系统正式设为 macOS 26.0，所有工程 configuration 使用同一 deployment target，见 ADR-007。
