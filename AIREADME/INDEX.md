# ThermalPulse · AIREADME
> macOS 热状态监控与限时 Turbo 散热工具 ｜ 生命周期: active, pre-alpha
> last-synced: b6f0f35 · 2026-08-31

## 状态

| 文件 | 状态 | 摘要 |
|---|:--:|---|
| CORE | ✅ | Apple Silicon MacBook Pro 范围、边界与失效安全红线已确定 |
| RELATIONS | ✅ | 当前无其他项目依赖或共享底座 |
| SPEC | ✅ | 固定 23 pt P/E 图片摘要、无滚动面板、协议 v8、Developer Team 与管理员固定 CDHash 双路径已记录 |
| ARCHITECTURE | ✅ | 三类温度、动态风扇摘要、单面板、Turbo 安全控制器和双向安装身份校验已记录 |
| DEPLOYMENT | ✅ | v0.1.1 预发布 DMG 已回读，系统安装与 Turbo 仍待用户验收 |
| PRD | ✅ | Apple Silicon MacBook Pro、动态风扇摘要、单张曲线和固定 10 分钟可停止 Turbo 已确定 |
| ROADMAP | ✅ | 下一阶段为从 v0.1.1 执行无租约安装、XPC inactive 与安全卸载验收 |
| CONVENTIONS | ✅ | 传感器、采样、AppIcon、紧凑展示、曲线、租约先行、动态风扇写入与测试约定已确定 |
| DECISIONS | ✅ | Apple Silicon 范围、Turbo 安全、无公证发布和管理员固定 CDHash 路径已记录 |
| MEMORY | ✅ | 已记录 M5 小写模式 key、外部手动控制，以及既有 helper 和状态项问题 |
| CHANGELOG | ✅ | v0.1.1 发布、官方 DMG 回读与旧资产清理证据已记录 |

## 按任务读

- 跨项目了解：CORE + RELATIONS，集成判断再读 SPEC。
- 修改产品方向：PRD + CORE + DECISIONS。
- 修改架构或安全状态机：ARCHITECTURE + DECISIONS + CORE。
- 实现监控：ARCHITECTURE + CONVENTIONS + PRD。
- 实现 Turbo 或 helper：CORE + ARCHITECTURE + SPEC + DEPLOYMENT + CONVENTIONS。
- 排期：ROADMAP。
- 发布或复盘：CHANGELOG 或 MEMORY。
