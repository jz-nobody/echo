# Agent Island

> 一款嵌入 Mac 刘海区的多 AI Agent 状态聚合器 —— 不切窗口，实时掌控所有编程 Agent 的运行状态并完成交互确认。

Agent Island 常驻在 Mac 顶部刘海区。当你在浏览网页、写文档、做其他工作时，无需打开各个 Agent 的对话界面，即可实时查看所有 AI 编程 Agent 的执行状态、接收完成通知、并直接在刘海面板里完成权限审批与选择应答。

---

## 支持的 Agent

| Agent | 接入方式 | 状态 |
|-------|---------|------|
| **Claude Code** | 会话文件监听（`~/.claude/sessions`）+ IPC hook | ✅ |
| **Codex** | SQLite 会话发现（`state_5.sqlite`）+ hook；子 agent 归并到父任务 | ✅ |
| **QoderWork** | MCP HTTP API + hook | ✅ |
| **Qoder** | 会话文件监听 + hook | ✅ |
| OpenCode / Gemini CLI | 规划中 | 🔲 |

## 核心功能

- **刘海区常驻**：缩小态显示聚合状态，hover 展开完整会话列表
- **实时状态**：就绪 / 思考 / 查询 / 编辑 / 运行 / 压缩 / 询问 / 完成，多 Agent 聚合
- **交互确认**：权限审批面板（diff 预览、快捷键）+ 选择题面板（单选 / 多选 / 自由文本）
- **子任务归并**：并行 spawn 的子 agent 归到父任务的 subagent 列表，不刷屏
- **智能抑制**：当你正盯着某 Agent 的终端时不弹面板
- **点击跳转**：点会话即跳到对应 Agent 的终端窗口（Accessibility API）
- **像素宠物动画** + **音效系统**：按状态切换的桌宠与声音提示
- **通知过滤** + **开机自启**

> 完全免费，无需激活码。

*English: [README.en.md](README.en.md)*

## 技术栈

- **语言**：Pure Swift 5.9+
- **UI**：SwiftUI + AppKit（NSPanel 实现刘海级窗口）
- **平台**：macOS 14+ (Sonoma)，Apple Silicon + Intel universal
- **构建**：Swift Package Manager
- **依赖**：无外部依赖
- **Bundle ID**：`com.agentisland.app`

## 架构

单向数据流，协议隔离，依赖注入（SwiftUI environment，无单例）：

```
各 Agent 数据源 (hook / 文件 / SQLite / MCP)
        │
   BridgeServer (actor, 中央 dispatch)
        │
   SessionManager (@MainActor @Observable)
        │
        UI (刘海条 / 展开面板 / 确认面板)
```

- **BridgeServer**：actor，按 Agent 类型 dispatch hook，维护会话/确认状态
- **IPC**：Unix domain socket，CLI 侧 `agent-island-bridge` 转发 hook 事件
- **SessionManager**：轮询 + hook 通知双路径驱动 UI

详见 [`arc.md`](arc.md)（架构）、[`prd.md`](prd.md)（需求）、[`design.md`](design.md)（视觉/交互）。

## 构建与运行

```bash
# 开发构建 + 测试
cd AgentIsland
swift build
swift test

# 打正式包（universal DMG）
./scripts/build-dmg.sh   # 从仓库根目录运行，产物在 build/Echo.dmg
```

首次打开 ad-hoc 签名的 app：右键 → 打开，或在「系统设置 → 隐私与安全性」中放行。

## 开发规范

- `@Observable`（不用 ObservableObject）、`async/await`（不用 completion handler）
- UI 变更标 `@MainActor`；单文件 < 200 行
- 不用 force unwrap / `try?` 静默吞错；颜色尺寸走 `DesignTokens`
- 每个 Step 独立功能分支，`main` 始终稳定可运行
- 每次工作结束更新 `devlog/YYYY-MM-DD.md`

完整规范见 [`CLAUDE.md`](CLAUDE.md) 与 [`docs/`](docs/)。

## 目录结构

```
AgentIsland/
  Sources/
    App/            应用入口 (SwiftUI + AppKit 生命周期)
    Core/           BridgeServer / SessionManager / 模型 / 业务逻辑
    Adaptors/       Claude Code 会话解析
    Infrastructure/ 窗口 / IPC / hook 安装 / Keychain / 设置
    Networking/     MCP 客户端 (JSON-RPC)
    UI/             刘海条 / 展开面板 / 确认面板 / 设置 / 动画
  Tests/            365+ 单元与集成测试
  BridgeCLI/        agent-island-bridge (hook 转发 CLI)
scripts/build-dmg.sh
docs/               工作流 / 编码规范 / 适配器契约 / 测试策略
devlog/             每日开发日志
```

## 许可

私有项目，保留所有权利。
