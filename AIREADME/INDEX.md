# ThermalPulse · AIREADME
> macOS 热状态监控与限时 Turbo 散热工具 ｜ 生命周期: active, pre-alpha
> last-synced: bd5e194 · 2026-08-28

## 状态

| 文件 | 状态 | 摘要 |
|---|:--:|---|
| CORE | ✅ | 身份、边界与失效安全红线已确定 |
| RELATIONS | ✅ | 当前无其他项目依赖或共享底座 |
| SPEC | ⚑ | 本地产品契约已定，XPC 错误模型待实现前冻结 |
| ARCHITECTURE | ✅ | 一次枚举、1 Hz 只读采样、内存历史和 Turbo 安全状态机已确定 |
| DEPLOYMENT | ⚑ | 最低系统已定为 macOS 26.0，签名、注册与卸载流程待实作验证 |
| PRD | ✅ | 监控优先、Turbo 限时的产品意图已确定 |
| ROADMAP | ✅ | 只读采样与统计已完成，当前转向证据筛选、曲线和长时间验证 |
| CONVENTIONS | ✅ | 传感器、采样节拍、环形缓冲、SMC ABI、安全与测试约定已确定 |
| DECISIONS | ✅ | 立项、只读基线与持续采样的关键决策已记录 |
| MEMORY | ✅ | 已记录 SMC ABI 布局和 Apple Silicon 浮点字节序踩坑 |
| CHANGELOG | ✅ | 两个只读监控切片已记录，尚无 release |

## 按任务读

- 跨项目了解：CORE + RELATIONS，集成判断再读 SPEC。
- 修改产品方向：PRD + CORE + DECISIONS。
- 修改架构或安全状态机：ARCHITECTURE + DECISIONS + CORE。
- 实现监控：ARCHITECTURE + CONVENTIONS + PRD。
- 实现 Turbo 或 helper：CORE + ARCHITECTURE + SPEC + DEPLOYMENT + CONVENTIONS。
- 排期：ROADMAP。
- 发布或复盘：CHANGELOG 或 MEMORY。
