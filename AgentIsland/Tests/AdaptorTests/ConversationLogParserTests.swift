import Testing
import Foundation
@testable import AgentIsland

@Suite("ConversationLogParser Tests")
struct ConversationLogParserTests {

    private func writeTempJSONL(_ lines: [String]) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConversationLogParserTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let filePath = tempDir.appendingPathComponent("test.jsonl").path
        let content = lines.joined(separator: "\n") + "\n"
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)
        return filePath
    }

    // MARK: - lastMessages compatibility tests

    @Test("extracts last user and assistant text messages")
    func extractLastMessages() throws {
        let path = try writeTempJSONL([
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"First prompt"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"First reply"}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Second prompt"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Second reply"}]}}"#
        ])

        let msgs = ConversationLogParser.lastMessages(atPath: path)

        #expect(msgs.userPrompt == "Second prompt")
        #expect(msgs.assistantMessage == "Second reply")
    }

    @Test("returns nil for nonexistent file")
    func nonexistentFile() {
        let msgs = ConversationLogParser.lastMessages(atPath: "/tmp/nonexistent-\(UUID()).jsonl")

        #expect(msgs.userPrompt == nil)
        #expect(msgs.assistantMessage == nil)
    }

    @Test("returns nil for empty file")
    func emptyFile() throws {
        let path = try writeTempJSONL([])

        let msgs = ConversationLogParser.lastMessages(atPath: path)

        #expect(msgs.userPrompt == nil)
        #expect(msgs.assistantMessage == nil)
    }

    @Test("skips assistant messages with only tool_use content")
    func toolUseOnlyAssistant() throws {
        let path = try writeTempJSONL([
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Run tests"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"swift test"}}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Tests passed"}]}}"#
        ])

        let msgs = ConversationLogParser.lastMessages(atPath: path)

        #expect(msgs.userPrompt == "Run tests")
        #expect(msgs.assistantMessage == "Tests passed")
    }

    @Test("returns nil assistantMessage when all assistant messages are tool_use only")
    func allToolUseAssistant() throws {
        let path = try writeTempJSONL([
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Do something"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Read","input":{}}]}}"#
        ])

        let msgs = ConversationLogParser.lastMessages(atPath: path)

        #expect(msgs.userPrompt == "Do something")
        #expect(msgs.assistantMessage == nil)
    }

    @Test("truncates text exceeding 200 characters")
    func truncatesLongText() throws {
        let longText = String(repeating: "A", count: 500)
        let path = try writeTempJSONL([
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":""# + longText + #""}]}}"#
        ])

        let msgs = ConversationLogParser.lastMessages(atPath: path)

        #expect(msgs.userPrompt?.count == 200)
    }

    @Test("skips non-message JSONL types")
    func skipsNonMessageTypes() throws {
        let path = try writeTempJSONL([
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Hello"}]}}"#,
            #"{"type":"queue-operation","operation":"enqueue"}"#,
            #"{"type":"last-prompt"}"#,
            #"{"type":"ai-title","title":"Test"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"World"}]}}"#
        ])

        let msgs = ConversationLogParser.lastMessages(atPath: path)

        #expect(msgs.userPrompt == "Hello")
        #expect(msgs.assistantMessage == "World")
    }

    @Test("handles user content with image and text blocks")
    func userWithImageAndText() throws {
        let path = try writeTempJSONL([
            #"{"type":"user","message":{"role":"user","content":[{"type":"image","source":{"data":"..."}},{"type":"text","text":"What is this?"}]}}"#
        ])

        let msgs = ConversationLogParser.lastMessages(atPath: path)

        #expect(msgs.userPrompt == "What is this?")
    }

    @Test("replaces newlines with spaces in extracted text")
    func replacesNewlines() throws {
        let path = try writeTempJSONL([
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"line one\nline two\nline three"}]}}"#
        ])

        let msgs = ConversationLogParser.lastMessages(atPath: path)

        #expect(msgs.userPrompt == "line one line two line three")
    }

    @Test("skips empty text content")
    func skipsEmptyText() throws {
        let path = try writeTempJSONL([
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":""}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Real input"}]}}"#
        ])

        let msgs = ConversationLogParser.lastMessages(atPath: path)

        #expect(msgs.userPrompt == "Real input")
    }

    @Test("lastMessages with cwd and sessionId constructs correct path")
    func cwdAndSessionId() {
        let msgs = ConversationLogParser.lastMessages(cwd: "/nonexistent/path", sessionId: "fake-id")

        #expect(msgs.userPrompt == nil)
        #expect(msgs.assistantMessage == nil)
    }

    // MARK: - Snapshot tests

    @Test("snapshot extracts sessionDescription from first user message")
    func snapshotSessionDescription() throws {
        let path = try writeTempJSONL([
            #"{"type":"queue-operation","operation":"enqueue"}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Build a macOS app for monitoring agents"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Sure, let me start."}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Add dark mode"}]}}"#
        ])

        let snap = ConversationLogParser.snapshot(atPath: path)

        #expect(snap.sessionDescription == "Build a macOS app for monitoring agents")
        #expect(snap.lastUserPrompt == "Add dark mode")
        #expect(snap.lastAssistantMessage == "Sure, let me start.")
    }

    @Test("snapshot extracts todos from last TodoWrite call")
    func snapshotTodos() throws {
        let path = try writeTempJSONL([
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Start"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tw1","name":"TodoWrite","input":{"todos":[{"content":"Task A","status":"completed","activeForm":"Doing A"},{"content":"Task B","status":"in_progress","activeForm":"Doing B"}]}}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tw2","name":"TodoWrite","input":{"todos":[{"content":"Task A","status":"completed","activeForm":"Doing A"},{"content":"Task B","status":"completed","activeForm":"Doing B"},{"content":"Task C","status":"in_progress","activeForm":"Doing C"}]}}]}}"#
        ])

        let snap = ConversationLogParser.snapshot(atPath: path)

        #expect(snap.todos.count == 3)
        #expect(snap.todos[0].content == "Task A")
        #expect(snap.todos[0].status == .completed)
        #expect(snap.todos[1].content == "Task B")
        #expect(snap.todos[1].status == .completed)
        #expect(snap.todos[2].content == "Task C")
        #expect(snap.todos[2].status == .inProgress)
    }

    @Test("snapshot extracts subagent info with completion status")
    func snapshotSubagents() throws {
        let path = try writeTempJSONL([
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Research"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"ag1","name":"Agent","input":{"description":"Explore UI code","subagent_type":"Explore"}}]}}"#,
            #"{"type":"tool_result","tool_use_id":"ag1","content":"Found 5 files"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"ag2","name":"Agent","input":{"description":"Plan implementation","subagent_type":"Plan"}}]}}"#
        ])

        let snap = ConversationLogParser.snapshot(atPath: path)

        #expect(snap.subagents.count == 2)

        let explore = snap.subagents.first { $0.description == "Explore UI code" }
        #expect(explore != nil)
        #expect(explore?.agentType == "Explore")
        #expect(explore?.isComplete == true)

        let plan = snap.subagents.first { $0.description == "Plan implementation" }
        #expect(plan != nil)
        #expect(plan?.agentType == "Plan")
        #expect(plan?.isComplete == false)
    }

    @Test("snapshot returns empty todos and subagents when none present")
    func snapshotEmptyExtras() throws {
        let path = try writeTempJSONL([
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Hello"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}]}}"#
        ])

        let snap = ConversationLogParser.snapshot(atPath: path)

        #expect(snap.todos.isEmpty)
        #expect(snap.subagents.isEmpty)
    }

    @Test("snapshot with nonexistent file returns empty snapshot")
    func snapshotNonexistent() {
        let snap = ConversationLogParser.snapshot(atPath: "/tmp/nonexistent-\(UUID()).jsonl")

        #expect(snap.sessionDescription == nil)
        #expect(snap.lastUserPrompt == nil)
        #expect(snap.lastAssistantMessage == nil)
        #expect(snap.todos.isEmpty)
        #expect(snap.subagents.isEmpty)
        #expect(snap.permissionMode == nil)
        #expect(snap.isConversationCompressed == false)
    }

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

    @Test("snapshot returns nil permissionMode when field absent")
    func snapshotPermissionModeNil() throws {
        let path = try writeTempJSONL([
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Hello"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}]}}"#
        ])
        let snap = ConversationLogParser.snapshot(atPath: path)
        #expect(snap.permissionMode == nil)
    }

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

    @Test("snapshot returns false when no compaction occurred")
    func snapshotNotCompressed() throws {
        let path = try writeTempJSONL([
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Hello"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}]}}"#
        ])
        let snap = ConversationLogParser.snapshot(atPath: path)
        #expect(snap.isConversationCompressed == false)
    }

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

    @Test("snapshot ignores invalid todo items gracefully")
    func snapshotInvalidTodos() throws {
        let path = try writeTempJSONL([
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Go"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tw1","name":"TodoWrite","input":{"todos":[{"content":"Valid","status":"pending","activeForm":"Doing"},{"status":"bad_status","activeForm":"X"}]}}]}}"#
        ])

        let snap = ConversationLogParser.snapshot(atPath: path)

        #expect(snap.todos.count == 1)
        #expect(snap.todos[0].content == "Valid")
    }

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

    @Test("fileSize returns correct byte count")
    func fileSizeHelper() throws {
        let content = "hello\nworld\n"
        let path = try writeTempJSONL(["hello", "world"])
        let size = ConversationLogParser.fileSize(atPath: path)
        #expect(size > 0)
        #expect(size == UInt64(content.utf8.count))
    }

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
}
