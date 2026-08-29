# ThermalPulse · AIREADME
> macOS 热状态监控与限时 Turbo 散热工具 ｜ 生命周期: active, pre-alpha
> last-synced: 1ac2af8 · 2026-08-29

## 状态

| 文件 | 状态 | 摘要 |
|---|:--:|---|
| CORE | ✅ | 身份、边界与失效安全红线已确定 |
| RELATIONS | ✅ | 当前无其他项目依赖或共享底座 |
| SPEC | ⚑ | 本地产品契约已定，XPC 错误模型待实现前冻结 |
| ARCHITECTURE | ✅ | 只读采样、曲线、Release 长测证据和 Turbo 安全状态机已记录 |
| DEPLOYMENT | ⚑ | 最低系统已定为 macOS 26.0，签名、注册与卸载流程待实作验证 |
| PRD | ✅ | 监控优先、Turbo 限时的产品意图已确定 |
| ROADMAP | ✅ | Release 自动长测已完成，当前转向人工界面验收和性能台阶归因 |
| CONVENTIONS | ✅ | 传感器、采样节拍、环形缓冲、默认曲线、安全与测试约定已确定 |
| DECISIONS | ✅ | 立项、只读基线、持续采样、曲线和默认温度选择决策已记录 |
| MEMORY | ✅ | 已记录 SMC ABI、浮点字节序和长测性能台阶踩坑 |
| CHANGELOG | ✅ | 只读实现、长时验证、性能和监控 UX 里程碑已记录，尚无 release |

## 按任务读

- 跨项目了解：CORE + RELATIONS，集成判断再读 SPEC。
- 修改产品方向：PRD + CORE + DECISIONS。
- 修改架构或安全状态机：ARCHITECTURE + DECISIONS + CORE。
- 实现监控：ARCHITECTURE + CONVENTIONS + PRD。
- 实现 Turbo 或 helper：CORE + ARCHITECTURE + SPEC + DEPLOYMENT + CONVENTIONS。
- 排期：ROADMAP。
- 发布或复盘：CHANGELOG 或 MEMORY。
