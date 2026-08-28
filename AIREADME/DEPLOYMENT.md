# DEPLOYMENT：ThermalPulse

## 主机 + 环境

计划运行在带主动散热的 Apple Silicon Mac。首台开发与验收机为 Mac16,7、Apple M4 Pro；其他机型必须经过只读探测与真实写入验收后再加入支持矩阵。

计划最低系统为 macOS 13 或更新版本，以使用现代 ServiceManagement API。最终 deployment target 会在 Xcode 工程建立和 API 验证后冻结。

## 怎么起

当前为 pre-code，没有可执行 App、构建 scheme 或 helper。建立 Xcode 工程后，在项目文档中补充准确 scheme 和测试命令；本机可以通过单条命令设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`，不要求修改全局 `xcode-select`。

## 域名 / 入口

N/A。项目是本地菜单栏 App，不提供服务器、域名、远程访问或后台上传。

## helper 注册与运行

- helper 随签名 App Bundle 分发，使用 `SMAppService` 注册 LaunchDaemon，并通过系统设置状态处理待批准、已启用和被拒绝。
- 普通监控不依赖 helper。只有用户首次使用 Turbo 时才引导注册和批准。
- helper 以 root 权限运行，但接口仅覆盖固定 Turbo 租约，不承担采样、图表或网络职责。
- App 与 helper 的 bundle layout、签名 requirement、plist 和 Mach service 名称在签名原型通过后写实，当前不得凭草稿编造。

## 备份 / 升级 / 回滚

- 首版不自动持久化传感器历史，因此没有用户数据备份要求。
- 升级前若存在 ThermalPulse 租约，必须先恢复自动模式并确认读回，再替换 App 或 helper。
- 卸载顺序必须是停止 Turbo、恢复自动、注销 helper、确认服务停止，最后移除 App。
- helper 更新失败时回滚到已签名的兼容版本；无法确认兼容时禁用 Turbo，但保留只读监控。
- 具体安装、升级、卸载和回滚命令必须在真实签名构建验证后补充，禁止把未经验证的 sudo 命令写成操作手册。

## 运维约束

- 不创建网络监听端口，不上传遥测。
- 不在无人值守条件下自动启用 Turbo。
- 不在休眠唤醒后自动续跑 Turbo。
- 不与其他风扇控制工具争抢手动控制权，发现外部手动模式时拒绝启动。
- 任何 helper 注册、授权或系统级安装验收都需要用户知情，并与普通构建测试分开报告。
