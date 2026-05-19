# Agent Island - 开发工作指引

## 项目概览

Agent Island 是一款嵌入 Mac 刘海区的多 AI Agent 状态聚合器，用户无需切换窗口即可实时查看所有 Agent 运行状态并完成交互确认。

- **技术栈：** Pure Swift 5.9+ / SwiftUI + AppKit / macOS 14+ (Sonoma)
- **构建系统：** Xcode 15+ / Swift Package Manager
- **Bundle ID：** com.agentisland.app
- **无外部依赖（MVP 阶段）**

---

## 关键文档索引

| 类别 | 文件路径 | 说明 |
|------|---------|------|
| 产品需求 | `prd.md` | 功能列表、验收标准、用户流程 |
| 视觉设计 | `design.md` | 色彩系统、布局规格、动效规范 |
| 技术架构 | `arc.md` | 四层架构、模块职责、数据流 |
| 项目进展 | `project.md` | 当前阶段、里程碑、阻塞项 |
| 竞品参考 | `reference.md` | VibeIsland 分析、开源项目、截图 |
| 开发工作流 | `docs/dev-workflow.md` | 如何开始/执行/验证/收尾 |
| 编码规范 | `docs/swift-standards.md` | 命名、文件组织、并发、错误处理 |
| UI 组件规格 | `docs/ui-component-spec.md` | 颜色 token、字体、尺寸、动画常量 |
| 适配器契约 | `docs/agent-adaptor-protocol.md` | 协议定义、QoderWork 映射、轮询策略 |
| 测试策略 | `docs/testing-strategy.md` | 测试金字塔、Mock 模式、验证清单 |
| 开发日志 | `devlog/` | 每日完成事项和待办 |

---

## 开发工作流（简述）

1. **开始工作前** → 阅读 `devlog/` 最新条目 + `project.md` 确认当前步骤
2. **创建功能分支** → `git checkout -b step/N-description` 从 main 拉出
3. **设计测试用例** → 编码前先明确模块的测试场景（正常/边界/错误）
4. **编码** → 参照对应的 docs/ 规范文件，每个逻辑变更一次 commit
5. **模块化测试验收** → build 通过 + 单元测试全部通过 + 手动验证匹配验收标准
6. **合并到主分支** → 验证通过后 `git checkout main && git merge step/N-description`
7. **收尾** → 创建/更新当天 `devlog/YYYY-MM-DD.md` + 更新 `project.md`

完整流程见 `docs/dev-workflow.md`。

---

## Git 版本管理准则

- **主分支 `main` 始终稳定可运行**，只接受验证通过的合并
- **每个 Step 在独立功能分支上开发**，命名 `step/N-description`
- **每次 commit 都是可回滚节点**，message 清晰描述变更
- **合并后打 tag**：`git tag step-N-done`
- **不删除已合并分支**，保留完整开发历史方便回溯

---

## 编码标准（摘要）

- 使用 `@Observable`（不用 ObservableObject）
- 使用 `async/await`（不用 completion handler）
- UI 变更标 `@MainActor`
- 文件 < 200 行
- 不写不必要的注释
- 不用 force unwrap
- 颜色/尺寸使用 `DesignTokens` 常量
- 依赖注入通过 `.environment()`，不用单例

完整规范见 `docs/swift-standards.md`。

---

## 架构规则

- **单向数据流：** Adaptor → SessionManager → UI
- **协议隔离：** UI 层不 import 具体 Adaptor 实现
- **依赖注入：** 通过 SwiftUI environment，不用单例
- **适配器模式：** 新增 Agent 只需实现 `AgentAdaptor` 协议

---

## Devlog 强制规则

**每次工作结束必须创建/更新当天的 devlog 文件。**

- 文件路径：`devlog/YYYY-MM-DD.md`
- 使用 `devlog/template.md` 作为模板
- Git pre-commit hook 会检查当天 devlog 是否存在，未创建则阻止提交

---

## Commit 消息格式

```
<type>: <subject>
```

type 取值：`feat:` / `fix:` / `refactor:` / `test:` / `docs:` / `chore:`

---

## 禁止事项

- 不添加外部 package 依赖（除非明确批准）
- 不在新代码中使用 Combine publisher
- 不添加 analytics/telemetry/外网请求
- 不读取/存储用户源代码内容
- 不提交无法编译的代码
- 不跨 Step 实现功能（保持增量）
- 不硬编码 magic number
- 不创建 God object
- 不使用 `try?` 静默吞掉错误
- 不使用 `!` force unwrap

---

## 当前开发阶段

**Phase 1 — 壳子 + 单 Agent (QoderWork)**

| Step | 状态 | 描述 |
|------|------|------|
| 0 | ✅ | 项目脚手架 |
| 1 | 🔲 | 刘海区窗口定位 |
| 2 | 🔲 | 缩小态静态 UI |
| 3 | 🔲 | Hover 展开收起 |
| 4 | 🔲 | MCP 客户端 |
| 5 | 🔲 | QoderWork 适配器 |
| 6 | 🔲 | 适配器接入 UI |
| 7 | 🔲 | 确认交互面板 |
| 8 | 🔲 | 端到端联调 |
