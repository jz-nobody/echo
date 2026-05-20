# Panel Behavior & Data Persistence Design

> Date: 2026-05-20
> Status: Draft
> Branch: step/1-notch-window

## Goal

Fix 5 issues with the expanded panel: (1) auto-expand on task completion, (2) auto-collapse after 5s inactivity, (3) click outside to collapse, (4) persist conversation data (todos/subagents) that currently vanishes as JSONL files grow, (5) show complete subagent list matching VibeIsland.

---

## 1. Auto-Expand on Task Completion

### Current Behavior

Panel auto-expands only for pending confirmations (`NotchRootView.onChange(of: sessionManager.pendingConfirmations.count)`). When a session completes, a sound plays (`SessionEventDetector.detectSessionEnd`) but the panel stays collapsed.

### Design

Add a completion-detection mechanism in `NotchRootView` that tracks previous session statuses and triggers `panelState.autoExpand()` when a session transitions from an active status (`.executing`, `.waitingConfirmation`) to `.completed`.

**File:** `Sources/UI/NotchRootView.swift`

Add a `@State private var previousStatuses: [String: SessionStatus] = [:]` property. In an `onChange(of: sessionManager.sessions)` handler, compare current statuses to previous. If any session transitioned to `.completed`:

1. Check `SuppressionEvaluator.shouldSuppress()` — if the user is focused on the terminal that just completed, don't auto-expand (they already see the result).
2. If not suppressed and panel is not already expanded, call `panelState.expand()`. Do NOT use `autoExpand()` — that sets `confirmationsActive = true` which locks the panel open. For completions, we want normal auto-collapse behavior (5s timer still applies).

**Why not reuse `SessionEventDetector`:** That class returns `SoundEvent` values consumed by `SessionManager`. Adding panel-state side effects to a sound-event system would couple unrelated concerns. A separate `onChange` in `NotchRootView` is cleaner.

**Edge case:** Multiple sessions completing simultaneously — only one `autoExpand()` call needed. The `onChange` fires once per `sessions` array change.

---

## 2. Auto-Collapse After 5 Seconds

### Current Behavior

`PanelState.mouseExited()` immediately calls `collapse()` (unless `confirmationsActive` is true). The panel vanishes the instant the cursor leaves.

### Design

Replace immediate collapse with a 5-second delayed collapse.

**File:** `Sources/Core/PanelState.swift`

Add a new timer property:

```swift
private var collapseTimer: Timer?
```

Modify `mouseExited()`:

```swift
func mouseExited() {
    expandTimer?.invalidate()
    expandTimer = nil
    guard !confirmationsActive else { return }
    collapseTimer?.invalidate()
    collapseTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
        Task { @MainActor in
            self?.collapse()
        }
    }
}
```

Modify `mouseEntered()` to cancel pending collapse:

```swift
func mouseEntered() {
    collapseTimer?.invalidate()
    collapseTimer = nil
    expandTimer?.invalidate()
    expandTimer = Timer.scheduledTimer(withTimeInterval: settingsStore.hoverDelay, repeats: false) { [weak self] _ in
        Task { @MainActor in
            self?.expand()
        }
    }
}
```

Also cancel `collapseTimer` in `expand()`, `autoExpand()`, and `collapse()` to prevent stale timers:

```swift
func collapse() {
    collapseTimer?.invalidate()
    collapseTimer = nil
    isExpanded = false
    onExpandChange?()
}
```

**The 5-second constant:** Hardcode as `private let autoCollapseDelay: TimeInterval = 5.0`. The existing `settingsStore.autoCollapseOnMouseExit` bool still serves as the on/off toggle — if `false`, skip the timer entirely and leave the panel open.

---

## 3. Click Outside to Collapse

### Current Behavior

`SettingsStore.dismissOnClickOutside` exists (default `false`) but has zero implementation. No global click monitor exists.

### Design

Add a global mouse-down monitor in `WindowController` that collapses the panel when a click lands outside its frame.

**File:** `Sources/Infrastructure/WindowController.swift`

Add a property:

```swift
private var globalClickMonitor: Any?
```

In `showCompactBar()`, after panel creation, install the monitor:

```swift
globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
    Task { @MainActor in
        guard let self, let panel = self.panel else { return }
        guard self.panelState.isExpanded else { return }
        let clickLocation = event.locationInWindow == .zero
            ? NSEvent.mouseLocation
            : event.locationInWindow
        if !panel.frame.contains(NSEvent.mouseLocation) {
            self.panelState.confirmationsActive = false
            self.panelState.collapse()
        }
    }
}
```

Key details:
- Uses `NSEvent.mouseLocation` (screen coordinates) since global monitors receive events without a window reference.
- Handles both left and right clicks.
- Clears `confirmationsActive` to allow collapse even during confirmations (user explicitly clicked away).
- Change `dismissOnClickOutside` default to `true` in `SettingsStore`.

**Cleanup:** In `stopMonitoring()` or a `deinit`-equivalent, remove the monitor:

```swift
if let monitor = globalClickMonitor {
    NSEvent.removeMonitor(monitor)
    globalClickMonitor = nil
}
```

---

## 4 & 5. Data Persistence and Complete Subagent Display

### Root Cause

`ConversationLogParser.readTailData()` reads only the last 64KB of the JSONL file. For a 45MB conversation, this is 0.14% of the file. As the conversation grows:

- TodoWrite calls from earlier fall outside the window — **todos vanish**
- Agent tool_use calls from earlier fall outside — **subagents vanish**
- This is why AgentIsland shows 1 subagent while VibeIsland shows 4 for the same session

### Design: Three-Part Solution

#### Part A: Increase tail buffer

**File:** `Sources/Adaptors/ClaudeCode/ConversationLogParser.swift`

Change `tailReadSize` from 64KB to 256KB:

```swift
private static let tailReadSize: UInt64 = 262_144  // 256KB
```

This gives 4x more coverage for ephemeral data (last prompts, messages, permissionMode, compression). For most conversations under 256KB, this alone fixes the problem.

#### Part B: Add subagent accumulation via full-file scan

**File:** `Sources/Adaptors/ClaudeCode/ConversationLogParser.swift`

Add a new public method that scans the file for Agent tool_use calls, with optional offset for incremental scanning:

```swift
static func scanAllSubagents(atPath path: String, fromOffset: UInt64 = 0) -> [SubagentInfo]
```

Implementation strategy:
1. Open the file with `FileHandle`
2. Read in chunks (e.g., 256KB at a time) to avoid loading 45MB into memory
3. For each line, do a fast string check: `line.contains("\"Agent\"")` — skip lines that don't match
4. For matching lines, JSON-parse and extract Agent tool_use entries (same logic as `parseAssistantToolCalls`)
5. Also collect `tool_result` entries for completion status
6. Return the complete subagent list

This is a full-file scan but with a fast pre-filter. For a 45MB file, the string search is ~10ms; JSON parsing only happens for matching lines (~dozens at most).

#### Part C: Add incremental caching in ClaudeCodeAdaptor

**File:** `Sources/Adaptors/ClaudeCode/ClaudeCodeAdaptor.swift`

Add per-session cache state:

```swift
private var cachedSubagents: [String: [SubagentInfo]] = [:]
private var cachedTodos: [String: [TodoItem]] = [:]
private var lastScanOffset: [String: UInt64] = [:]
```

Modify `refreshConversationData()`:

```swift
private func refreshConversationData() {
    for (id, file) in sessionFiles {
        guard var session = activeSessions[id] else { continue }
        let path = ConversationLogParser.jsonlPath(cwd: file.cwd, sessionId: file.sessionId)

        // 1. Normal tail scan for ephemeral data
        let snap = ConversationLogParser.snapshot(atPath: path)
        session.sessionDescription = snap.sessionDescription
        session.lastUserPrompt = snap.lastUserPrompt
        session.lastAssistantMessage = snap.lastAssistantMessage
        session.permissionMode = snap.permissionMode
        session.isConversationCompressed = snap.isConversationCompressed

        // 2. Subagents: full scan on first load, incremental after
        let fileSize = ConversationLogParser.fileSize(atPath: path)
        let lastOffset = lastScanOffset[id] ?? 0
        if fileSize > lastOffset {
            // Scan new bytes for subagents (full scan on first call when lastOffset == 0)
            let allSubagents = ConversationLogParser.scanAllSubagents(
                atPath: path,
                fromOffset: lastOffset
            )
            var merged = cachedSubagents[id] ?? []
            for sub in allSubagents {
                if !merged.contains(where: { $0.description == sub.description && $0.agentType == sub.agentType }) {
                    merged.append(sub)
                } else if sub.isComplete, let idx = merged.firstIndex(where: { $0.description == sub.description && $0.agentType == sub.agentType }) {
                    merged[idx] = sub
                }
            }
            cachedSubagents[id] = merged
            lastScanOffset[id] = fileSize
        }

        // 3. Todos: use tail result if available, else keep cache
        if !snap.todos.isEmpty {
            cachedTodos[id] = snap.todos
        }

        session.subagents = cachedSubagents[id]
        session.todos = cachedTodos[id]
        activeSessions[id] = session
    }
}
```

**Why incremental:** After the first full scan, subsequent polls only scan new bytes (typically a few KB per 2-second poll). The `lastScanOffset` tracks how far we've read. We re-scan whenever the file has grown (any new data), since `scanAllSubagents(fromOffset:)` only reads from the offset to end — for small increments this is cheap (a few KB).

**Why cache todos separately:** The tail buffer handles todos for most conversations. But when the JSONL grows very large, the last TodoWrite may fall outside even the 256KB tail. The cache preserves the last known todo list until a newer one is found.

#### Exposing `jsonlPath` as package-internal

Currently `ConversationLogParser.jsonlPath(cwd:sessionId:)` is `private`. It needs to be `static func` (internal) so `ClaudeCodeAdaptor` can construct the path for `scanAllSubagents()`. Alternatively, `scanAllSubagents` can accept `cwd` + `sessionId` like `snapshot()` does.

Recommended: Add a `scanAllSubagents(cwd:sessionId:fromOffset:)` overload that internally calls `jsonlPath`. Keep the path-based version for testing.

---

## SubagentInfo Identity

Currently `SubagentInfo` has no stable identity field. The merge logic in Part C uses `(description, agentType)` as a composite key, which is fragile if two subagents have the same description.

Better approach: Add an `id: String` field to `SubagentInfo`, populated from the tool_use `id` in the JSONL. This provides a stable, unique key for merging.

```swift
struct SubagentInfo: Sendable, Equatable {
    let id: String            // tool_use id from JSONL
    let description: String
    let agentType: String
    let isComplete: Bool
}
```

Update `SubagentSectionView` to use `\.id` as the `ForEach` identity instead of `\.offset`.

---

## Cleanup: Remove Stale Cache Entries

In `ClaudeCodeAdaptor.updateSessions()`, when sessions are removed, also clean up their cache entries:

```swift
for id in removedIds {
    // ... existing cleanup ...
    cachedSubagents.removeValue(forKey: id)
    cachedTodos.removeValue(forKey: id)
    lastScanOffset.removeValue(forKey: id)
}
```

---

## Files Changed

| File | Action | Description |
|------|--------|-------------|
| `Sources/Core/PanelState.swift` | Modify | Add `collapseTimer`, 5s delay in `mouseExited()`, cancel in `mouseEntered()` |
| `Sources/UI/NotchRootView.swift` | Modify | Add `previousStatuses`, detect completion → auto-expand |
| `Sources/Infrastructure/WindowController.swift` | Modify | Add global click monitor for click-outside-to-collapse |
| `Sources/Core/SettingsStore.swift` | Modify | Change `dismissOnClickOutside` default to `true` |
| `Sources/Adaptors/ClaudeCode/ConversationLogParser.swift` | Modify | Increase tail to 256KB, add `scanAllSubagents()`, add `fileSize()` helper |
| `Sources/Core/Models/SubagentInfo.swift` | Modify | Add `id: String` field |
| `Sources/Adaptors/ClaudeCode/ClaudeCodeAdaptor.swift` | Modify | Add caching for subagents/todos, incremental scan logic |
| `Sources/UI/ExpandedPanel/SubagentSectionView.swift` | Modify | Use `\.id` for ForEach identity |
| `Tests/AdaptorTests/ConversationLogParserTests.swift` | Modify | Add tests for `scanAllSubagents()`, larger tail, SubagentInfo.id |
| `Tests/CoreTests/PanelStateTests.swift` | Modify | Add tests for 5s delay collapse, cancel on re-enter |

---

## Verification

1. `swift build` — zero errors
2. `swift test` — all tests pass (existing + new)
3. Manual verification:
   - [ ] Hover over notch, panel expands; move cursor away, panel stays for ~5s then collapses
   - [ ] Move cursor back within 5s, panel stays expanded (timer cancelled)
   - [ ] Click outside expanded panel, it collapses
   - [ ] Start a Claude session, let it run, verify subagent list shows ALL subagents (not just recent)
   - [ ] Let session run long enough for TodoWrite to fall outside 64KB, verify todos persist
   - [ ] Session completes → panel auto-expands to show result
   - [ ] Auto-expand does NOT fire when user is focused on the terminal that completed
   - [ ] Escape key still collapses panel
   - [ ] Confirmation auto-expand still works
   - [ ] Click-outside collapses even during active confirmations

---

## Scope Exclusions

- No disk persistence of cached data (cache is in-memory, lost on app restart)
- No settings UI changes beyond default toggle (click-outside default → true)
- No changes to poll intervals
- No changes to compact bar behavior
