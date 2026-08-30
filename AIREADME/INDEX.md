# ThermalPulse · AIREADME
> macOS 热状态监控与限时 Turbo 散热工具 ｜ 生命周期: active, pre-alpha
> last-synced: 0b4df3b · 2026-08-31

## 状态

| 文件 | 状态 | 摘要 |
|---|:--:|---|
| CORE | ✅ | Apple Silicon MacBook Pro 范围、边界与失效安全红线已确定 |
| RELATIONS | ✅ | 当前无其他项目依赖或共享底座 |
| SPEC | ✅ | 固定 23 pt P/E 图片状态摘要、无滚动面板、协议 v7、固定租约、快速稳定读回、并发 XPC 请求与恢复重试契约已记录 |
| ARCHITECTURE | ✅ | 三类温度、动态单或双风扇状态摘要、无滚动菜单栏面板与 Turbo 安全控制器已记录 |
| DEPLOYMENT | ✅ | v0.0.1 由 GitHub Actions 生成 ad hoc 签名 DMG；Developer ID、公证与公开 Turbo 不在本版 |
| PRD | ✅ | Apple Silicon MacBook Pro、动态风扇摘要、单张曲线和固定 10 分钟可停止 Turbo 已确定 |
| ROADMAP | ✅ | 下一阶段为确认 M5 单风扇视觉，再按机型继续 Turbo 与恢复验收 |
| CONVENTIONS | ✅ | 传感器、采样、紧凑展示、曲线、租约先行、动态风扇写入与测试约定已确定 |
| DECISIONS | ✅ | Apple Silicon MacBook Pro 范围、动态风扇布局、Turbo 安全与无公证预览发布边界已记录 |
| MEMORY | ✅ | 已记录 M5 小写模式 key、外部手动控制，以及既有 helper 和状态项问题 |
| CHANGELOG | ✅ | v0.0.1 首个公开 DMG 预览版及既有监控、Turbo 验收边界已记录 |

## 按任务读

- 跨项目了解：CORE + RELATIONS，集成判断再读 SPEC。
- 修改产品方向：PRD + CORE + DECISIONS。
- 修改架构或安全状态机：ARCHITECTURE + DECISIONS + CORE。
- 实现监控：ARCHITECTURE + CONVENTIONS + PRD。
- 实现 Turbo 或 helper：CORE + ARCHITECTURE + SPEC + DEPLOYMENT + CONVENTIONS。
- 排期：ROADMAP。
- 发布或复盘：CHANGELOG 或 MEMORY。
