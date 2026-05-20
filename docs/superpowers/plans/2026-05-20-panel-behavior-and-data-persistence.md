# Panel Behavior & Data Persistence — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 5 issues with the expanded panel: auto-expand on task completion, auto-collapse after 5s inactivity, click-outside-to-collapse, persist conversation data (todos/subagents) across panel cycles, and show complete subagent list matching VibeIsland.

**Architecture:** Add a `collapseTimer` to `PanelState` for delayed collapse. Install an `NSEvent.addGlobalMonitorForEvents` in `WindowController` for click-outside. Add completion detection via `onChange(of: sessionManager.sessions)` in `NotchRootView`. Fix data loss by increasing the JSONL tail buffer from 64KB to 256KB, adding a full-file `scanAllSubagents()` scanner in `ConversationLogParser`, and caching results in `ClaudeCodeAdaptor` with incremental offset tracking. Add a stable `id` field to `SubagentInfo` from the JSONL tool_use id.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, Swift Testing framework

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/Core/Models/SubagentInfo.swift` | Modify | Add `id: String` field |
| `Sources/Adaptors/ClaudeCode/ConversationLogParser.swift` | Modify | Increase tail to 256KB, expose `jsonlPath`, add `fileSize()`, add `scanAllSubagents()` |
| `Sources/Adaptors/ClaudeCode/ClaudeCodeAdaptor.swift` | Modify | Add per-session cache for subagents/todos, incremental scan, cleanup |
| `Sources/UI/ExpandedPanel/SubagentSectionView.swift` | Modify | Use `\.id` for ForEach identity |
| `Sources/Core/PanelState.swift` | Modify | Add `collapseTimer`, 5s delayed collapse, `autoCollapseDelay` |
| `Sources/Core/SettingsStore.swift` | Modify | Change `dismissOnClickOutside` default to `true` |
| `Sources/Infrastructure/WindowController.swift` | Modify | Add global click monitor |
| `Sources/UI/NotchRootView.swift` | Modify | Add `previousStatuses`, detect completion → expand |
| `Tests/AdaptorTests/ConversationLogParserTests.swift` | Modify | Add tests for `scanAllSubagents()`, SubagentInfo.id |
| `Tests/CoreTests/PanelStateTests.swift` | Modify | Add tests for 5s delayed collapse |

---

### Task 1: SubagentInfo — add id field

**Files:**
- Modify: `AgentIsland/Sources/Core/Models/SubagentInfo.swift`
- Modify: `AgentIsland/Sources/Adaptors/ClaudeCode/ConversationLogParser.swift:165-170`
- Modify: `AgentIsland/Tests/AdaptorTests/ConversationLogParserTests.swift`

- [ ] **Step 1: Write test for SubagentInfo.id**

Add a new test to `AgentIsland/Tests/AdaptorTests/ConversationLogParserTests.swift` after the `snapshotSubagents` test:

```swift
@Test("snapshot subagents include tool_use id")
func snapshotSubagentIds() throws {
    let path = try writeTempJSONL([
        #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Go"}]}}"#,
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_abc123","name":"Agent","input":{"description":"Search code","subagent_type":"Explore"}}]}}"#,
        #"{"type":"tool_result","tool_use_id":"toolu_abc123","content":"Done"}"#,
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_def456","name":"Agent","input":{"description":"Review changes","subagent_type":"code-reviewer"}}]}}"#
    ])

    let snap = ConversationLogParser.snapshot(atPath: path)

    #expect(snap.subagents.count == 2)
    let search = snap.subagents.first { $0.id == "toolu_abc123" }
    #expect(search != nil)
    #expect(search?.description == "Search code")
    #expect(search?.isComplete == true)
    let review = snap.subagents.first { $0.id == "toolu_def456" }
    #expect(review != nil)
    #expect(review?.description == "Review changes")
    #expect(review?.isComplete == false)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd AgentIsland && swift test --filter ConversationLogParserTests/snapshotSubagentIds 2>&1 | tail -10`
Expected: Compilation error — `SubagentInfo` has no member `id`.

- [ ] **Step 3: Add id to SubagentInfo**

Replace the full content of `AgentIsland/Sources/Core/Models/SubagentInfo.swift`:

```swift
import Foundation

struct SubagentInfo: Sendable, Equatable, Identifiable {
    let id: String
    let description: String
    let agentType: String
    let isComplete: Bool
}
```

- [ ] **Step 4: Update parser to pass id through**

In `AgentIsland/Sources/Adaptors/ClaudeCode/ConversationLogParser.swift`, find the subagent construction at lines 165-170:

```swift
let subagents = agentCalls.map { (id, info) in
    SubagentInfo(
        description: info.description,
        agentType: info.agentType,
        isComplete: completedToolIds.contains(id)
    )
}
```

Replace with:

```swift
let subagents = agentCalls.map { (id, info) in
    SubagentInfo(
        id: id,
        description: info.description,
        agentType: info.agentType,
        isComplete: completedToolIds.contains(id)
    )
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd AgentIsland && swift test --filter ConversationLogParserTests 2>&1 | tail -20`
Expected: All tests pass including the new `snapshotSubagentIds`.

- [ ] **Step 6: Commit**

```bash
git add AgentIsland/Sources/Core/Models/SubagentInfo.swift AgentIsland/Sources/Adaptors/ClaudeCode/ConversationLogParser.swift AgentIsland/Tests/AdaptorTests/ConversationLogParserTests.swift
git commit -m "feat: add stable id field to SubagentInfo from JSONL tool_use id"
```

---

### Task 2: ConversationLogParser — increase tail buffer, add scanAllSubagents

**Files:**
- Modify: `AgentIsland/Sources/Adaptors/ClaudeCode/ConversationLogParser.swift`
- Modify: `AgentIsland/Tests/AdaptorTests/ConversationLogParserTests.swift`

- [ ] **Step 1: Write test for scanAllSubagents**

Add to `AgentIsland/Tests/AdaptorTests/ConversationLogParserTests.swift`:

```swift
// MARK: - scanAllSubagents tests

@Test("scanAllSubagents finds all Agent tool_use calls across entire file")
func scanAllSubagentsFullScan() throws {
    let path = try writeTempJSONL([
        #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Start"}]}}"#,
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"ag1","name":"Agent","input":{"description":"Explore UI","subagent_type":"Explore"}}]}}"#,
        #"{"type":"tool_result","tool_use_id":"ag1","content":"Found files"}"#,
        #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Continue"}]}}"#,
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"ag2","name":"Agent","input":{"description":"Review code","subagent_type":"code-reviewer"}}]}}"#,
        #"{"type":"tool_result","tool_use_id":"ag2","content":"Looks good"}"#,
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"ag3","name":"Agent","input":{"description":"Run tests","subagent_type":"general"}}]}}"#
    ])

    let subagents = ConversationLogParser.scanAllSubagents(atPath: path)

    #expect(subagents.count == 3)
    let ag1 = subagents.first { $0.id == "ag1" }
    #expect(ag1?.description == "Explore UI")
    #expect(ag1?.agentType == "Explore")
    #expect(ag1?.isComplete == true)
    let ag2 = subagents.first { $0.id == "ag2" }
    #expect(ag2?.isComplete == true)
    let ag3 = subagents.first { $0.id == "ag3" }
    #expect(ag3?.isComplete == false)
}
```

- [ ] **Step 2: Write test for scanAllSubagents with fromOffset**

```swift
@Test("scanAllSubagents with fromOffset only scans new bytes")
func scanAllSubagentsIncremental() throws {
    let lines = [
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"ag1","name":"Agent","input":{"description":"First","subagent_type":"Explore"}}]}}"#,
        #"{"type":"tool_result","tool_use_id":"ag1","content":"Done"}"#,
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"ag2","name":"Agent","input":{"description":"Second","subagent_type":"Plan"}}]}}"#
    ]
    let path = try writeTempJSONL(lines)

    let firstLineBytes = UInt64((lines[0] + "\n").utf8.count)
    let secondLineBytes = UInt64((lines[1] + "\n").utf8.count)
    let offset = firstLineBytes + secondLineBytes

    let subagents = ConversationLogParser.scanAllSubagents(atPath: path, fromOffset: offset)

    #expect(subagents.count == 1)
    #expect(subagents[0].id == "ag2")
    #expect(subagents[0].description == "Second")
}
```

- [ ] **Step 3: Write test for fileSize helper**

```swift
@Test("fileSize returns correct byte count")
func fileSizeHelper() throws {
    let content = "hello\nworld\n"
    let path = try writeTempJSONL(["hello", "world"])
    let size = ConversationLogParser.fileSize(atPath: path)
    #expect(size > 0)
    #expect(size == UInt64(content.utf8.count))
}
```

- [ ] **Step 4: Write test for nonexistent file returns empty**

```swift
@Test("scanAllSubagents returns empty for nonexistent file")
func scanAllSubagentsNonexistent() {
    let result = ConversationLogParser.scanAllSubagents(atPath: "/tmp/nonexistent-\(UUID()).jsonl")
    #expect(result.isEmpty)
}

@Test("fileSize returns 0 for nonexistent file")
func fileSizeNonexistent() {
    let size = ConversationLogParser.fileSize(atPath: "/tmp/nonexistent-\(UUID()).jsonl")
    #expect(size == 0)
}
```

- [ ] **Step 5: Run tests to verify they fail**

Run: `cd AgentIsland && swift test --filter ConversationLogParserTests 2>&1 | tail -20`
Expected: Compilation errors — `scanAllSubagents` and `fileSize` don't exist.

- [ ] **Step 6: Increase tailReadSize to 256KB**

In `AgentIsland/Sources/Adaptors/ClaudeCode/ConversationLogParser.swift`, find line 20:

```swift
private static let tailReadSize: UInt64 = 65536
```

Replace with:

```swift
private static let tailReadSize: UInt64 = 262_144
```

- [ ] **Step 7: Change jsonlPath from private to static (internal)**

In `AgentIsland/Sources/Adaptors/ClaudeCode/ConversationLogParser.swift`, find line 222:

```swift
private static func jsonlPath(cwd: String, sessionId: String) -> String {
```

Replace with:

```swift
static func jsonlPath(cwd: String, sessionId: String) -> String {
```

- [ ] **Step 8: Add fileSize helper**

Add after the `jsonlPath` method:

```swift
static func fileSize(atPath path: String) -> UInt64 {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let size = attrs[.size] as? UInt64 else { return 0 }
    return size
}
```

- [ ] **Step 9: Add scanAllSubagents method**

Add after `fileSize`:

```swift
static func scanAllSubagents(atPath path: String, fromOffset: UInt64 = 0) -> [SubagentInfo] {
    guard let fileHandle = FileHandle(forReadingAtPath: path) else { return [] }
    defer { fileHandle.closeFile() }

    let fileSize = fileHandle.seekToEndOfFile()
    guard fileSize > fromOffset else { return [] }

    fileHandle.seek(toFileOffset: fromOffset)
    let data = fileHandle.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8) else { return [] }

    var lines = text.components(separatedBy: "\n")
    if fromOffset > 0 {
        lines.removeFirst()
    }

    var agentCalls: [String: (description: String, agentType: String)] = [:]
    var completedToolIds: Set<String> = []

    for line in lines {
        guard !line.isEmpty else { continue }
        guard line.contains("\"Agent\"") || line.contains("\"tool_result\"") else { continue }

        guard let lineData = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let type = obj["type"] as? String else { continue }

        if type == "assistant" {
            guard let message = obj["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { continue }
            for item in content {
                guard item["type"] as? String == "tool_use",
                      item["name"] as? String == "Agent",
                      let id = item["id"] as? String,
                      let input = item["input"] as? [String: Any] else { continue }
                let desc = input["description"] as? String ?? "Agent"
                let agentType = input["subagent_type"] as? String ?? "general"
                if agentCalls[id] == nil {
                    agentCalls[id] = (description: desc, agentType: agentType)
                }
            }
        } else if type == "tool_result" {
            if let toolUseId = obj["tool_use_id"] as? String {
                completedToolIds.insert(toolUseId)
            }
        }
    }

    return agentCalls.map { (id, info) in
        SubagentInfo(
            id: id,
            description: info.description,
            agentType: info.agentType,
            isComplete: completedToolIds.contains(id)
        )
    }
}
```

- [ ] **Step 10: Add scanAllSubagents overload with cwd/sessionId**

Add after the path-based version:

```swift
static func scanAllSubagents(cwd: String, sessionId: String, fromOffset: UInt64 = 0) -> [SubagentInfo] {
    let path = jsonlPath(cwd: cwd, sessionId: sessionId)
    return scanAllSubagents(atPath: path, fromOffset: fromOffset)
}
```

- [ ] **Step 11: Run tests to verify they pass**

Run: `cd AgentIsland && swift test --filter ConversationLogParserTests 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 12: Commit**

```bash
git add AgentIsland/Sources/Adaptors/ClaudeCode/ConversationLogParser.swift AgentIsland/Tests/AdaptorTests/ConversationLogParserTests.swift
git commit -m "feat: increase tail to 256KB, add scanAllSubagents for full-file subagent scan"
```

---

### Task 3: ClaudeCodeAdaptor — caching for subagents and todos

**Files:**
- Modify: `AgentIsland/Sources/Adaptors/ClaudeCode/ClaudeCodeAdaptor.swift`

- [ ] **Step 1: Add cache properties**

In `AgentIsland/Sources/Adaptors/ClaudeCode/ClaudeCodeAdaptor.swift`, add three new properties after line 10 (`private var responseCallbacks`):

```swift
private var cachedSubagents: [String: [SubagentInfo]] = [:]
private var cachedTodos: [String: [TodoItem]] = [:]
private var lastScanOffset: [String: UInt64] = [:]
```

- [ ] **Step 2: Replace refreshConversationData with caching version**

Replace the existing `refreshConversationData()` method (lines 150-163) with:

```swift
private func refreshConversationData() {
    for (id, file) in sessionFiles {
        guard var session = activeSessions[id] else { continue }
        let path = ConversationLogParser.jsonlPath(cwd: file.cwd, sessionId: file.sessionId)

        let snap = ConversationLogParser.snapshot(atPath: path)
        session.sessionDescription = snap.sessionDescription
        session.lastUserPrompt = snap.lastUserPrompt
        session.lastAssistantMessage = snap.lastAssistantMessage
        session.permissionMode = snap.permissionMode
        session.isConversationCompressed = snap.isConversationCompressed

        let currentFileSize = ConversationLogParser.fileSize(atPath: path)
        let lastOffset = lastScanOffset[id] ?? 0
        if currentFileSize > lastOffset {
            let newSubagents = ConversationLogParser.scanAllSubagents(
                atPath: path,
                fromOffset: lastOffset
            )
            var merged = cachedSubagents[id] ?? []
            for sub in newSubagents {
                if let idx = merged.firstIndex(where: { $0.id == sub.id }) {
                    merged[idx] = sub
                } else {
                    merged.append(sub)
                }
            }
            cachedSubagents[id] = merged
            lastScanOffset[id] = currentFileSize
        }

        if !snap.todos.isEmpty {
            cachedTodos[id] = snap.todos
        }

        session.subagents = cachedSubagents[id]
        session.todos = cachedTodos[id]
        activeSessions[id] = session
    }
}
```

- [ ] **Step 3: Add cache cleanup in updateSessions**

In the `updateSessions` method, find the loop over `removedIds` (lines 135-143). After the existing cleanup for `pendingRequests`, add cache cleanup:

```swift
for id in removedIds {
    if let confs = pendingRequests[id] {
        for conf in confs {
            responseCallbacks[conf.id]?(HookResponse(decision: "ask", reason: "Session ended"))
            responseCallbacks.removeValue(forKey: conf.id)
        }
    }
    pendingRequests.removeValue(forKey: id)
    cachedSubagents.removeValue(forKey: id)
    cachedTodos.removeValue(forKey: id)
    lastScanOffset.removeValue(forKey: id)
}
```

- [ ] **Step 4: Verify build**

Run: `cd AgentIsland && swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 5: Run full tests**

Run: `cd AgentIsland && swift test 2>&1 | tail -10`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add AgentIsland/Sources/Adaptors/ClaudeCode/ClaudeCodeAdaptor.swift
git commit -m "feat: add incremental caching for subagents and todos in adaptor"
```

---

### Task 4: SubagentSectionView — stable ForEach identity

**Files:**
- Modify: `AgentIsland/Sources/UI/ExpandedPanel/SubagentSectionView.swift`

- [ ] **Step 1: Update ForEach to use stable id**

In `AgentIsland/Sources/UI/ExpandedPanel/SubagentSectionView.swift`, find line 12:

```swift
ForEach(Array(subagents.enumerated()), id: \.offset) { _, agent in
```

Replace with:

```swift
ForEach(subagents) { agent in
```

This works because `SubagentInfo` now conforms to `Identifiable` (added in Task 1).

- [ ] **Step 2: Verify build**

Run: `cd AgentIsland && swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add AgentIsland/Sources/UI/ExpandedPanel/SubagentSectionView.swift
git commit -m "feat: use stable SubagentInfo.id for ForEach identity"
```

---

### Task 5: PanelState — 5-second delayed collapse

**Files:**
- Modify: `AgentIsland/Tests/CoreTests/PanelStateTests.swift`
- Modify: `AgentIsland/Sources/Core/PanelState.swift`

- [ ] **Step 1: Write test — mouseExited does NOT immediately collapse**

Add to `AgentIsland/Tests/CoreTests/PanelStateTests.swift`:

```swift
@MainActor
@Test("mouseExited starts delayed collapse, does not collapse immediately")
func mouseExitedDelayedCollapse() {
    let store = makeStore()
    store.autoCollapseOnMouseExit = true
    let state = PanelState(settingsStore: store, autoCollapseDelay: 5.0)
    state.expand()
    state.mouseExited()
    #expect(state.isExpanded == true)
}
```

- [ ] **Step 2: Write test — mouseEntered cancels pending collapse**

```swift
@MainActor
@Test("mouseEntered cancels pending collapse timer")
func mouseEnteredCancelsCollapse() {
    let store = makeStore()
    store.autoCollapseOnMouseExit = true
    let state = PanelState(settingsStore: store, autoCollapseDelay: 0.1)
    state.expand()
    state.mouseExited()
    #expect(state.isExpanded == true)
    state.mouseEntered()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
    #expect(state.isExpanded == true)
}
```

- [ ] **Step 3: Write test — collapse fires after delay**

```swift
@MainActor
@Test("mouseExited collapses panel after delay elapses")
func mouseExitedCollapsesAfterDelay() {
    let store = makeStore()
    store.autoCollapseOnMouseExit = true
    let state = PanelState(settingsStore: store, autoCollapseDelay: 0.1)
    state.expand()
    state.mouseExited()
    #expect(state.isExpanded == true)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
    #expect(state.isExpanded == false)
}
```

- [ ] **Step 4: Write test — autoCollapseOnMouseExit=false prevents collapse**

```swift
@MainActor
@Test("mouseExited does not collapse when autoCollapseOnMouseExit is false")
func mouseExitedNoCollapseWhenDisabled() {
    let store = makeStore()
    store.autoCollapseOnMouseExit = false
    let state = PanelState(settingsStore: store, autoCollapseDelay: 0.1)
    state.expand()
    state.mouseExited()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
    #expect(state.isExpanded == true)
}
```

- [ ] **Step 5: Run tests to verify they fail**

Run: `cd AgentIsland && swift test --filter PanelStateTests 2>&1 | tail -20`
Expected: `mouseExitedDelayedCollapse` fails — current `mouseExited()` collapses immediately. `mouseExitedCollapsesAfterDelay` may pass by accident. Other new tests fail because `PanelState.init` doesn't accept `autoCollapseDelay`.

- [ ] **Step 6: Implement delayed collapse in PanelState**

Replace the full content of `AgentIsland/Sources/Core/PanelState.swift`:

```swift
import Foundation

@MainActor
@Observable
final class PanelState {
    private(set) var isExpanded = false
    var confirmationsActive = false
    private var expandTimer: Timer?
    private var collapseTimer: Timer?
    private let autoCollapseDelay: TimeInterval
    @ObservationIgnored var onExpandChange: (() -> Void)?
    @ObservationIgnored var expandedContentHeight: CGFloat = 0 {
        didSet {
            guard isExpanded, expandedContentHeight != oldValue else { return }
            onExpandChange?()
        }
    }

    let settingsStore: SettingsStore

    init(settingsStore: SettingsStore, autoCollapseDelay: TimeInterval = 5.0) {
        self.settingsStore = settingsStore
        self.autoCollapseDelay = autoCollapseDelay
    }

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

    func mouseExited() {
        expandTimer?.invalidate()
        expandTimer = nil
        guard !confirmationsActive else { return }
        guard settingsStore.autoCollapseOnMouseExit else { return }
        collapseTimer?.invalidate()
        collapseTimer = Timer.scheduledTimer(withTimeInterval: autoCollapseDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.collapse()
            }
        }
    }

    func expand() {
        collapseTimer?.invalidate()
        collapseTimer = nil
        isExpanded = true
        onExpandChange?()
    }

    func collapse() {
        collapseTimer?.invalidate()
        collapseTimer = nil
        isExpanded = false
        onExpandChange?()
    }

    func autoExpand() {
        confirmationsActive = true
        expandTimer?.invalidate()
        collapseTimer?.invalidate()
        collapseTimer = nil
        expand()
    }

    func toggle() {
        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd AgentIsland && swift test --filter PanelStateTests 2>&1 | tail -20`
Expected: All tests pass (existing + 4 new).

- [ ] **Step 8: Commit**

```bash
git add AgentIsland/Sources/Core/PanelState.swift AgentIsland/Tests/CoreTests/PanelStateTests.swift
git commit -m "feat: replace immediate collapse with 5s delayed collapse timer"
```

---

### Task 6: Click outside to collapse

**Files:**
- Modify: `AgentIsland/Sources/Core/SettingsStore.swift:60`
- Modify: `AgentIsland/Sources/Infrastructure/WindowController.swift`

- [ ] **Step 1: Change dismissOnClickOutside default to true**

In `AgentIsland/Sources/Core/SettingsStore.swift`, find line 60:

```swift
autoCollapseOnMouseExit = true; autoReminderDuration = 5.0; dismissOnClickOutside = false
```

Replace `dismissOnClickOutside = false` with `dismissOnClickOutside = true`:

```swift
autoCollapseOnMouseExit = true; autoReminderDuration = 5.0; dismissOnClickOutside = true
```

Also update the `resetToDefaults()` method at line 80 — same change:

```swift
autoCollapseOnMouseExit = true; autoReminderDuration = 5.0; dismissOnClickOutside = true
```

- [ ] **Step 2: Add globalClickMonitor property to WindowController**

In `AgentIsland/Sources/Infrastructure/WindowController.swift`, add after line 17 (`private var displayChangeObserver`):

```swift
private var globalClickMonitor: Any?
```

- [ ] **Step 3: Add installGlobalClickMonitor method**

Add after the `setupDisplayChangeObserver()` method (after line 193):

```swift
private func installGlobalClickMonitor() {
    globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
        Task { @MainActor in
            guard let self, let panel = self.panel else { return }
            guard self.panelState.isExpanded else { return }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                self.panelState.confirmationsActive = false
                self.panelState.collapse()
            }
        }
    }
}
```

- [ ] **Step 4: Install monitor in showCompactBar**

In `showCompactBar()`, find line 64-65:

```swift
setupTracking(panel: panel); setupKeyMonitor()
setupFullscreenObserver(); setupDisplayChangeObserver()
```

Add after:

```swift
if settingsStore.dismissOnClickOutside {
    installGlobalClickMonitor()
}
```

- [ ] **Step 5: Verify build**

Run: `cd AgentIsland && swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 6: Run full tests**

Run: `cd AgentIsland && swift test 2>&1 | tail -10`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add AgentIsland/Sources/Core/SettingsStore.swift AgentIsland/Sources/Infrastructure/WindowController.swift
git commit -m "feat: add click-outside-to-collapse with global mouse monitor"
```

---

### Task 7: Auto-expand on session completion

**Files:**
- Modify: `AgentIsland/Sources/UI/NotchRootView.swift`

- [ ] **Step 1: Add previousStatuses state**

In `AgentIsland/Sources/UI/NotchRootView.swift`, add after line 8 (`let windowActivator`):

```swift
@State private var previousStatuses: [String: SessionStatus] = [:]
```

- [ ] **Step 2: Add onChange handler for session completion detection**

Add a new `.onChange` modifier after the existing `.onChange(of: frontmostAppMonitor.frontmostAppPID)` block (after line 86):

```swift
.onChange(of: sessionManager.sessions) {
    let currentStatuses = Dictionary(
        uniqueKeysWithValues: sessionManager.sessions.map { ($0.id, $0.status) }
    )
    defer { previousStatuses = currentStatuses }

    guard !panelState.isExpanded else { return }

    for (id, currentStatus) in currentStatuses {
        guard case .completed = currentStatus else { continue }
        guard let previous = previousStatuses[id] else { continue }
        let wasActive: Bool
        switch previous {
        case .executing, .thinking, .waitingConfirmation:
            wasActive = true
        default:
            wasActive = false
        }
        guard wasActive else { continue }

        if let session = sessionManager.sessions.first(where: { $0.id == id }),
           !frontmostAppMonitor.isTerminalOfSession(session) {
            panelState.expand()
            return
        }
    }
}
```

Key design decisions:
- Uses `panelState.expand()` (NOT `autoExpand()`) — this allows the 5s auto-collapse timer to still work. `autoExpand()` sets `confirmationsActive = true` which would lock the panel open.
- Checks `frontmostAppMonitor.isTerminalOfSession()` — suppresses auto-expand when user is already looking at the terminal that completed.
- Only triggers for transitions from active statuses (`.executing`, `.thinking`, `.waitingConfirmation`) to `.completed`.
- `guard !panelState.isExpanded` — no need to auto-expand if already expanded.

- [ ] **Step 3: Verify build**

Run: `cd AgentIsland && swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 4: Run full tests**

Run: `cd AgentIsland && swift test 2>&1 | tail -10`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add AgentIsland/Sources/UI/NotchRootView.swift
git commit -m "feat: auto-expand panel when session transitions to completed"
```

---

### Task 8: Full build, test, and manual verification

**Files:** None (verification only)

- [ ] **Step 1: Full build**

Run: `cd AgentIsland && swift build 2>&1 | tail -10`
Expected: Build succeeds with zero errors.

- [ ] **Step 2: Run all tests**

Run: `cd AgentIsland && swift test 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 3: Run the app**

Run: `cd AgentIsland && swift build && .build/debug/AgentIsland &`
Launch the app and hover over the notch area to expand the panel.

- [ ] **Step 4: Manual verification checklist**

Verify each item:
- [ ] Hover over notch, panel expands; move cursor away, panel stays for ~5s then collapses
- [ ] Move cursor back within 5s, panel stays expanded (collapse timer cancelled)
- [ ] Click outside expanded panel, it collapses
- [ ] Click outside collapses even during active confirmations
- [ ] Start a Claude session, let it run with subagents, verify ALL subagents show (not just recent)
- [ ] Let session run long enough for TodoWrite to fall outside 64KB, verify todos persist
- [ ] Session completes → panel auto-expands to show result
- [ ] Auto-expand does NOT fire when user is focused on the terminal that completed
- [ ] Escape key still collapses panel
- [ ] Confirmation auto-expand still works
- [ ] Hover highlight and click-to-jump still work

- [ ] **Step 5: Fix any issues found during manual verification**

If any fixes needed:
```bash
git add -A && git commit -m "fix: polish panel behavior after manual verification"
```

- [ ] **Step 6: Update devlog**

Create or update `devlog/2026-05-20.md` using the template at `devlog/template.md`.
