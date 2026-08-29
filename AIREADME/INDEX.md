# ThermalPulse · AIREADME
> macOS 热状态监控与限时 Turbo 散热工具 ｜ 生命周期: active, pre-alpha
> last-synced: 25eda8d · 2026-08-30

## 状态

| 文件 | 状态 | 摘要 |
|---|:--:|---|
| CORE | ✅ | 身份、边界与失效安全红线已确定 |
| RELATIONS | ✅ | 当前无其他项目依赖或共享底座 |
| SPEC | ✅ | 固定身份、协议 v1、持久 XPC、固定租约、写入读回与恢复契约已记录 |
| ARCHITECTURE | ✅ | 只读采样、产品界面、Turbo 安全控制器、受限写适配器与恢复链路已记录 |
| DEPLOYMENT | ⚑ | 最终 helper 已完成签名升级与首次短时实写，读回不一致后已验证安全恢复，Turbo 与卸载仍待验收 |
| PRD | ✅ | 菜单栏直读、无侧栏单页监控和 Turbo 限时的产品意图已确定 |
| ROADMAP | ✅ | helper 安全引擎与系统升级已完成，下一阶段为定位首次实写读回不一致并增加可诊断证据 |
| CONVENTIONS | ✅ | 传感器、采样、曲线、租约先行、动态风扇写入、读回与测试约定已确定 |
| DECISIONS | ✅ | 只读基线、界面、固定身份、显式注册和 fail-safe 写入决策已记录 |
| MEMORY | ✅ | 已记录 SMC ABI、浮点字节序、性能、SMAppService、升级竞态、模式 key、签名门禁与首次实写失败保护踩坑 |
| CHANGELOG | ✅ | 已记录只读、界面、注册 XPC、Turbo 安全引擎、helper 升级与首次短时实写里程碑，尚无 release |

## 按任务读

- 跨项目了解：CORE + RELATIONS，集成判断再读 SPEC。
- 修改产品方向：PRD + CORE + DECISIONS。
- 修改架构或安全状态机：ARCHITECTURE + DECISIONS + CORE。
- 实现监控：ARCHITECTURE + CONVENTIONS + PRD。
- 实现 Turbo 或 helper：CORE + ARCHITECTURE + SPEC + DEPLOYMENT + CONVENTIONS。
- 排期：ROADMAP。
- 发布或复盘：CHANGELOG 或 MEMORY。
