# Agent 适配器协议规格

## 1. 协议定义

```swift
protocol AgentAdaptor: Sendable {
    var agentType: AgentType { get }
    var isAvailable: Bool { get async }
    
    func discoverSessions() async throws -> [AgentSession]
    func getStatus(session: AgentSession) async throws -> SessionStatus
    func getPendingConfirmations(session: AgentSession) async throws -> [PendingConfirmation]
    func respond(session: AgentSession, confirmation: PendingConfirmation, response: ConfirmationResponse) async throws
    func jumpTo(session: AgentSession) async throws
}
```

---

## 2. 数据模型

```swift
enum AgentType: String, Codable {
    case qoderWork
    case claudeCode
    case codex
    case openCode
    case gemini
}

struct AgentSession: Identifiable, Sendable {
    let id: String
    let agentType: AgentType
    var title: String
    var status: SessionStatus
    var startTime: Date
    var lastUpdate: Date
    var terminalInfo: TerminalInfo?
    var currentToolCall: String?
    var userLastInput: String?
}

enum SessionStatus: Sendable {
    case idle
    case thinking
    case executing
    case completed
    case waitingConfirmation
    case error(String)
}

struct PendingConfirmation: Identifiable, Sendable {
    let id: String
    let type: ConfirmationType
    let title: String
    let details: ConfirmationDetails
    let timestamp: Date
}

enum ConfirmationType: Sendable {
    case permission
    case choice
}

enum ConfirmationDetails: Sendable {
    case permission(PermissionDetails)
    case choice(ChoiceDetails)
}

struct PermissionDetails: Sendable {
    let operation: String       // "Edit src/auth/middleware.ts"
    let diff: [DiffLine]
    let additions: Int
    let deletions: Int
}

struct DiffLine: Sendable {
    let lineNumber: Int
    let content: String
    let type: DiffLineType      // .added, .removed, .context
}

struct ChoiceDetails: Sendable {
    let question: String
    let options: [ChoiceOption]
}

struct ChoiceOption: Identifiable, Sendable {
    let id: String
    let label: String
    let description: String?
}

enum ConfirmationResponse: Sendable {
    case allow
    case deny
    case select(optionId: String)
}

struct TerminalInfo: Sendable {
    let appName: String         // "iTerm", "Terminal", "Ghostty"
    let pid: pid_t?
    let windowId: String?
}
```

---

## 3. QoderWork 适配器实现规格

### 3.1 通信参数

| 参数 | 值 |
|------|-----|
| 协议 | HTTP POST, JSON-RPC 2.0 |
| 端点 | `http://127.0.0.1:52345` |
| 备用 | Unix Socket `/tmp/qoderwork-mcp.sock` |
| 超时 | 10 秒 |
| 轮询间隔 | 2 秒 |
| 重试策略 | 最多 3 次，指数退避（2s, 4s, 8s） |

### 3.2 MCP 方法映射

| 适配器方法 | MCP 工具 | 参数 |
|-----------|---------|------|
| `discoverSessions()` | `qoder_list_tasks` | 无 |
| `getStatus(session:)` | `qoder_get_task_detail` | `{taskId: session.id}` |
| `respond(..., .allow)` | `qoder_respond_task` | `{taskId: ..., response: "approve"}` |
| `respond(..., .deny)` | `qoder_respond_task` | `{taskId: ..., response: "deny"}` |
| `respond(..., .select(id))` | `qoder_respond_task` | `{taskId: ..., response: "answer", answer: {header: value}}` |
| `jumpTo(session:)` | N/A | 通过 Accessibility API 激活终端 |

### 3.3 状态映射

| MCP 原始状态 | 映射到 SessionStatus |
|-------------|---------------------|
| `task.status == "running"` && `lastToolCall.state == "input-streaming"` | `.thinking` |
| `task.status == "running"` && `lastToolCall.state == "result"` | `.executing` |
| `task.status == "running"` && `lastToolCall.state == "call"` | `.waitingConfirmation` |
| `task.status == "idle"` | `.idle` |
| `task.status == "completed"` | `.completed` |
| `task.status == "error"` | `.error(message)` |

### 3.4 可用性检测

```swift
var isAvailable: Bool {
    // 尝试连接 127.0.0.1:52345
    // 调用 initialize 方法验证 MCP server 存活
    // 返回 true/false
}
```

---

## 4. 轮询策略

```
if (no active sessions detected):
    stop polling (zero CPU)
    
if (QoderWork is available):
    poll every 2 seconds:
        1. discoverSessions() → update session list
        2. for each session: getStatus() → update status
        3. for sessions with .waitingConfirmation: getPendingConfirmations()
        
if (QoderWork becomes unavailable):
    retry 3 times with exponential backoff
    after 3 failures: mark as offline, pause polling 30s
    then retry availability check
```

---

## 5. Claude Code 适配器（Phase 2 预留）

| 参数 | 值 |
|------|-----|
| 监听路径 | `~/.claude/projects/*/sessions/*.jsonl`（待验证） |
| 监听方式 | FSEvents + FileHandle 增量读取 |
| 状态解析 | JSONL 行解析，type 字段匹配 |
| 确认响应 | 通过对应 PTY stdin 写入 |

状态映射（待验证）：
| JSONL type | SessionStatus |
|-----------|--------------|
| `thinking` | `.thinking` |
| `tool_use` | `.executing` |
| `permission_request` | `.waitingConfirmation` |
| `ask` | `.waitingConfirmation` |
| `result` | `.completed` |

---

## 6. 扩展新 Agent 的步骤

1. 定义新的 `AgentType` case
2. 实现 `AgentAdaptor` 协议的具体类
3. 在 `SessionManager` 中注册新适配器
4. 添加 Agent 标签色到 `DesignTokens`
5. 编写单元测试（mock 数据）
6. 集成测试（真实 Agent 运行时）
