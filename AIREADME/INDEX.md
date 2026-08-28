# ThermalPulse · AIREADME
> macOS 热状态监控与限时 Turbo 散热工具 ｜ 生命周期: planned
> last-synced: pre-code · 2026-08-28

## 状态

| 文件 | 状态 | 摘要 |
|---|:--:|---|
| CORE | ✅ | 身份、边界与失效安全红线已确定 |
| RELATIONS | ✅ | 当前无其他项目依赖或共享底座 |
| SPEC | ⚑ | 本地产品契约已定，XPC 错误模型待实现前冻结 |
| ARCHITECTURE | ✅ | 监控数据流和 Turbo 安全状态机已确定 |
| DEPLOYMENT | ⚑ | 本地运行方向已定，签名、注册与卸载流程待实作验证 |
| PRD | ✅ | 监控优先、Turbo 限时的产品意图已确定 |
| ROADMAP | ✅ | pre-code 阶段顺序已确定 |
| CONVENTIONS | ✅ | 传感器、时间、安全与测试约定已确定 |
| DECISIONS | ✅ | 立项关键决策已记录 |
| MEMORY | ⚑ | 尚无运行时事故或实现踩坑 |
| CHANGELOG | ⚑ | 尚无版本或里程碑 |

## 按任务读

- 跨项目了解：CORE + RELATIONS，集成判断再读 SPEC。
- 修改产品方向：PRD + CORE + DECISIONS。
- 修改架构或安全状态机：ARCHITECTURE + DECISIONS + CORE。
- 实现监控：ARCHITECTURE + CONVENTIONS + PRD。
- 实现 Turbo 或 helper：CORE + ARCHITECTURE + SPEC + DEPLOYMENT + CONVENTIONS。
- 排期：ROADMAP。
- 发布或复盘：CHANGELOG 或 MEMORY。
