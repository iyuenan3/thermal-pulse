# ThermalPulse · AIREADME
> macOS 热状态监控与限时 Turbo 散热工具 ｜ 生命周期: active, pre-alpha
> last-synced: 934721e · 2026-08-30

## 状态

| 文件 | 状态 | 摘要 |
|---|:--:|---|
| CORE | ✅ | 身份、边界与失效安全红线已确定 |
| RELATIONS | ✅ | 当前无其他项目依赖或共享底座 |
| SPEC | ✅ | 固定 23 pt P/E 图片状态摘要、无滚动面板、协议 v7、固定租约、快速稳定读回、并发 XPC 请求与恢复重试契约已记录 |
| ARCHITECTURE | ✅ | 三类温度、固定图片 2×2 状态摘要、无滚动菜单栏面板、Turbo 安全控制器与立即恢复重试已记录 |
| DEPLOYMENT | ✅ | v6 helper 已完成短时 Turbo 验收；v7 仅完成源码、测试和签名构建，尚未升级系统 helper |
| PRD | ✅ | 2×2 菜单栏摘要、无滚动完整面板、单张曲线和固定 10 分钟可停止 Turbo 已确定 |
| ROADMAP | ✅ | 下一阶段为单独升级 v7 helper，再继续到期、断连、重启与唤醒恢复验收 |
| CONVENTIONS | ✅ | 传感器、采样、紧凑展示、曲线、租约先行、动态风扇写入与测试约定已确定 |
| DECISIONS | ✅ | 三类温度、固定图片 2×2 摘要、`Ftst` 快速稳定读回、恢复重试、并发 XPC 请求与未知状态拒绝已记录 |
| MEMORY | ✅ | 已记录温度聚合、helper 竞态、恢复重试假绿、未知 `Ftst` 写入风险和状态项渲染问题 |
| CHANGELOG | ✅ | 已记录只读、Turbo v6 短测、v7 安全审查、核心温度曲线与固定图片菜单栏里程碑，尚无 release |

## 按任务读

- 跨项目了解：CORE + RELATIONS，集成判断再读 SPEC。
- 修改产品方向：PRD + CORE + DECISIONS。
- 修改架构或安全状态机：ARCHITECTURE + DECISIONS + CORE。
- 实现监控：ARCHITECTURE + CONVENTIONS + PRD。
- 实现 Turbo 或 helper：CORE + ARCHITECTURE + SPEC + DEPLOYMENT + CONVENTIONS。
- 排期：ROADMAP。
- 发布或复盘：CHANGELOG 或 MEMORY。
