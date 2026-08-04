# Echo

> 一款嵌入 Mac 刘海区的多 AI Agent 状态聚合器 —— 不切窗口，实时掌控所有编程 Agent 的运行状态并完成交互确认。

Echo 常驻在 Mac 顶部刘海区。当你在浏览网页、写文档、做其他工作时，无需打开各个 Agent 的对话界面，即可实时查看所有 AI 编程 Agent 的执行状态、接收完成通知、并直接在刘海面板里完成权限审批与选择应答。

> 完全免费，无需激活码。

*English: [README.en.md](README.en.md)*

---

## 目录

- [使用场景](#使用场景)
- [支持的 Agent](#支持的-agent)
- [功能](#功能)
- [状态种类](#状态种类)
- [技术栈](#技术栈)
- [架构](#架构)
- [构建与运行](#构建与运行)
- [目录结构](#目录结构)
- [开发约定](#开发约定)
- [许可](#许可)

## 使用场景

同时跑多个 AI 编程 Agent（Claude Code / Codex / QoderWork / Qoder）做并行开发时，你往往要在多个终端/窗口间来回切换，才能知道"哪个在跑、哪个卡在等你确认、哪个已经完成"。Echo 把这些状态聚合到刘海区一处：

- 缩小态：一眼看到聚合状态（有没有 Agent 在等你、有没有跑完）
- 展开态：完整会话列表 + 每个会话的当前动作、待办、子任务
- 需要审批/回答时：直接在刘海面板处理，不用切回对应终端

## 支持的 Agent

| Agent | 接入方式 | 状态 |
|-------|---------|------|
| **Claude Code** | 监听 `~/.claude/sessions` 会话文件 + IPC hook；从 JSONL transcript 解析标题/待办/子任务 | ✅ |
| **Codex** | 读取 `~/.codex/state_5.sqlite`（只读）发现会话 + hook；并行 spawn 的子 agent 按 `parent_thread_id` 归并到父任务的 subagent 列表，不刷屏 | ✅ |
| **QoderWork** | MCP HTTP API（`127.0.0.1`）+ hook；多 chat 合并到 workspace 会话 | ✅ |
| **Qoder** | 监听 `~/.qoder/projects` transcript + hook | ✅ |
| OpenCode / Gemini CLI | 规划中 | 🔲 |

各 Agent 通过安装到 `~/.agent-island/bin/agent-island-bridge` 的 hook 桥接程序，把 PreToolUse / PostToolUse / UserPromptSubmit / Stop / SubagentStart 等事件经 Unix domain socket 转发给主程序。桥接不可达时回退为中性放行（`{}`），不阻塞 Agent 正常运行。

## 功能

- **刘海区常驻**：缩小态显示聚合状态，hover 展开完整会话列表

<img width="368" height="240" alt="001" src="https://github.com/user-attachments/assets/bd9e7497-1ba8-421b-ae35-34de71909661" />

- **实时状态**：多 Agent 状态聚合，按优先级汇总（等待确认 > 运行 > 完成 > 就绪）
- **权限审批面板**：diff 预览、允许 / 拒绝、键盘快捷键、"始终允许"、自动批准

<img width="368" height="240" alt="8月4日(3)" src="https://github.com/user-attachments/assets/5ec10403-cbae-48ea-8dd6-ca4ac8a0a104" />

- **选择题面板**：单选 / 多选 / 自由文本输入，支持一次多问的分组应答

<img width="368" height="240" alt="8月4日" src="https://github.com/user-attachments/assets/8cb111df-560e-4f0e-a18a-7c8e54618718" />
<img width="368" height="240" alt="8月4日(1)" src="https://github.com/user-attachments/assets/ff3b8182-04d5-4d6c-bd9d-29d4e9dca551" />

- **确认队列**：多个 Agent 的确认请求排队处理
- **子任务归并**：并行子 agent 归到父任务的 subagent 列表，显示活跃subagent执行状态，并自动归纳
- **智能抑制**：当你正盯着某 Agent 的终端时不弹面板（前台应用检测）
- **点击跳转**：点会话即跳到对应 Agent 的终端窗口（Accessibility API）
  <img width="368" height="240" alt="8月4日(2)" src="https://github.com/user-attachments/assets/29f5a93e-6492-4aad-bdb9-a8eea50997a2" />
  
- **像素宠物动画**：按状态切换的桌宠（就绪 / 运行 / 压缩 / 询问）
- **音效系统**：完成 / 询问 / 压缩完成 / 空闲提醒等事件音，可配置
- **通知过滤**：按标题关键字过滤噪音会话
- **开机自启**：登录时自动运行 Echo

## 状态种类

| 状态 | 含义 |
|------|------|
| `idle` 就绪 | 空闲等待 |
| `thinking` 思考中 | 模型推理中 |
| `reading` 查询中 | 读取类工具（Read/Grep/Glob/WebFetch…） |
| `editing` 编辑中 | 写入类工具（Edit/Write…） |
| `executing` 运行中 | 执行类工具（Bash 等） |
| `compacting` 压缩中 | 上下文压缩 |
| `waitingConfirmation` 询问中 | 等待你审批/回答（最高优先级） |
| `completed` 已完成 | 本轮结束 |

进程存活检测：活跃态会话若其 Agent 进程已退出，会被转为就绪/清理，避免因网络中断等原因卡在"运行中"。

## 技术栈

- **语言**：Pure Swift 5.9+
- **UI**：SwiftUI + AppKit（NSPanel 实现刘海级窗口定位）
- **平台**：macOS 14+ (Sonoma)，Apple Silicon + Intel universal
- **构建**：Swift Package Manager
- **依赖**：无外部依赖
- **Bundle ID**：`com.agentisland.app`

## 架构

单向数据流，协议隔离，依赖注入（通过 SwiftUI environment，无单例）：

```
各 Agent 数据源  (hook 事件 / 会话文件 / SQLite / MCP)
        │
   BridgeServer          actor，中央 dispatch：按 Agent 类型路由 hook，
        │                维护会话状态机与确认队列
        ▼
   SessionManager        @MainActor @Observable：轮询 + hook 通知双路径
        │                驱动 UI，做会话过滤 / 声音事件 / 空闲提醒
        ▼
        UI               刘海条 / 展开面板 / 确认面板 / 设置窗口
```

- **BridgeServer（actor）**：所有会话/确认状态的单一持有者。按 tag dispatch 各 Agent 的 hook；`discoverAllSessions()` 每轮做会话发现、过期清理、进程存活检测。
- **IPC**：`IPCServer` 监听 Unix domain socket，CLI 侧 `agent-island-bridge` 转发 hook 的 JSON 消息；`HookInstaller` 负责把 hook 装进各 Agent 的 settings。
- **SessionManager**：`@Observable`，`pollOnce()` 定时轮询（活跃 1s / 空闲 5s）+ 监听 `statusChanged` 通知即时更新；`SessionEventDetector` 产出声音事件，`SessionFilter` 过滤噪音。
- **会话状态机**：`SessionState.apply(_ event:)` 把 hook 事件（UserPromptSubmit/PreToolUse/PostToolUse/Stop/PreCompact/PermissionRequest…）映射为 `SessionStatus`，`waitingConfirmation` 时屏蔽进度事件覆盖。
- **协议隔离**：UI 不 import 具体数据源实现；新增 Agent 只需在 `AgentConfig` 注册并接入 dispatch。

## 构建与运行

```bash
# 开发构建 + 测试（365+ 单元与集成测试）
cd AgentIsland
swift build
swift test

# 打正式包（universal DMG）
./scripts/build-dmg.sh   # 从仓库根目录运行，产物在 build/Echo.dmg
```

首次打开 ad-hoc 签名的 app：右键 → 打开，或在「系统设置 → 隐私与安全性」中放行；也可 `xattr -cr /Applications/Echo.app`。

首次运行会把 hook 桥接程序安装到 `~/.agent-island/bin/`，并把 hook 注册进检测到的 Agent 的配置文件（`~/.claude/settings.json`、`~/.codex/hooks.json` 等）。

## 目录结构

```
AgentIsland/                 Swift Package（内部模块名保留 AgentIsland）
  Sources/
    App/            应用入口 (SwiftUI + AppKit 生命周期)
    Core/           BridgeServer / SessionManager / 状态机 / 模型 / 业务逻辑
    Adaptors/       Claude Code 会话/日志解析
    Infrastructure/ 窗口 / IPC / hook 安装 / 设置 / 刘海检测
    Networking/     MCP 客户端 (JSON-RPC)
    UI/             刘海条 / 展开面板 / 确认面板 / 设置 / 宠物与状态动画
  Tests/            365+ 单元与集成测试
  BridgeCLI/        agent-island-bridge (hook 转发 CLI)
  Resources/        图标 / 音效 / SVG 动画
scripts/build-dmg.sh         打包脚本（产出 Echo.app / Echo.dmg）
```

> 说明：应用对外品牌为 **Echo**；内部 Swift 模块与目录仍名为 `AgentIsland`，Bundle ID `com.agentisland.app`。

## 开发约定

- 用 `@Observable`（不用 `ObservableObject`）、`async/await`（不用 completion handler）
- UI 变更标 `@MainActor`；单文件 < 200 行
- 不用 force unwrap / 不用 `try?` 静默吞错；颜色尺寸走 `DesignTokens`
- 依赖注入通过 `.environment()`，不用单例
- 不加外部 package 依赖；不加 analytics / 外网请求；不读取用户源代码内容
- `main` 始终稳定可运行，每次 commit 都是可回滚节点

## 许可

私有项目，保留所有权利。
