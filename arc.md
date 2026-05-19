# Agent Island - 产品架构文档

> 版本：v1.0.0  
> 最后更新：2026-05-20  
> 状态：初始架构设计

---

<!-- 
## 版本变更记录
| 版本 | 日期 | 变更内容 | 变更原因 |
|------|------|---------|---------|
| v1.0.0 | 2026-05-20 | 初始架构设计 | 项目启动，确定技术栈和系统边界 |
-->

## 1. 系统边界

### 1.1 部署形态
- **纯本地桌面应用**，无服务端
- 不联网（除非用户主动检查更新）
- 所有 Agent 通信发生在 localhost

### 1.2 运行环境
- macOS 14.0+ (Sonoma)
- 硬件要求：Apple Silicon 或 Intel Mac（有/无刘海均兼容）
- 分发方式：.dmg 安装包 或 Homebrew Cask

### 1.3 不涉及的范围
- 无用户账号系统
- 无云端数据同步
- 无后端服务器
- 无数据上报 / 遥测
- 无内购（MVP 阶段免费开源）

---

## 2. 隐私与合规

| 维度 | 策略 |
|------|------|
| 数据存储 | 所有配置存储在 `~/Library/Application Support/AgentIsland/`，不加密（用户可自查） |
| 网络通信 | 仅与本机 Agent 通信（127.0.0.1 / Unix Socket），不发起外网请求 |
| 用户代码 | 不读取、不存储、不传输用户项目代码。仅展示 Agent 输出的摘要片段 |
| 终端内容 | 仅监听 Agent 进程的输出流，不监听用户在终端中输入的其他命令 |
| 辅助功能权限 | 需要 Accessibility API 权限（仅用于窗口跳转和前台应用检测），在首次启动时向用户明确说明用途 |
| 日志 | 本地调试日志存储在 `~/Library/Logs/AgentIsland/`，不包含用户代码内容 |

---

## 3. 技术栈

| 层级 | 选型 | 版本要求 | 选型理由 |
|------|------|---------|---------|
| 语言 | Swift | 5.9+ | 原生性能，与 macOS API 无缝衔接，VibeIsland 同技术栈 |
| UI 框架 | SwiftUI + AppKit | macOS 14+ | SwiftUI 做声明式 UI，AppKit 控制窗口行为（level、position、tracking） |
| 状态管理 | Combine + @Observable | - | SwiftUI 原生响应式数据流 |
| 窗口管理 | NSPanel + NSWindow | - | 无边框置顶窗口，精确定位到刘海区 |
| 终端 Hook | FileHandle + DispatchSource + FSEvents | - | 监听 Agent 日志文件变化 |
| MCP 通信 | URLSession (HTTP JSON-RPC 2.0) | - | QoderWork MCP Adaptor 通信 |
| 进程管理 | NSRunningApplication + Process | - | 检测 Agent 进程状态 |
| 辅助功能 | Accessibility API (AXUIElement) | - | 窗口跳转、前台应用检测 |
| 构建系统 | Xcode + Swift Package Manager | Xcode 15+ | 标准 macOS 开发工具链 |
| 测试 | XCTest + Swift Testing | - | 单元测试 + UI 测试 |
| 分发 | Sparkle (自动更新) + DMG | - | 标准 macOS 应用分发 |

---

## 4. 系统架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Application Layer                            │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    UI Layer (SwiftUI)                         │   │
│  │  CompactBarView │ ExpandedPanelView │ SettingsView           │   │
│  └────────────────────────────┬────────────────────────────────┘   │
│                               │ @Observable binding                  │
│  ┌────────────────────────────┴────────────────────────────────┐   │
│  │                  State Layer (核心状态)                        │   │
│  │  SessionManager │ NotificationQueue │ SettingsStore           │   │
│  └────────────────────────────┬────────────────────────────────┘   │
│                               │                                      │
│  ┌────────────────────────────┴────────────────────────────────┐   │
│  │                  Adaptor Layer (Agent 适配层)                  │   │
│  │                                                              │   │
│  │  protocol AgentAdaptor {                                     │   │
│  │    func discoverSessions() async -> [AgentSession]           │   │
│  │    func getStatus(session: AgentSession) async -> Status     │   │
│  │    func getPending(session: AgentSession) async -> [Pending] │   │
│  │    func respond(session: AgentSession, ...) async            │   │
│  │    func jumpTo(session: AgentSession) async                  │   │
│  │  }                                                           │   │
│  │                                                              │   │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │   │
│  │  │ QoderWork    │ │ ClaudeCode   │ │ Codex        │        │   │
│  │  │ Adaptor      │ │ Adaptor      │ │ Adaptor      │        │   │
│  │  │ (MCP HTTP)   │ │ (File Hook)  │ │ (File Hook)  │        │   │
│  │  └──────────────┘ └──────────────┘ └──────────────┘        │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                  Infrastructure Layer                          │  │
│  │  WindowController │ AccessibilityService │ SoundPlayer        │  │
│  │  ProcessDetector  │ HotkeyManager        │ PersistenceStore   │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘

                    External (本机 localhost)
    ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
    │ QoderWork    │  │ Claude Code  │  │ Codex CLI    │
    │ MCP Adaptor  │  │ (Terminal)   │  │ (Terminal)   │
    │ :52345       │  │ ~/.claude/   │  │ ~/.codex/    │
    └──────────────┘  └──────────────┘  └──────────────┘
```

---

## 5. 核心模块职责

### 5.1 WindowController (窗口管理)
- 创建和管理 NSPanel（缩小态 + 扩展态）
- 刘海区物理尺寸检测和窗口定位
- NSTrackingArea 实现 hover 检测
- 展开/收起动画驱动
- 多显示器场景处理

### 5.2 SessionManager (会话管理)
- 统一管理所有 Agent 的活跃会话
- 定时调度各 Adaptor 的轮询任务
- 会话生命周期管理（创建、活跃、空闲、清理）
- 状态优先级聚合（为缩小态计算应显示哪个状态）

### 5.3 NotificationQueue (通知队列)
- 接收各 Agent 的待确认事件
- 按时间顺序排队
- 驱动面板展开/内容切换/收起
- 智能抑制规则判断

### 5.4 AgentAdaptor (适配器协议)
- 定义统一接口（见架构图）
- 每个 Agent 实现自己的 Adaptor
- 隔离 Agent 差异，上层无需关心具体 Agent 类型

### 5.5 AccessibilityService (辅助功能服务)
- 前台应用检测
- 目标窗口/Tab 查找
- AXRaise 窗口激活
- 权限状态检查和引导

---

## 6. Agent 适配器详细设计

### 6.1 QoderWorkAdaptor (MCP 模式)

```
通信方式: HTTP POST → 127.0.0.1:52345
协议: JSON-RPC 2.0
轮询间隔: 2 秒

核心调用:
- tools/call: qoder_list_tasks → 会话发现
- tools/call: qoder_get_task_detail → 状态查询
- tools/call: qoder_respond_task → 确认提交
- tools/call: qoder_send_message → 消息发送
- tools/call: qoder_cancel_task → 任务终止

状态映射:
  task.status == "running" && lastToolCall.state == "input-streaming" → 思考中
  task.status == "running" && lastToolCall.state == "result" → 执行中
  task.status == "running" && lastToolCall.state == "call" → 等待确认
  task.status == "idle" → 空闲/已完成
```

### 6.2 ClaudeCodeAdaptor (终端 Hook 模式)

```
监听路径: ~/.claude/projects/*/sessions/*.jsonl (推测)
监听方式: FSEvents 目录监控 + FileHandle 增量读取
轮询间隔: 1 秒（文件变化驱动，非定时轮询）

进程发现:
- NSRunningApplication 过滤 bundleId 包含 "terminal"/"iterm"/"ghostty"
- Process 查找 command 包含 "claude" 的进程
- 或直接监听 ~/.claude/ 目录变化发现新会话

状态解析:
- 解析 JSONL 行，提取 type 字段
- type == "thinking" → 思考中
- type == "tool_use" → 执行中
- type == "permission_request" → 等待确认，提取 diff 内容
- type == "ask" → 等待选择，提取选项列表
- type == "result" → 已完成

确认响应:
- 通过 stdin 写入 Y/N（权限审批）
- 通过 stdin 写入选项编号（选择题）
- 需要找到对应 PTY 的文件描述符

窗口跳转:
- 记录 session 对应的终端 PID + window/tab ID
- AXUIElement 定位到具体 tab
- AXRaise 激活
```

### 6.3 CodexAdaptor (终端 Hook 模式)

```
结构类似 ClaudeCodeAdaptor，差异点:
- 监听路径不同（~/.codex/ 或 Codex 特定日志路径）
- 输出格式解析器不同
- 会话生命周期：无明确结束信号，需要空闲超时清理（默认 2h）
- 后台会话过滤：Memory Consolidation / Memory Writer 等内部会话需过滤
```

---

## 7. 性能约束

| 指标 | 上限 | 监控方式 |
|------|------|---------|
| 常驻内存 | < 80MB | Instruments / Activity Monitor |
| CPU 空闲时 | < 1% | 无 Agent 活跃时几乎零开销 |
| CPU 轮询时 | < 3% | 多 Agent 活跃时的轮询负载 |
| 文件句柄 | < 50 | 同时监听的日志文件数量 |
| 启动时间 | < 2s | 冷启动到缩小态可见 |
| 动画帧率 | 60fps | 展开/收起动画期间 |
| 状态延迟 | < 3s | Agent 状态变化到 UI 更新 |

### 性能设计原则
- 无 Agent 活跃时不做任何轮询（零 CPU 开销）
- 文件监听使用 FSEvents（内核态通知，非轮询）
- MCP 轮询仅在 QoderWork 运行时激活
- SwiftUI 视图按需刷新（@Observable 精准绑定）
- 大文本截断显示，不做全量渲染

---

## 8. 数据流

### 8.1 Agent 状态轮询流

```
[Adaptor] ──(发现/轮询)──→ [SessionManager] ──(状态更新)──→ [UI View]
                                    │
                                    ├─ 状态变化 → 更新缩小态图标/文案
                                    ├─ 出现待确认 → NotificationQueue.enqueue()
                                    └─ 会话结束 → 清理 session 记录
```

### 8.2 用户确认流

```
[NotificationQueue] ──(展示待确认)──→ [UI ConfirmationView]
                                              │
                                    用户点击 Allow / 选择选项
                                              │
                                              ▼
[NotificationQueue] ──(调用 Adaptor)──→ [Adaptor.respond()] ──→ [Agent]
         │
         ├─ 队列非空 → 切换到下一个待确认（面板保持展开）
         └─ 队列为空 → 收起面板
```

### 8.3 设置持久化

```
[SettingsView] ──(用户修改)──→ [SettingsStore] ──(写入)──→ UserDefaults / .plist
                                      │
                                      └─ 通知各模块配置变更（Combine Publisher）
```

---

## 9. 项目目录结构（建议）

```
AgentIsland/
├── AgentIsland.xcodeproj
├── Sources/
│   ├── App/
│   │   ├── AgentIslandApp.swift          # 入口
│   │   └── AppDelegate.swift             # AppKit 生命周期
│   ├── UI/
│   │   ├── CompactBar/
│   │   │   ├── CompactBarView.swift
│   │   │   └── StatusIconView.swift
│   │   ├── ExpandedPanel/
│   │   │   ├── ExpandedPanelView.swift
│   │   │   ├── TaskListView.swift
│   │   │   ├── TaskCardView.swift
│   │   │   └── ConfirmationView.swift
│   │   ├── Settings/
│   │   │   ├── SettingsWindow.swift
│   │   │   └── Sections/
│   │   └── Onboarding/
│   │       └── OnboardingView.swift
│   ├── Core/
│   │   ├── SessionManager.swift
│   │   ├── NotificationQueue.swift
│   │   ├── SettingsStore.swift
│   │   └── Models/
│   │       ├── AgentSession.swift
│   │       ├── SessionStatus.swift
│   │       └── PendingConfirmation.swift
│   ├── Adaptors/
│   │   ├── AgentAdaptor.swift            # 协议定义
│   │   ├── QoderWorkAdaptor.swift
│   │   ├── ClaudeCodeAdaptor.swift
│   │   ├── CodexAdaptor.swift
│   │   └── OpenCodeAdaptor.swift
│   ├── Infrastructure/
│   │   ├── WindowController.swift
│   │   ├── AccessibilityService.swift
│   │   ├── ProcessDetector.swift
│   │   ├── HotkeyManager.swift
│   │   ├── SoundPlayer.swift
│   │   └── FileWatcher.swift
│   └── Utilities/
│       ├── MCPClient.swift               # JSON-RPC 2.0 封装
│       ├── NotchDetector.swift           # 刘海尺寸检测
│       └── Extensions/
├── Tests/
│   ├── CoreTests/
│   ├── AdaptorTests/
│   └── UITests/
├── Resources/
│   ├── Assets.xcassets
│   ├── Sounds/
│   └── PixelIcons/
└── Package.swift
```

---

## 10. 开发阶段规划

| Phase | 目标 | 核心模块 | 预期时长 |
|-------|------|---------|---------|
| Phase 1 | 壳子 + 单 Agent | WindowController + CompactBar + ExpandedPanel + QoderWorkAdaptor | 1-2 周 |
| Phase 2 | 多 Agent | ClaudeCodeAdaptor + CodexAdaptor + SessionManager | 1-2 周 |
| Phase 3 | 体验完善 | NotificationQueue + Settings + Sound + HotkeyManager | 1 周 |
| Phase 4 | 稳定性 | 测试 + 性能优化 + 边界场景处理 | 1 周 |

---

## 11. 关键技术风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| Claude Code 日志格式变更 | Claude Code 更新后解析器失效 | 解析器模块化，支持多版本格式；监控 Claude 更新日志 |
| macOS 版本兼容 | 新版 macOS 改变窗口行为 | CI 上跑多版本测试；关注 WWDC 变更 |
| 辅助功能权限被拒绝 | 窗口跳转功能不可用 | 优雅降级：仅激活应用不定位 tab；引导用户授权 |
| MCP Adaptor 端口变更 | QoderWork 通信中断 | 支持配置端口；自动探测常用端口 |
| 终端 App 多样性 | 不同终端的 tab/session 结构不同 | 优先支持 iTerm2 + Terminal.app，Ghostty/Warp 后续支持 |
