# 灵动岛多 Agent 聚合产品 - 技术可行性评估 v2

## 产品定位

一个嵌入 Mac 刘海区（Notch / Dynamic Island）的多 Agent 状态聚合器，实时展示所有正在运行的 AI Agent（Claude Code、Codex、QoderWork 等）的工作状态，支持用户在不打开 Agent 原始界面的情况下完成审批、确认和消息发送操作。

对标产品：**VibeIsland**（vibeisland.app）

---

## 一、产品形态分析（基于参考图反推）

### 1.1 缩小态（Compact Mode）

参考「运行中.jpg」和「已完成.jpg」：

- 嵌入刘海区右侧，与系统刘海融为一体
- 显示内容：agent 像素图标 + 状态文案（"运行中"/"已完成"）+ 活跃会话数
- 状态通过图标颜色/动画区分：蓝色动画=运行中，绿色静止=已完成
- 宽度约 200-300pt，高度与刘海一致（约 32pt）

### 1.2 扩展态（Expanded Mode）

参考「运行中hover.jpg」和「多agent列表.JPG」和「点击任务唤起agent.jpg」：

- hover 触发下拉面板展开，最大高度约 560pt，最大宽度约 640pt
- 每个任务卡片包含：agent 名称标签（Claude/Codex/Gemini）、终端标签（iTerm/Terminal/Ghostty）、任务标题、用户上一轮输入摘要、执行时长、当前状态
- 支持"自动批准"模式切换
- 点击任务卡片 → 唤起对应 agent 的终端/IDE 并跳转到该会话（"Done — click to jump"）
- 展示子代理详情（"子代理 (2): Explore (Search API endpoints) 8s..."）

### 1.3 确认交互态

参考「用户确认项.jpg」和「用户确认项2.jpg」：

- Permission Request：显示文件 diff（红/绿行），底部 Deny / Allow 按钮，支持 Cmd+N / Cmd+Y 快捷键
- 选择类问题：显示选项列表，支持 Cmd+1/2/3 快捷键直接选择

### 1.4 设置面板（反推技术实现）

从设置图中可提取的关键技术信息：

| 设置项 | 技术含义 |
|--------|---------|
| 登录时打开 | Launch at Login（`SMLoginItemSetEnabled` / `ServiceManagement`） |
| 悬停延迟 0.15s | `NSTrackingArea` + 延迟触发，非即时展开 |
| 智能抑制：Agent 所在终端在前台时不自动展开 | 需要监听前台应用切换（`NSWorkspace.didActivateApplicationNotification`） |
| 全屏时隐藏 | 监听屏幕模式变化（`NSWindow.didEnterFullScreenNotification`） |
| 鼠标离开时自动收起 | `NSTrackingArea` 的 `mouseExited` 事件 |
| 自动提醒停留时长 5s | 完成/警告提醒的自动关闭定时器 |
| 空闲会话自动清理 2h（Codex、OpenCode、Cursor） | 不同 agent 的会话生命周期管理 |
| 禁用点击跳转 | 可选关闭 `NSWorkspace.openApplication` + AXRaise 行为 |
| 刘海宽度/高度微调 | `NSScreen.frame` + 物理刘海尺寸检测 |
| 显示代理活动详情（子代理） | agent 工具调用的实时流式监听 |
| 集成：支持 Claude/Codex/Gemini/OpenCode | 多 agent 适配器架构 |
| SSH 远程 | 支持远程终端会话监控 |
| 通知过滤（Codex Memory Consolidation 等） | 基于 prompt 前缀 / 工作目录的规则引擎 |
| 声音（会话开始/任务完成/任务错误/需要审批/任务确认） | 状态机转换时触发音效 |

---

## 二、核心技术架构

### 2.1 整体架构图

```
┌─────────────────────────────────────────────────────────────┐
│                    Notch UI Layer (SwiftUI + AppKit)          │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────────┐      │
│  │ 缩小态    │  │ 扩展态面板    │  │ 确认交互面板      │      │
│  │ Compact  │  │ Task List    │  │ Permission/Choice │      │
│  └──────────┘  └──────────────┘  └───────────────────┘      │
└────────────────────────┬────────────────────────────────────┘
                         │ @Published 状态驱动
┌────────────────────────┴────────────────────────────────────┐
│                    Session Manager (核心调度层)                │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐       │
│  │ Session │  │ Session │  │ Session │  │ Session │       │
│  │ Claude  │  │ Codex   │  │ QoderW  │  │ Gemini  │       │
│  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘       │
└───────┼─────────────┼───────────┼─────────────┼─────────────┘
        │             │           │             │
┌───────┴─────────────┴───────────┴─────────────┴─────────────┐
│                    Agent Adaptor Layer (适配层)                │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Terminal Hook │  │ MCP Client   │  │ File Watcher │       │
│  │ (PTY Monitor)│  │ (HTTP/IPC)   │  │ (FSEvents)   │       │
│  │              │  │              │  │              │       │
│  │ Claude Code  │  │ QoderWork    │  │ Cursor       │       │
│  │ Codex        │  │              │  │ (IDE 日志)   │       │
│  │ OpenCode     │  │              │  │              │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
└──────────────────────────────────────────────────────────────┘
```

### 2.2 技术栈选择

| 层级 | 技术 | 理由 |
|------|------|------|
| UI | Swift + SwiftUI + AppKit | 原生性能，刘海区精确绑定，VibeIsland 也是 Pure Swift |
| 状态管理 | Combine + @Published | SwiftUI 原生数据流 |
| Terminal Hook | PTY 输出监听 | 终端类 agent 的核心接入方式 |
| MCP 通信 | URLSession + JSON-RPC | QoderWork 接入 |
| 文件监听 | FSEvents / DispatchSource | IDE 类 agent 的日志监控 |
| 窗口跳转 | NSWorkspace + Accessibility API | 点击跳转到 agent 会话 |
| 进程管理 | NSRunningApplication | 检测 agent 进程是否在运行 |

---

## 三、Agent 接入层技术可行性（关键）

### 3.1 Claude Code — Terminal Hook 模式

**原理：** Claude Code 运行在终端（iTerm2、Terminal、Ghostty 等）中，其输出是结构化的 ANSI 文本流。通过监听终端进程的 PTY（伪终端）输出，可以实时捕获 agent 状态。

**具体实现路径：**

方案 A：**终端输出日志文件监听**
- Claude Code 在 `~/.claude/` 下会产生会话日志
- 用 FSEvents 监听日志文件变化，解析新增内容
- 提取状态变化（thinking → tool_use → awaiting_input）
- VibeIsland 和 open-vibe-island 就是用这种方式

方案 B：**PTY 子进程代理**
- 启动一个中间层 PTY proxy，fork 原始终端进程
- 所有输入输出经过 proxy 层时被捕获和解析
- 性能更好，但侵入性强

方案 C：**Claude Code CLI Hook / 事件 API**
- Claude Code 可能提供 `--emit-events` 或类似的 hook 机制
- VibeIsland 官网提到 "zero config local CLI hooks"
- 这是最干净的方式，依赖 Claude 官方支持

**推荐：方案 A + C 结合。** 先用文件/日志监听做 MVP，等 Claude 官方 hook API 稳定后切换。

**状态解析逻辑：**
```
日志中出现 "Thinking..." → 状态 = thinking
日志中出现 "Running tool:" → 状态 = executing  
日志中出现 "Permission required" → 状态 = waiting_confirm, 提取 diff 内容
日志中出现 "?" 或选项列表 → 状态 = waiting_choice, 提取选项
日志中出现用户 prompt → 状态 = idle (完成上一轮)
```

**可行性：高。** VibeIsland 已经验证了这个路径可行，且有开源替代（open-vibe-island）可参考。

### 3.2 Codex — Terminal Hook 模式

与 Claude Code 类似，Codex 也是 CLI 工具运行在终端中。

- Codex 的输出结构与 Claude Code 不同，需要单独写解析器
- 设置图中提到 "空闲会话自动清理 2h（Codex、OpenCode、Cursor）"，说明 Codex 的会话生命周期管理与 Claude 不同
- 通知过滤中有 "Codex Memory Consolidation" 等内置规则

**可行性：高。** 同样是终端 hook 模式，已被 VibeIsland 验证。

### 3.3 QoderWork — MCP 客户端模式

这是我们之前已经验证的路径，且是最干净的：

- HTTP 连接 `127.0.0.1:52345`
- `qoder_list_tasks` → 发现活跃任务
- `qoder_get_task_detail` → 轮询状态
- `qoder_send_message` → 发送用户输入
- `qoder_respond_task` → 提交确认/选择
- `qoder_start_task` → 创建新任务
- `qoder_cancel_task` → 终止任务

**可行性：完全可行。** 已通过实际探测验证，工具链完整。

### 3.4 Cursor / Windsurf — IDE 日志监听模式

Cursor 基于 VS Code，其 agent 交互记录在特定日志文件中：

- `~/Library/Application Support/Cursor/logs/` 下的日志文件
- 或通过 Cursor 的 Extension API 暴露的事件（如果有）
- 也可能需要监听 Cursor 的内部 WebSocket 通信

**可行性：中。** 比终端 hook 复杂，需要逆向 Cursor 的日志格式。VibeIsland 尚未完全支持 Cursor（从设置图看主要支持 Claude/Codex/OpenCode/Gemini）。

### 3.5 适配器模式总结

| Agent | 接入方式 | 可行性 | 复杂度 |
|-------|---------|--------|--------|
| Claude Code | Terminal 日志/PTY hook | 高 | 中 |
| Codex | Terminal 日志/PTY hook | 高 | 中 |
| QoderWork | MCP HTTP API | 高 | 低 |
| OpenCode | Terminal 日志 | 高 | 中 |
| Gemini | Terminal 日志 | 高 | 中 |
| Cursor | IDE 日志监听/Extension | 中 | 高 |

---

## 四、刘海区 UI 技术可行性

### 4.1 macOS Notch 区域渲染

macOS 不提供官方的 "Dynamic Island" API。VibeIsland 和类似产品使用的是：

**无边框置顶窗口 + 精确定位到刘海区旁边**

```swift
// 获取刘海区物理尺寸
let screen = NSScreen.main!
let notchHeight: CGFloat = 32 // 或通过 screen.auxiliaryTopLeftArea 检测
let notchWidth: CGFloat = screen.frame.width * 0.25 // 约 1/4 屏幕宽

// 创建无边框窗口，level 设置为超越菜单栏
let window = NSPanel(
    contentRect: NSRect(x: notchX, y: screen.frame.height - notchHeight, 
                        width: barWidth, height: notchHeight),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
window.level = .statusBar + 1  // 高于菜单栏
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = false
window.ignoresMouseEvents = false  // 缩小态可响应 hover
```

**设置图中的"刘海宽度/高度微调"** 证实了这个实现方式——通过 macOS API 检测物理刘海尺寸，然后将窗口精确贴合。

### 4.2 Hover 展开/收起动效

```swift
// NSTrackingArea 监听鼠标进入/离开
let trackingArea = NSTrackingArea(
    rect: bounds,
    options: [.mouseEnteredAndExited, .activeAlways],
    owner: self
)

// 延迟展开（设置中可配置 0.15s）
func mouseEntered(with event: NSEvent) {
    expandTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
        withAnimation(.spring(response: 0.3)) {
            self.isExpanded = true
            self.updateWindowFrame(expanded: true)
        }
    }
}

func mouseExited(with event: NSEvent) {
    expandTimer?.invalidate()
    withAnimation(.spring(response: 0.3)) {
        self.isExpanded = false
        self.updateWindowFrame(expanded: false)
    }
}
```

### 4.3 点击跳转到 Agent 会话

从「点击任务唤起agent.jpg」中的 "Done — click to jump" 可以看出，产品支持点击后跳转到对应终端的对应 tab/session。

```swift
// 1. 通过 NSWorkspace 激活目标应用
NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/iTerm.app"))

// 2. 通过 Accessibility API 定位到具体的 tab/session
let app = AXUIElementCreateApplication(pid)
// 遍历窗口和 tab，找到匹配的会话
// 发送 AXRaise 将窗口带到前台
```

### 4.4 快捷键支持

确认面板中的 Cmd+Y（Allow）、Cmd+N（Deny）、Cmd+1/2/3（选择选项）：

```swift
// NSEvent.addLocalMonitorForEvents 或 CGEvent tap
NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    if event.modifierFlags.contains(.command) {
        switch event.keyCode {
        case 16: // Y → Allow
            self.respondAllow()
        case 45: // N → Deny  
            self.respondDeny()
        case 18...20: // 1,2,3 → 选择选项
            self.selectOption(event.keyCode - 18)
        }
    }
    return event
}
```

---

## 五、核心交互流程技术实现

### 5.1 任务完成自动展开 + 排队确认机制

你描述的场景："agent 任务执行完成后，产品从缩小态自动变为扩展态，展示待确认项。多个 agent 返回结果时按时间排队，逐个确认。"

```swift
class NotificationQueue: ObservableObject {
    @Published var pendingConfirmations: [AgentConfirmation] = []
    @Published var currentConfirmation: AgentConfirmation?
    
    // agent 完成时入队
    func enqueue(_ confirmation: AgentConfirmation) {
        pendingConfirmations.append(confirmation)
        if currentConfirmation == nil {
            showNext()
        }
    }
    
    // 用户确认后自动展示下一个（无收起再展开的动效）
    func confirmCurrent(choice: String) {
        currentConfirmation?.respond(choice)
        pendingConfirmations.removeFirst()
        if pendingConfirmations.isEmpty {
            currentConfirmation = nil
            collapse() // 全部确认完毕，收起
        } else {
            // 直接切换到下一个（面板保持展开，内容替换）
            showNext()
        }
    }
    
    private func showNext() {
        currentConfirmation = pendingConfirmations.first
        expand() // 确保面板是展开的
    }
}
```

### 5.2 智能抑制逻辑

设置中的 "Agent 所在终端标签页在前台时不自动展开"：

```swift
// 监听前台应用变化
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification,
    object: nil, queue: .main
) { notification in
    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
    
    // 如果当前前台是 agent 所在的终端，抑制自动展开
    if self.isAgentTerminal(bundleId: app.bundleIdentifier) {
        self.suppressAutoExpand = true
    } else {
        self.suppressAutoExpand = false
    }
}
```

---

## 六、总体可行性评级

| 维度 | 可行性 | 说明 |
|------|--------|------|
| 刘海区 UI 实现 | **高** | 无边框置顶窗口方案成熟，VibeIsland 已验证 |
| Hover 展开/收起 | **高** | NSTrackingArea + 动画，标准 macOS 开发模式 |
| 点击跳转 agent 会话 | **高** | NSWorkspace + AXRaise，需要辅助功能权限 |
| Claude Code 接入 | **高** | 终端日志/hook 监听，已有成熟开源方案 |
| Codex 接入 | **高** | 同上 |
| QoderWork 接入 | **高** | MCP HTTP API，工具链完整，已实测 |
| 待办确认交互 | **高** | diff 展示 + 按钮 + 快捷键，纯 UI 层实现 |
| 多 agent 排队确认 | **高** | 队列模式 + 状态机，纯逻辑层实现 |
| 通知过滤/规则引擎 | **中-高** | 正则匹配 + 目录匹配，复杂度可控 |
| 整体产品 | **完全可行** | VibeIsland 已经完整验证了这个产品形态 |

---

## 七、与 VibeIsland 的竞争差异化分析

你的产品本质上是 VibeIsland 的竞品。从技术角度看两者能力基本对等，差异化应该在：

| 维度 | VibeIsland | 你的产品机会 |
|------|-----------|-------------|
| Agent 覆盖 | Claude/Codex/OpenCode/Gemini | + QoderWork（MCP 原生支持，体验更好） |
| 接入协议 | 主要依赖终端 hook | MCP 原生 + 终端 hook 混合，更规范 |
| 国内 Agent 支持 | 无 | 可加 QoderWork、通义灵码等 |
| 定价 | 付费（通行证模式） | 可考虑免费/开源切入 |
| 开源替代 | open-vibe-island（功能简陋） | 可做更完善的开源版 |

---

## 八、建议的下一步

### Phase 1: UI 原型（1 周）
- SwiftUI 实现刘海区窗口定位
- 缩小态：状态灯 + 文案 + 会话计数
- 扩展态：任务列表 + 确认面板
- Hover 触发展开/收起动画
- 快捷键响应

### Phase 2: 单 Agent 接入（1 周）
- 选一个最容易的 agent 先跑通完整链路
- **推荐先接 QoderWork**（MCP API 最规范、已验证、无需逆向）
- 实现：发现任务 → 显示状态 → 接收确认请求 → 用户点击响应

### Phase 3: 多 Agent 适配（2 周）
- 加入 Claude Code 的终端日志监听
- 加入 Codex 的终端日志监听
- 统一适配器接口，实现多 agent 排队确认

### Phase 4: 完善体验（1 周）
- 通知过滤规则引擎
- 声音提醒
- 智能抑制
- 点击跳转到 agent 会话
- 设置面板

### 技术栈最终建议
- **语言**：Swift（Pure Swift，与 VibeIsland 同级）
- **UI 框架**：SwiftUI + AppKit（SwiftUI 做内容，AppKit 控制窗口行为）
- **状态管理**：Combine + @ObservableObject
- **Agent 通信**：URLSession（MCP）+ FileHandle/DispatchSource（文件监听）
- **窗口管理**：NSPanel + NSTrackingArea
- **构建系统**：Xcode + Swift Package Manager
- **最低系统要求**：macOS 14+（有刘海的 MacBook 起步 macOS 12，但 SwiftUI 特性需要 14+）
