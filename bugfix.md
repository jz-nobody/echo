# Agent Island - Bug & Iteration Tracker

> 创建日期：2026-05-21
> 最后更新：2026-05-21

---

## 状态说明

| 状态 | 含义 |
|------|------|
| `NEW` | 新发现，待分析 |
| `IN_PROGRESS` | 开发修复中（已拉分支） |
| `FIXED` | 修复完成，待验收 |
| `VERIFIED` | 验收通过，已合并主分支 |
| `WONTFIX` | 不修复（说明原因） |

---

## Bug 列表

| 编号 | 类型 | 描述 | 状态 | 分支 | 发现日期 |
|------|------|------|------|------|---------|
| BUG-001 | bug | Agent 会话状态显示与实际工作状态不一致 | `FIXED` | `bugfix/status-mapping-accuracy` | 2026-05-21 |
| BUG-002 | bug | 压缩上下文时显示"就绪"而非"压缩中" | `FIXED` | `bugfix/status-mapping-accuracy` | 2026-05-21 |
| BUG-003 | bug | Agent 状态变更后延迟显示，非实时同步 | `FIXED` | `bugfix/realtime-status-hooks` | 2026-05-21 |

---

## 迭代改进列表

| 编号 | 类型 | 描述 | 状态 | 分支 | 提出日期 |
|------|------|------|------|------|---------|
| ITER-001 | 文案优化 | reading 状态显示"查询中"、waitingConfirmation 显示"询问中" | `FIXED` | `bugfix/status-mapping-accuracy` | 2026-05-21 |

---

## 修复记录

### BUG-001 + ITER-001: Agent 会话状态映射修复

**日期：** 2026-05-21
**分支：** `bugfix/status-mapping-accuracy`
**状态：** 待验收

#### 问题描述
- Agent 处于 thinking 时显示"阅读中"而非"思考中"
- Agent 运行时显示"就绪"而非对应的活跃状态
- reading 状态文案不符合用户预期（"阅读中" → "查询中"）
- waitingConfirmation 状态文案不符合用户预期（"等待确认" → "询问中"）

#### 根因分析
1. `ClaudeCodeAdaptor.deriveStatus()` 中，当 `lastMessageType == .toolResult`（工具执行完毕，模型正在处理结果）时，无论在 `fileStatus` 非 idle 路径还是 `elapsed < 15s` 的启发式路径，都错误地走到 `refineExecuting(toolName)` 分支，导致以上一次工具名称（如 "Read"）决定状态，显示为"阅读中"而非"思考中"
2. 对于 `fileStatus` 非 nil 且非 "idle" 的情况，也缺少对 `toolResult` 的特殊处理

#### 修复内容
| 文件 | 修改 |
|------|------|
| `ClaudeCodeAdaptor.swift` | `deriveStatus()`: fileStatus 非 idle 时，toolResult 返回 `.thinking`；elapsed < 15s switch 中新增 `.toolResult` case 返回 `.thinking` |
| `SessionStatus.swift` | `.reading` displayText: "阅读中" → "查询中"；`.waitingConfirmation` displayText: "等待确认" → "询问中" |
| `SessionRowView.swift` | statusSubtitle 硬编码文案同步更新 |
| `SessionStatusTests.swift` | 更新断言匹配新文案，新增 `.reading` 和 `.editing` 的 displayText 覆盖 |

#### 状态映射对照表（修复后）
| Agent 实际状态 | SessionStatus | 显示文案 |
|---------------|---------------|---------|
| 思考中（处理用户输入或工具结果） | `.thinking` | 思考中 |
| 执行工具（Bash 等） | `.executing` | 运行中 |
| 查询文件/网页（Read/WebFetch 等） | `.reading` | 查询中 |
| 编辑文件（Edit/Write 等） | `.editing` | 编辑中 |
| 等待用户确认/选择 | `.waitingConfirmation` | 询问中 |
| 空闲 | `.idle` | 就绪 |
| 已完成 | `.completed` | 已完成 |
| 压缩上下文 | `.compacting` | 压缩中 |

#### 验证
- Build: 通过
- Tests: 215 tests, 28 suites, 全部通过

---

### BUG-002: 压缩上下文时状态显示为"就绪"

**日期：** 2026-05-21
**分支：** `bugfix/status-mapping-accuracy`
**状态：** 待验收

#### 问题描述
- Agent 会话执行上下文压缩（/compact 或自动压缩）时，Agent Island 显示"就绪"而非"压缩中"

#### 根因分析
1. 压缩期间 session 文件的 status 字段保持 "idle"（压缩是 Claude Code 内部操作，不更新 session status）
2. `compact_boundary` 写入 JSONL 后，summary assistant 消息紧随其后，导致 `lastMessageType` 不再是 `.systemCompact`，`isPostCompact` 也变为 false
3. `deriveStatus()` 中 `fileStatus == "idle"` 检查在压缩检测之前执行，直接返回 `.idle`
4. 空闲会话轮询间隔为 5 秒，而压缩窗口可能很短，导致轮询错过 `lastMessageType == .systemCompact` 的瞬间

#### 修复内容
| 文件 | 修改 |
|------|------|
| `ConversationLogParser.swift` | 新增 `entriesSinceCompact: Int?` 字段，追踪 compact_boundary 之后有多少条非元数据条目 |
| `ClaudeCodeAdaptor.swift` | `deriveStatus()`: 将 `isPostCompact` 和 `entriesSinceCompact` 检查移到 `fileStatus == "idle"` 之前；新增 `compactingDetectionThreshold = 30s`；压缩后 ≤5 条目且 JSONL 修改时间 <30s 则显示 `.compacting` |
| `ClaudeCodeAdaptor.swift` | `refreshConversationData()`: 新增压缩迟滞逻辑，从 `.compacting` 到 `.idle` 的跳转在 JSONL 修改时间 <30s 内保持 `.compacting` |

#### 压缩检测优先级链（修复后）
1. `lastMessageType == .systemCompact` → `.compacting`（compact_boundary 是最后一条 → 120s 内）
2. `isPostCompact == true` → `.compacting`（compact_boundary 后无 assistant → 120s 内）
3. `entriesSinceCompact <= 5` → `.compacting`（compact_boundary 附近 → 30s 内）
4. 迟滞：上一状态为 `.compacting` 且 JSONL 修改 <30s → 保持 `.compacting`
5. `fileStatus == "idle"` → `.idle`（以上条件都不满足时才走到这里）

#### 验证
- Build: 通过
- Tests: 218 tests, 28 suites, 全部通过（新增 3 个压缩检测测试）

---

### BUG-003: Agent 状态变更后延迟显示，非实时同步

**日期：** 2026-05-21
**分支：** `bugfix/realtime-status-hooks`
**状态：** 待验收

#### 问题描述
- Agent 会话状态变更（如开始压缩、开始执行工具、用户发送消息等）后，Agent Island 显示的状态更新延迟 1-5 秒
- 用户反馈"agent会话状态变更后，agentisland没有实时变更显示状态而是延时显示了"

#### 根因分析
1. Agent Island 依赖轮询 JSONL 文件检测状态变更（活跃会话 1s，空闲会话 5s）
2. JSONL 文件无任何文件监听（DispatchSource/FSEvents），仅在轮询时读取
3. SessionFileWatcher 仅监听 `~/.claude/sessions/` 目录（session JSON 文件），不监听 JSONL 对话日志文件
4. 参考竞品 open-vibe-island 使用 Claude Code Hook 推送架构实现近实时状态同步

#### 修复方案：Hook 推送架构
参考 open-vibe-island，将状态检测从"轮询拉取"改为"Hook 推送"。Agent Island 已有 IPC Server 和 Hook Installer 基础设施，但仅注册了 `PermissionRequest` 一种 Hook。修复后扩展至 6 种 Hook 类型。

#### 修复内容
| 文件 | 修改 |
|------|------|
| `IPCProtocol.swift` | `HookMessage.toolName` 和 `toolInput` 改为可选（非权限 Hook 无这些字段）；`HookResponse.decision` 改为可选，新增 `.empty` 静态常量（返回 `{}` 不影响权限流程） |
| `HookInstaller.swift` | 新增 `requiredHookTypes` 配置，注册 6 种 Hook：PermissionRequest(86400s)、PreToolUse(5s)、PostToolUse(5s)、UserPromptSubmit(5s)、PreCompact(5s)、Stop(5s)；`isHookInstalled()` 改为检查所有必需 Hook 类型 |
| `ClaudeCodeAdaptor.swift` | 新增 `handleStatusHook()` 方法，根据 Hook 类型映射状态（PreToolUse→reading/editing/executing，PostToolUse→thinking，UserPromptSubmit→thinking，PreCompact→compacting，Stop→idle）；新增 `hookStatusOverrides` 字典存储 Hook 状态覆盖（TTL 15s）；新增 `statusChangedNotification` 通知；`refreshConversationData()` 中 Hook 状态覆盖优先于 JSONL 派生状态 |
| `SessionManager.swift` | 新增 `statusChangedNotification` 观察者，Hook 状态变更时立即触发 `pollOnce()` |

#### Hook 推送状态映射表
| Hook 类型 | SessionStatus | 说明 |
|-----------|--------------|------|
| `PreToolUse` (Read/WebFetch/etc.) | `.reading` | 开始查询文件/网页 |
| `PreToolUse` (Edit/Write/etc.) | `.editing` | 开始编辑文件 |
| `PreToolUse` (Bash/other) | `.executing` | 开始执行命令 |
| `PostToolUse` | `.thinking` | 工具完成，模型处理结果 |
| `UserPromptSubmit` | `.thinking` | 用户发送消息 |
| `PreCompact` | `.compacting` | 开始压缩上下文 |
| `Stop` | `.idle` | 轮次结束 |

#### 数据流对比
**修复前：** Claude Code 写入 JSONL → 等待轮询（1-5s）→ 解析 JSONL → 派生状态 → UI 更新
**修复后：** Claude Code 触发 Hook → Bridge 脚本转发 → IPC Server 接收 → 立即更新状态 → 通知 UI 刷新（~100ms）

#### 验证
- Build: 通过
- Tests: 228 tests, 28 suites, 全部通过（新增 10 个 Hook 状态同步测试）

---
