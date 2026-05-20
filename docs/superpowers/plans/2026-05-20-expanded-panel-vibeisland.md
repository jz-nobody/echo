# Expanded Panel VibeIsland Replication — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replicate VibeIsland's expanded panel UI: auto-approve tag, idle/completed status text, tool name highlighting, and conversation-compressed indicator.

**Architecture:** Extend the existing ConversationLogParser to extract two new fields (`permissionMode`, `isConversationCompressed`) from JSONL conversation logs. Propagate through ClaudeCodeAdaptor → AgentSession → SessionRowView. Add four new visual elements to SessionRowView.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, Swift Testing framework

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/Core/Models/AgentSession.swift` | Modify | Add `permissionMode: String?` and `isConversationCompressed: Bool` |
| `Sources/Adaptors/ClaudeCode/ConversationLogParser.swift` | Modify | Extract permissionMode from user messages, detect `compact_boundary` system messages |
| `Sources/Adaptors/ClaudeCode/ClaudeCodeAdaptor.swift` | Modify | Populate new AgentSession fields from snapshot |
| `Sources/UI/DesignTokens.swift` | Modify | Add color tokens for auto-approve tag and tool name highlighting |
| `Sources/UI/ExpandedPanel/SessionRowView.swift` | Modify | Add auto-approve tag, status subtitle, tool highlighting, compressed indicator |
| `Tests/AdaptorTests/ConversationLogParserTests.swift` | Modify | Add tests for permissionMode and compression detection |

---

### Task 1: Add new fields to AgentSession

**Files:**
- Modify: `AgentIsland/Sources/Core/Models/AgentSession.swift`

- [ ] **Step 1: Add `permissionMode` and `isConversationCompressed` fields**

Open `AgentIsland/Sources/Core/Models/AgentSession.swift` and add two fields after `subagents`:

```swift
struct AgentSession: Identifiable, Sendable, Equatable {
    let id: String
    let agentType: AgentType
    var title: String
    var status: SessionStatus
    var startTime: Date
    var lastUpdate: Date
    var terminalInfo: TerminalInfo?
    var currentToolCall: String?
    var lastUserPrompt: String?
    var lastAssistantMessage: String?
    var sessionDescription: String?
    var todos: [TodoItem]?
    var subagents: [SubagentInfo]?
    var permissionMode: String?
    var isConversationCompressed: Bool = false
}
```

- [ ] **Step 2: Verify build**

Run: `cd AgentIsland && swift build 2>&1 | tail -5`
Expected: Build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add AgentIsland/Sources/Core/Models/AgentSession.swift
git commit -m "feat: add permissionMode and isConversationCompressed to AgentSession"
```

---

### Task 2: Parser tests for new snapshot fields

**Files:**
- Modify: `AgentIsland/Tests/AdaptorTests/ConversationLogParserTests.swift`

- [ ] **Step 1: Write test for permissionMode extraction**

Add to the `ConversationLogParserTests` struct:

```swift
@Test("snapshot extracts permissionMode from latest user message")
func snapshotPermissionMode() throws {
    let path = try writeTempJSONL([
        #"{"type":"user","permissionMode":"default","message":{"role":"user","content":[{"type":"text","text":"Hello"}]}}"#,
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}]}}"#,
        #"{"type":"user","permissionMode":"acceptEdits","message":{"role":"user","content":[{"type":"text","text":"Do it"}]}}"#
    ])

    let snap = ConversationLogParser.snapshot(atPath: path)

    #expect(snap.permissionMode == "acceptEdits")
}
```

- [ ] **Step 2: Write test for nil permissionMode**

```swift
@Test("snapshot returns nil permissionMode when field absent")
func snapshotPermissionModeNil() throws {
    let path = try writeTempJSONL([
        #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Hello"}]}}"#,
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}]}}"#
    ])

    let snap = ConversationLogParser.snapshot(atPath: path)

    #expect(snap.permissionMode == nil)
}
```

- [ ] **Step 3: Write test for conversation compression detection**

```swift
@Test("snapshot detects conversation compression via compact_boundary")
func snapshotConversationCompressed() throws {
    let path = try writeTempJSONL([
        #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Start"}]}}"#,
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"OK"}]}}"#,
        #"{"type":"system","subtype":"compact_boundary","content":"Conversation compacted"}"#,
        #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Continue"}]}}"#
    ])

    let snap = ConversationLogParser.snapshot(atPath: path)

    #expect(snap.isConversationCompressed == true)
}
```

- [ ] **Step 4: Write test for no compression**

```swift
@Test("snapshot returns false when no compaction occurred")
func snapshotNotCompressed() throws {
    let path = try writeTempJSONL([
        #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Hello"}]}}"#,
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}]}}"#
    ])

    let snap = ConversationLogParser.snapshot(atPath: path)

    #expect(snap.isConversationCompressed == false)
}
```

- [ ] **Step 5: Run tests to verify they fail**

Run: `cd AgentIsland && swift test --filter ConversationLogParserTests 2>&1 | tail -20`
Expected: Compilation fails — `ConversationSnapshot` has no member `permissionMode` / `isConversationCompressed`.

- [ ] **Step 6: Commit failing tests**

```bash
git add AgentIsland/Tests/AdaptorTests/ConversationLogParserTests.swift
git commit -m "test: add parser tests for permissionMode and compression detection"
```

---

### Task 3: Implement parser changes

**Files:**
- Modify: `AgentIsland/Sources/Adaptors/ClaudeCode/ConversationLogParser.swift`

- [ ] **Step 1: Update ConversationSnapshot**

Add `permissionMode` and `isConversationCompressed` to the struct:

```swift
struct ConversationSnapshot: Sendable {
    let sessionDescription: String?
    let lastUserPrompt: String?
    let lastAssistantMessage: String?
    let todos: [TodoItem]
    let subagents: [SubagentInfo]
    let permissionMode: String?
    let isConversationCompressed: Bool
}
```

- [ ] **Step 2: Update TailData**

Add the new fields:

```swift
private struct TailData {
    let lastUserPrompt: String?
    let lastAssistantMessage: String?
    let todos: [TodoItem]
    let subagents: [SubagentInfo]
    let permissionMode: String?
    let isConversationCompressed: Bool
}
```

- [ ] **Step 3: Update readTailData() to extract permissionMode and detect compression**

In `readTailData()`, add two new local variables before the loop:

```swift
var lastPermissionMode: String?
var foundCompactBoundary = false
```

In the `switch type` block, update the `"user"` case:

```swift
case "user":
    if lastUserText == nil {
        lastUserText = extractText(from: obj)
    }
    if lastPermissionMode == nil, let mode = obj["permissionMode"] as? String {
        lastPermissionMode = mode
    }
```

Note: remove the `where lastUserText == nil` guard from the case pattern — we now need to enter the case for permissionMode even if we already have the user text. Use an `if` inside instead.

Add a new case for system messages:

```swift
case "system":
    if obj["subtype"] as? String == "compact_boundary" {
        foundCompactBoundary = true
    }
```

Update the `TailData` return:

```swift
return TailData(
    lastUserPrompt: lastUserText,
    lastAssistantMessage: lastAssistantText,
    todos: lastTodos,
    subagents: subagents,
    permissionMode: lastPermissionMode,
    isConversationCompressed: foundCompactBoundary
)
```

- [ ] **Step 4: Update snapshot() to pass new fields through**

In `snapshot(atPath:)`, update the return:

```swift
return ConversationSnapshot(
    sessionDescription: description,
    lastUserPrompt: tailData.lastUserPrompt,
    lastAssistantMessage: tailData.lastAssistantMessage,
    todos: tailData.todos,
    subagents: tailData.subagents,
    permissionMode: tailData.permissionMode,
    isConversationCompressed: tailData.isConversationCompressed
)
```

Also update the two early-return empty snapshots in `snapshot(atPath:)`:

```swift
return ConversationSnapshot(
    sessionDescription: nil, lastUserPrompt: nil, lastAssistantMessage: nil,
    todos: [], subagents: [], permissionMode: nil, isConversationCompressed: false
)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd AgentIsland && swift test --filter ConversationLogParserTests 2>&1 | tail -20`
Expected: All tests pass including the 4 new ones.

- [ ] **Step 6: Commit**

```bash
git add AgentIsland/Sources/Adaptors/ClaudeCode/ConversationLogParser.swift
git commit -m "feat: extract permissionMode and detect conversation compression in parser"
```

---

### Task 4: Update adaptor to populate new fields

**Files:**
- Modify: `AgentIsland/Sources/Adaptors/ClaudeCode/ClaudeCodeAdaptor.swift`

- [ ] **Step 1: Update refreshConversationData()**

In the `refreshConversationData()` method, add two lines after the existing field assignments:

```swift
private func refreshConversationData() {
    for (id, file) in sessionFiles {
        guard var session = activeSessions[id] else { continue }
        let snap = ConversationLogParser.snapshot(cwd: file.cwd, sessionId: file.sessionId)
        session.sessionDescription = snap.sessionDescription
        session.lastUserPrompt = snap.lastUserPrompt
        session.lastAssistantMessage = snap.lastAssistantMessage
        session.todos = snap.todos.isEmpty ? nil : snap.todos
        session.subagents = snap.subagents.isEmpty ? nil : snap.subagents
        session.permissionMode = snap.permissionMode
        session.isConversationCompressed = snap.isConversationCompressed
        activeSessions[id] = session
    }
}
```

- [ ] **Step 2: Verify build**

Run: `cd AgentIsland && swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 3: Run full tests**

Run: `cd AgentIsland && swift test 2>&1 | tail -10`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add AgentIsland/Sources/Adaptors/ClaudeCode/ClaudeCodeAdaptor.swift
git commit -m "feat: populate permissionMode and isConversationCompressed from snapshot"
```

---

### Task 5: Add DesignTokens for new UI elements

**Files:**
- Modify: `AgentIsland/Sources/UI/DesignTokens.swift`

- [ ] **Step 1: Add color tokens**

Add after the existing `tagTerminalBackground` line in the "Task & Subagent" section:

```swift
static let tagAutoApproveBackground = Color(nsColor: NSColor(hex: "#FF453A"))
static let toolBash = Color(nsColor: NSColor(hex: "#D97757"))
static let toolWrite = Color(nsColor: NSColor(hex: "#30D158"))
static let toolRead = Color(nsColor: NSColor(hex: "#0A84FF"))
```

Note: Apply `.opacity(0.15)` on the background at the usage site in SessionRowView, not in the token definition (Color.opacity returns ShapeStyle, not Color).

- [ ] **Step 2: Verify build**

Run: `cd AgentIsland && swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add AgentIsland/Sources/UI/DesignTokens.swift
git commit -m "feat: add design tokens for auto-approve tag and tool name colors"
```

---

### Task 6: SessionRowView — auto-approve tag

**Files:**
- Modify: `AgentIsland/Sources/UI/ExpandedPanel/SessionRowView.swift`

- [ ] **Step 1: Rename agentTag → agentTypeTag**

Rename the existing `agentTag` computed property to `agentTypeTag` to avoid confusion with the new auto-approve tag. Find-and-replace `agentTag` → `agentTypeTag` in SessionRowView.swift (the property definition and the reference in `headerRow`). The helper properties `agentLabel` and `tagColor` stay as-is.

- [ ] **Step 2: Add autoApproveTag view**

Add a new private computed property in the `// MARK: - Tags` section:

```swift
@ViewBuilder
private var autoApproveTag: some View {
    if let mode = session.permissionMode, mode != "default" {
        Text("自动批准 ×")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(DesignTokens.tagAutoApproveBackground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(DesignTokens.tagAutoApproveBackground.opacity(0.15))
            .clipShape(Capsule())
    }
}
```

- [ ] **Step 3: Add autoApproveTag to headerRow**

Update `headerRow` to insert the auto-approve tag before the agent type tag:

```swift
private var headerRow: some View {
    HStack(spacing: 6) {
        StatusDotView(status: session.status)

        Text(titleText)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(DesignTokens.textPrimary)
            .lineLimit(1)

        Spacer(minLength: 4)

        autoApproveTag

        agentTypeTag

        if let terminal = session.terminalInfo {
            terminalTag(terminal)
        }

        timeTag
    }
}
```

- [ ] **Step 4: Verify build**

Run: `cd AgentIsland && swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add AgentIsland/Sources/UI/ExpandedPanel/SessionRowView.swift
git commit -m "feat: add auto-approve status tag to session row header"
```

---

### Task 7: SessionRowView — status subtitle for idle/completed

**Files:**
- Modify: `AgentIsland/Sources/UI/ExpandedPanel/SessionRowView.swift`

- [ ] **Step 1: Add statusSubtitle view**

Add a new computed property:

```swift
@ViewBuilder
private var statusSubtitle: some View {
    if session.status == .idle {
        Text("就绪")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DesignTokens.statusCompleted)
            .padding(.leading, 16)
    } else if session.status == .completed {
        Text("Done — click to jump")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DesignTokens.statusCompleted)
            .padding(.leading, 16)
    }
}
```

- [ ] **Step 2: Add to body VStack**

Insert `statusSubtitle` after `agentActionLine` in the body:

```swift
VStack(alignment: .leading, spacing: 4) {
    headerRow
    userPromptLine
    agentActionLine
    statusSubtitle

    if let todos = session.todos, !todos.isEmpty {
        TaskSectionView(todos: todos)
    }

    if let subagents = session.subagents, !subagents.isEmpty {
        SubagentSectionView(subagents: subagents)
    }
}
```

- [ ] **Step 3: Verify build**

Run: `cd AgentIsland && swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add AgentIsland/Sources/UI/ExpandedPanel/SessionRowView.swift
git commit -m "feat: add idle/completed status subtitle to session rows"
```

---

### Task 8: SessionRowView — tool name syntax highlighting

**Files:**
- Modify: `AgentIsland/Sources/UI/ExpandedPanel/SessionRowView.swift`

- [ ] **Step 1: Add toolCallText helper**

Add a new private method:

```swift
private func toolCallText(_ tool: String) -> Text {
    let parts = tool.split(separator: " ", maxSplits: 1)
    let toolName = String(parts[0]).replacingOccurrences(of: ":", with: "")
    let toolArgs = parts.count > 1 ? " " + String(parts[1]) : ""

    let nameColor: Color = switch toolName {
    case "Bash": DesignTokens.toolBash
    case "Write", "Edit": DesignTokens.toolWrite
    case "Read": DesignTokens.toolRead
    default: DesignTokens.textSecondary
    }

    return Text(toolName)
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(nameColor)
    + Text(toolArgs)
        .font(.system(size: 11))
        .foregroundColor(DesignTokens.textSecondary)
}
```

- [ ] **Step 2: Update agentActionLine to use toolCallText**

Replace the current `agentActionLine` implementation:

```swift
@ViewBuilder
private var agentActionLine: some View {
    if let tool = session.currentToolCall {
        toolCallText(tool)
            .lineLimit(1)
            .padding(.leading, 16)
    } else if let reply = session.lastAssistantMessage {
        Text(reply)
            .font(.system(size: 11))
            .foregroundStyle(DesignTokens.textSecondary)
            .lineLimit(1)
            .padding(.leading, 16)
    }
}
```

- [ ] **Step 3: Verify build**

Run: `cd AgentIsland && swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add AgentIsland/Sources/UI/ExpandedPanel/SessionRowView.swift
git commit -m "feat: add tool name syntax highlighting in agent action line"
```

---

### Task 9: SessionRowView — conversation compressed indicator

**Files:**
- Modify: `AgentIsland/Sources/UI/ExpandedPanel/SessionRowView.swift`

- [ ] **Step 1: Add compressedIndicator view**

Add a new computed property:

```swift
@ViewBuilder
private var compressedIndicator: some View {
    if session.isConversationCompressed {
        HStack(spacing: 4) {
            Image(systemName: "circle.slash")
                .font(.system(size: 10))
            Text("对话已压缩")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(DesignTokens.statusError)
        .padding(.leading, 16)
    }
}
```

- [ ] **Step 2: Add to body VStack**

Insert `compressedIndicator` after `agentActionLine` and before `statusSubtitle`:

```swift
VStack(alignment: .leading, spacing: 4) {
    headerRow
    userPromptLine
    agentActionLine
    compressedIndicator
    statusSubtitle

    if let todos = session.todos, !todos.isEmpty {
        TaskSectionView(todos: todos)
    }

    if let subagents = session.subagents, !subagents.isEmpty {
        SubagentSectionView(subagents: subagents)
    }
}
```

- [ ] **Step 3: Verify build**

Run: `cd AgentIsland && swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add AgentIsland/Sources/UI/ExpandedPanel/SessionRowView.swift
git commit -m "feat: add conversation compressed indicator to session rows"
```

---

### Task 10: Full build, test, and manual verification

**Files:** None (verification only)

- [ ] **Step 1: Full build**

Run: `cd AgentIsland && swift build 2>&1 | tail -10`
Expected: Build succeeds with zero errors.

- [ ] **Step 2: Run all tests**

Run: `cd AgentIsland && swift test 2>&1 | tail -20`
Expected: All tests pass (existing + 4 new parser tests).

- [ ] **Step 3: Run the app**

Run: `cd AgentIsland && swift build && .build/debug/AgentIsland &`
Launch the app and hover over the notch area to expand the panel.

- [ ] **Step 4: Manual verification checklist**

Verify each item:
- [ ] Active session shows user prompt line ("你：...")
- [ ] Active session shows agent action with colored tool name (Bash in orange, Write/Edit in green)
- [ ] Auto-approve tag ("自动批准 ×") appears in header when session has permissionMode
- [ ] "对话已压缩" indicator appears for compressed conversations
- [ ] Idle sessions show "就绪" status text in green
- [ ] Task section and subagent section display correctly
- [ ] Hover highlight and click-to-jump still work
- [ ] Confirmation panels inline display still works
- [ ] Escape key still collapses the panel

- [ ] **Step 5: Final commit if any fixes needed**

If any manual fixes were needed, commit them:
```bash
git add -A
git commit -m "fix: polish expanded panel UI after manual verification"
```
