# Expanded Panel VibeIsland Replication Design

> Date: 2026-05-20
> Status: Draft
> Branch: step/1-notch-window

## Goal

Replicate VibeIsland's expanded panel UI/UX layout, information fields, and content display in AgentIsland. The current code has the structural building blocks (SessionRowView, TaskSectionView, SubagentSectionView, ConversationLogParser) but is missing several visual elements and data fields that VibeIsland displays.

## Reference Screenshots

- IMG-003: `~/Downloads/运行中hover.jpg` — Running state with user prompt + tool call
- IMG-004: `~/Downloads/多agent列表.JPG` — Multi-agent list with rich session cards
- IMG-005: `~/Downloads/点击任务唤起agent.jpg` — Completed state with "Done — click to jump"
- User-provided screenshots in conversation — Current AgentIsland vs VibeIsland side-by-side

---

## 1. Target Layouts

### Active Session Card

```
┌──────────────────────────────────────────────────────────────────┐
│ ● echo · 首条用户提示...   [自动批准 ×] [Claude] [VS Code] 3m     │
│   你：最近用户输入...                                              │
│   Bash claude --help 2>/dev/null | grep -i plugin || true        │
│   ⊘ 对话已压缩                                                    │
│                                                                   │
│   任务 (6 已完成, 0 进行中, 0 待处理)                                │
│   ☑ Task item 1 (strikethrough)                                   │
│   ☑ Task item 2 (strikethrough)                                   │
│   ... +4 已完成                                                    │
│                                                                   │
│   ↳ Subagents (2)                                                 │
│   ● Explore (expansion panel code) 完成                           │
│   ● Explore (Claude Code session data) 完成                       │
└──────────────────────────────────────────────────────────────────┘
```

### Idle Session Card

```
┌──────────────────────────────────────────────────────────────────┐
│ ● wm338658                                  [Claude] [Terminal] 6h│
│   就绪                                                            │
└──────────────────────────────────────────────────────────────────┘
```

### Completed Session Card

```
┌──────────────────────────────────────────────────────────────────┐
│ ● fix auth bug                              [Claude] [iTerm] 28m  │
│   你：fix the auth bug in middleware                               │
│   Done — click to jump                                            │
└──────────────────────────────────────────────────────────────────┘
```

---

## 2. Data Model Changes

### AgentSession (modify existing)

File: `Sources/Core/Models/AgentSession.swift`

Add two new fields:

```swift
var permissionMode: String?          // "auto-accept", etc. from JSONL
var isConversationCompressed: Bool   // whether conversation was compacted
```

Default `isConversationCompressed` to `false`.

### ConversationSnapshot (modify existing)

File: `Sources/Adaptors/ClaudeCode/ConversationLogParser.swift`

Add to `ConversationSnapshot`:

```swift
let permissionMode: String?
let isConversationCompressed: Bool
```

---

## 3. Parser Changes

### ConversationLogParser

File: `Sources/Adaptors/ClaudeCode/ConversationLogParser.swift`

#### 3.1 Extract `permissionMode`

From user messages in the JSONL, the `message` object may contain a `permissionMode` field at the top level. Parse the most recent user message's `permissionMode` value.

Detection: In `readTailData()`, when parsing `type:"user"` messages, also extract:
```json
{"type": "user", "message": {"role": "user", "content": [...]}, "permissionMode": "auto-accept"}
```

Note: the `permissionMode` is at the TOP level of the JSONL line object, NOT inside `message`.

#### 3.2 Detect conversation compression

Conversation compression in Claude Code produces a message with `type: "summary"` or the user sends `/compact`. Detection strategy:

- In tail parsing, look for any line where `type` is `"summary"` — this indicates the conversation was compacted.
- Alternatively, look for assistant messages that contain compaction markers.

Simple approach: scan tail lines for `type == "summary"`. If found, set `isConversationCompressed = true`.

#### 3.3 TailData update

Add to `TailData`:
```swift
let permissionMode: String?
let isConversationCompressed: Bool
```

---

## 4. Adaptor Changes

### ClaudeCodeAdaptor

File: `Sources/Adaptors/ClaudeCode/ClaudeCodeAdaptor.swift`

In `refreshConversationData()`, populate the new fields:

```swift
session.permissionMode = snap.permissionMode
session.isConversationCompressed = snap.isConversationCompressed
```

---

## 5. UI Changes

### 5.1 SessionRowView Redesign

File: `Sources/UI/ExpandedPanel/SessionRowView.swift`

#### Header Row — Add auto-approve tag

Insert before `agentTag` in the header HStack:

```swift
if let mode = session.permissionMode, mode != "default" {
    autoApproveTag(mode)
}
```

The tag renders as a red capsule with "自动批准 ×" text. The "×" indicates auto-approve is active (user can't change it from the panel, just informational).

#### Status Subtitle — For idle and completed sessions

Add a new `@ViewBuilder` below `agentActionLine`:

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

#### Agent Action Line — Tool name syntax highlighting

Modify `agentActionLine` to split tool name from arguments and color the tool name:

```swift
if let tool = session.currentToolCall {
    toolCallText(tool)
        .padding(.leading, 16)
}
```

Where `toolCallText()` splits on the first space/colon and renders the tool name in its specific color:
- `Bash` → `DesignTokens.tagClaude` (orange #D97757)
- `Write`, `Edit` → `DesignTokens.statusCompleted` (green #30D158)
- `Read` → `DesignTokens.statusExecuting` (blue #0A84FF)
- Others → `DesignTokens.textSecondary`

Implementation: Use `Text` concatenation (`Text("Bash") + Text(" command...")`) to apply different foreground styles.

#### Conversation Compressed Indicator

Add below the agent action line:

```swift
@ViewBuilder
private var compressedIndicator: some View {
    if session.isConversationCompressed {
        HStack(spacing: 4) {
            Text("⊘")
                .font(.system(size: 11))
            Text("对话已压缩")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(DesignTokens.statusError)
        .padding(.leading, 16)
    }
}
```

#### Updated VStack body order

```swift
VStack(alignment: .leading, spacing: 4) {
    headerRow
    userPromptLine
    agentActionLine          // with tool name highlighting
    compressedIndicator      // NEW
    statusSubtitle           // NEW (idle "就绪" or completed "Done — click to jump")

    if let todos = session.todos, !todos.isEmpty {
        TaskSectionView(todos: todos)
    }
    if let subagents = session.subagents, !subagents.isEmpty {
        SubagentSectionView(subagents: subagents)
    }
}
```

### 5.2 DesignTokens

File: `Sources/UI/DesignTokens.swift`

Add new tokens:

```swift
static let tagAutoApproveBackground = Color(nsColor: NSColor(hex: "#FF453A"))
static let toolBash = Color(nsColor: NSColor(hex: "#D97757"))
static let toolWrite = Color(nsColor: NSColor(hex: "#30D158"))
static let toolRead = Color(nsColor: NSColor(hex: "#0A84FF"))
```

---

## 6. Auto-Approve Tag Design

Visual spec:
- Background: `#FF453A` (red) with 0.15 opacity
- Text color: `#FF453A` (red) full opacity
- Font: system 10pt medium
- Text: "自动批准 ×"
- Shape: Capsule
- Padding: horizontal 6pt, vertical 2pt

Placement: In the header HStack, between the title `Spacer()` and the agent type tag.

---

## 7. Test Changes

### ConversationLogParserTests

File: `Tests/AdaptorTests/ConversationLogParserTests.swift`

New test cases:
1. `testSnapshotExtractsPermissionMode` — JSONL with `permissionMode` field on user message
2. `testSnapshotDetectsConversationCompressed` — JSONL with `type:"summary"` line
3. `testSnapshotNoCompression` — JSONL without summary, `isConversationCompressed == false`
4. `testSnapshotPermissionModeNil` — JSONL without permissionMode field

---

## 8. Scope Exclusions

- **No avatar icon** — Per user preference, skip the Creeper-style avatar
- **No activity detail section** — VibeIsland's IMG-005 shows tool call results (e.g., "Write(src/routes/users.ts) → New file (47 lines)"). This requires significant new data infrastructure and is out of scope for this iteration.
- **No new external dependencies**

---

## 9. Files Changed

| File | Type | Description |
|------|------|-------------|
| `Sources/Core/Models/AgentSession.swift` | Modify | Add `permissionMode`, `isConversationCompressed` |
| `Sources/Adaptors/ClaudeCode/ConversationLogParser.swift` | Modify | Extract permissionMode, detect compression |
| `Sources/Adaptors/ClaudeCode/ClaudeCodeAdaptor.swift` | Modify | Populate new fields |
| `Sources/UI/DesignTokens.swift` | Modify | Add color tokens |
| `Sources/UI/ExpandedPanel/SessionRowView.swift` | Modify | Auto-approve tag, status subtitle, tool highlighting, compressed indicator |
| `Tests/AdaptorTests/ConversationLogParserTests.swift` | Modify | New test cases |

---

## 10. Verification

1. `swift build` — zero errors
2. `swift test` — all tests pass (existing + new)
3. Manual verification:
   - [ ] Active session shows user prompt line
   - [ ] Active session shows agent action with colored tool name
   - [ ] Auto-approve tag appears when permissionMode is set
   - [ ] "对话已压缩" indicator appears for compressed conversations
   - [ ] Idle sessions show "就绪" status text
   - [ ] Completed sessions show "Done — click to jump" green text
   - [ ] Task section and subagent section display correctly
   - [ ] Hover highlight and click-to-jump still work
   - [ ] Confirmation panels inline display still works
