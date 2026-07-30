import Testing
import Foundation
@testable import AgentIsland

@Suite("BridgeServer Session Lifecycle Tests")
struct BridgeServerTests {

    private func makeBridgeServer() throws -> BridgeServer {
        let tmpDir = NSTemporaryDirectory() + UUID().uuidString
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        let configs = [
            AgentConfig(
                agentType: .claudeCode, tag: "claude", displayName: "Claude Code",
                socketPath: tmpDir + "/claude.sock",
                hookSettingsPath: tmpDir + "/claude/settings.json",
                hookTypes: AgentConfig.claude.hookTypes,
                requiresExistingDir: false,
                idleTimeout: nil
            ),
            AgentConfig(
                agentType: .codex, tag: "codex", displayName: "Codex",
                socketPath: tmpDir + "/codex.sock",
                hookSettingsPath: tmpDir + "/nonexistent/hooks.json",
                hookTypes: AgentConfig.codex.hookTypes,
                requiresExistingDir: true,
                idleTimeout: 7200
            ),
            AgentConfig(
                agentType: .qoderWork, tag: "qoderwork", displayName: "QoderWork",
                socketPath: tmpDir + "/qoderwork.sock",
                hookSettingsPath: tmpDir + "/nonexistent/settings.json",
                hookTypes: AgentConfig.qoderWork.hookTypes,
                requiresExistingDir: true,
                idleTimeout: nil
            ),
        ]
        return try BridgeServer(configs: configs)
    }

    private func makeHookMessage(
        type: String, sessionId: String = "test-session-1",
        toolName: String? = nil, toolInput: [String: AnyCodable]? = nil,
        prompt: String? = nil, cwd: String? = nil
    ) -> HookMessage {
        HookMessage(
            type: type, sessionId: sessionId, toolName: toolName,
            toolInput: toolInput, permissionLevel: nil,
            prompt: prompt, cwd: cwd
        )
    }

    // MARK: - Session Creation & Upsert

    @Test("1. Session created on first hook")
    func sessionCreatedOnFirstHook() async throws {
        let server = try makeBridgeServer()
        let msg = makeHookMessage(type: "SessionStart")
        let respond = { @Sendable (_: HookResponse) in }

        await server.handleClaudeStatusHook(message: msg, sessionId: "claudeCode-test-session-1", respond: respond)

        let sessions = await server.sessions
        #expect(sessions["claudeCode-test-session-1"] != nil)
        #expect(sessions["claudeCode-test-session-1"]?.status == .idle)
    }

    @Test("2. Session upsert on restart — no duplicate")
    func sessionUpsertOnRestart() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg1 = makeHookMessage(type: "SessionStart")
        await server.handleClaudeStatusHook(message: msg1, sessionId: "claudeCode-test-session-1", respond: respond)

        let msg2 = makeHookMessage(type: "UserPromptSubmit")
        await server.handleClaudeStatusHook(message: msg2, sessionId: "claudeCode-test-session-1", respond: respond)

        let msg3 = makeHookMessage(type: "SessionStart")
        await server.handleClaudeStatusHook(message: msg3, sessionId: "claudeCode-test-session-1", respond: respond)

        let sessions = await server.sessions
        #expect(sessions.count == 1)
        #expect(sessions["claudeCode-test-session-1"]?.status == .idle)
    }

    // MARK: - Status Transitions

    @Test("3. PreToolUse transitions status based on tool name")
    func preToolUseTransitionsStatus() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }
        let sid = "s1"
        let internalId = "claudeCode-\(sid)"

        let startMsg = makeHookMessage(type: "UserPromptSubmit", sessionId: sid)
        await server.handleClaudeStatusHook(message: startMsg, sessionId: internalId, respond: respond)

        let readMsg = makeHookMessage(type: "PreToolUse", sessionId: sid, toolName: "Read")
        await server.handleClaudeStatusHook(message: readMsg, sessionId: internalId, respond: respond)
        let s1 = await server.sessions[internalId]
        #expect(s1?.status == .reading)

        let editMsg = makeHookMessage(type: "PreToolUse", sessionId: sid, toolName: "Edit")
        await server.handleClaudeStatusHook(message: editMsg, sessionId: internalId, respond: respond)
        let s2 = await server.sessions[internalId]
        #expect(s2?.status == .editing)

        let bashMsg = makeHookMessage(type: "PreToolUse", sessionId: sid, toolName: "Bash")
        await server.handleClaudeStatusHook(message: bashMsg, sessionId: internalId, respond: respond)
        let s3 = await server.sessions[internalId]
        #expect(s3?.status == .executing)
    }

    @Test("4. PostToolUse clears currentToolCall")
    func postToolUseClearsToolCall() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg1 = makeHookMessage(type: "UserPromptSubmit", sessionId: "s1")
        await server.handleQoderWorkStatusHook(
            message: msg1, sessionId: "qoderWork-s1", clientPID: nil, respond: respond
        )

        let msg2 = makeHookMessage(
            type: "PreToolUse", sessionId: "s1", toolName: "Bash",
            toolInput: ["command": AnyCodable("ls -la")]
        )
        await server.handleQoderWorkStatusHook(
            message: msg2, sessionId: "qoderWork-s1", clientPID: nil, respond: respond
        )
        let s1 = await server.sessions["qoderWork-s1"]
        #expect(s1?.currentToolCall != nil)

        let msg3 = makeHookMessage(type: "PostToolUse", sessionId: "s1")
        await server.handleQoderWorkStatusHook(
            message: msg3, sessionId: "qoderWork-s1", clientPID: nil, respond: respond
        )
        let s2 = await server.sessions["qoderWork-s1"]
        #expect(s2?.currentToolCall == nil)
    }

    @Test("5. Claude Stop transitions to completed")
    func stopTransitionsToCompleted() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }
        let sid = "s1"
        let internalId = "claudeCode-\(sid)"

        let msg1 = makeHookMessage(type: "UserPromptSubmit", sessionId: sid)
        await server.handleClaudeStatusHook(message: msg1, sessionId: internalId, respond: respond)
        let s1 = await server.sessions[internalId]
        #expect(s1?.status == .executing)

        let msg2 = makeHookMessage(type: "Stop", sessionId: sid)
        await server.handleClaudeStatusHook(message: msg2, sessionId: internalId, respond: respond)
        let s2 = await server.sessions[internalId]
        #expect(s2?.status == .completed)
    }

    @Test("6. UserPromptSubmit transitions to executing")
    func userPromptSubmitTransitions() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }
        let sid = "s1"
        let internalId = "claudeCode-\(sid)"

        let msg = makeHookMessage(type: "UserPromptSubmit", sessionId: sid)
        await server.handleClaudeStatusHook(message: msg, sessionId: internalId, respond: respond)
        let s = await server.sessions[internalId]
        #expect(s?.status == .executing)
    }

    @Test("7. Unknown hook type returns empty, no crash")
    func unknownHookTypeReturnsEmpty() async throws {
        let server = try makeBridgeServer()
        var captured: HookResponse?
        let respond: @Sendable (HookResponse) -> Void = { captured = $0 }
        let sid = "s1"
        let internalId = "claudeCode-\(sid)"

        let msg = makeHookMessage(type: "SomethingWeird", sessionId: sid)
        await server.handleClaudeStatusHook(message: msg, sessionId: internalId, respond: respond)

        #expect(captured == .empty)
        let sessions = await server.sessions
        #expect(sessions[internalId] == nil)
    }

    // MARK: - Cross-Agent Independence

    @Test("8. Cross-agent sessions are independent")
    func crossAgentIndependence() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let claudeMsg = makeHookMessage(type: "UserPromptSubmit", sessionId: "shared-id")
        await server.handleClaudeStatusHook(message: claudeMsg, sessionId: "claudeCode-shared-id", respond: respond)

        let qoderMsg = makeHookMessage(type: "Stop", sessionId: "shared-id", cwd: "/tmp/test")
        await server.handleQoderWorkStatusHook(
            message: qoderMsg, sessionId: "qoderWork-shared-id", clientPID: nil, respond: respond
        )

        let sessions = await server.sessions
        #expect(sessions["claudeCode-shared-id"]?.status == .executing)
        #expect(sessions["qoderWork-shared-id"]?.status == .idle)
    }

    @Test("9. Session IDs namespaced by agent type")
    func sessionIdNamespacedByAgent() async throws {
        let server = try makeBridgeServer()
        let claudeId = await server.internalSessionId(agentType: .claudeCode, hookSessionId: "abc")
        let codexId = await server.internalSessionId(agentType: .codex, hookSessionId: "abc")
        let qoderWorkId = await server.internalSessionId(agentType: .qoderWork, hookSessionId: "abc")

        #expect(claudeId == "claudeCode-abc")
        #expect(codexId == "codex-abc")
        #expect(qoderWorkId == "qoderWork-abc")
        #expect(claudeId != codexId)
        #expect(claudeId != qoderWorkId)
    }

    // MARK: - Codex Idle Timeout (via generic handler)

    @Test("10. Codex sessions removed after idle timeout")
    func codexIdleTimeout() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg = makeHookMessage(type: "SessionStart", sessionId: "codex-1")
        await server.handleGenericStatusHook(
            message: msg, sessionId: "codex-codex-1",
            agentType: .codex, displayName: "Codex", respond: respond
        )

        let s1 = await server.sessions["codex-codex-1"]
        #expect(s1 != nil)

        let pastDate = Date().addingTimeInterval(-7201)
        await server.setLastActivityDate(pastDate, for: "codex-codex-1")
        await server.cleanupIdleSessions(agentType: .codex, timeout: 7200)

        let s2 = await server.sessions["codex-codex-1"]
        #expect(s2 == nil)
    }

    // MARK: - QoderWork Specifics

    @Test("11. QoderWork title derived from cwd")
    func qoderWorkTitleFromCwd() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg = makeHookMessage(type: "SessionStart", sessionId: "q1", cwd: "/Users/test/my-project")
        await server.handleQoderWorkStatusHook(
            message: msg, sessionId: "qoderWork-q1", clientPID: nil, respond: respond
        )

        let session = await server.sessions["qoderWork-q1"]
        #expect(session?.title == "my-project")
    }

    @Test("12. QoderWork UserPromptSubmit updates title from prompt")
    func qoderWorkTitleFromPrompt() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg1 = makeHookMessage(type: "SessionStart", sessionId: "q2")
        await server.handleQoderWorkStatusHook(
            message: msg1, sessionId: "qoderWork-q2", clientPID: nil, respond: respond
        )

        let msg2 = makeHookMessage(
            type: "UserPromptSubmit", sessionId: "q2",
            prompt: "Fix the login bug in auth module"
        )
        await server.handleQoderWorkStatusHook(
            message: msg2, sessionId: "qoderWork-q2", clientPID: nil, respond: respond
        )

        let session = await server.sessions["qoderWork-q2"]
        #expect(session?.title == "Fix the login bug in auth module")
    }

    @Test("13. QoderWork TodoWrite updates session todos")
    func qoderWorkTodoWrite() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg1 = makeHookMessage(type: "UserPromptSubmit", sessionId: "q3")
        await server.handleQoderWorkStatusHook(
            message: msg1, sessionId: "qoderWork-q3", clientPID: nil, respond: respond
        )

        let todosInput: [String: AnyCodable] = [
            "todos": AnyCodable([
                ["content": "Fix bug", "status": "in_progress", "activeForm": "Fixing bug"] as [String: Any],
                ["content": "Add tests", "status": "pending", "activeForm": "Adding tests"] as [String: Any],
            ] as [[String: Any]])
        ]
        let msg2 = makeHookMessage(
            type: "PreToolUse", sessionId: "q3", toolName: "TodoWrite", toolInput: todosInput
        )
        await server.handleQoderWorkStatusHook(
            message: msg2, sessionId: "qoderWork-q3", clientPID: nil, respond: respond
        )

        let session = await server.sessions["qoderWork-q3"]
        #expect(session?.todos?.count == 2)
        #expect(session?.todos?.first?.content == "Fix bug")
    }

    @Test("14. QoderWork Agent tool adds subagent")
    func qoderWorkAgentSubagent() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg1 = makeHookMessage(type: "UserPromptSubmit", sessionId: "q4")
        await server.handleQoderWorkStatusHook(
            message: msg1, sessionId: "qoderWork-q4", clientPID: nil, respond: respond
        )

        let agentInput: [String: AnyCodable] = [
            "description": AnyCodable("Search for tests"),
            "subagent_type": AnyCodable("Explore"),
        ]
        let msg2 = makeHookMessage(
            type: "PreToolUse", sessionId: "q4", toolName: "Agent", toolInput: agentInput
        )
        await server.handleQoderWorkStatusHook(
            message: msg2, sessionId: "qoderWork-q4", clientPID: nil, respond: respond
        )

        let session = await server.sessions["qoderWork-q4"]
        #expect(session?.subagents?.count == 1)
        #expect(session?.subagents?.first?.description == "Search for tests")
    }

    @Test("15. QoderWork SubagentStop completes subagent")
    func qoderWorkSubagentStop() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg1 = makeHookMessage(type: "UserPromptSubmit", sessionId: "q5")
        await server.handleQoderWorkStatusHook(
            message: msg1, sessionId: "qoderWork-q5", clientPID: nil, respond: respond
        )

        let agentInput: [String: AnyCodable] = [
            "description": AnyCodable("Research task"),
            "subagent_type": AnyCodable("general"),
        ]
        let msg2 = makeHookMessage(
            type: "PreToolUse", sessionId: "q5", toolName: "Agent", toolInput: agentInput
        )
        await server.handleQoderWorkStatusHook(
            message: msg2, sessionId: "qoderWork-q5", clientPID: nil, respond: respond
        )

        let msg3 = makeHookMessage(type: "SubagentStop", sessionId: "q5")
        await server.handleQoderWorkStatusHook(
            message: msg3, sessionId: "qoderWork-q5", clientPID: nil, respond: respond
        )

        let session = await server.sessions["qoderWork-q5"]
        #expect(session?.subagents == nil)
    }

    @Test("16. QoderWork strips system-reminder from prompt")
    func qoderWorkStripsSystemReminder() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg1 = makeHookMessage(type: "SessionStart", sessionId: "q6")
        await server.handleQoderWorkStatusHook(
            message: msg1, sessionId: "qoderWork-q6", clientPID: nil, respond: respond
        )

        let msg2 = makeHookMessage(
            type: "UserPromptSubmit", sessionId: "q6",
            prompt: "<system-reminder>hidden</system-reminder>Fix the bug"
        )
        await server.handleQoderWorkStatusHook(
            message: msg2, sessionId: "qoderWork-q6", clientPID: nil, respond: respond
        )

        let session = await server.sessions["qoderWork-q6"]
        #expect(session?.lastUserPrompt == "Fix the bug")
        #expect(session?.title == "Fix the bug")
    }

    // MARK: - QoderWork Status Isolation

    @Test("QoderWork PreToolUse updates metadata without changing status")
    func qoderWorkPreToolUseMetadataOnly() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg1 = makeHookMessage(type: "SessionStart", sessionId: "q-meta")
        await server.handleQoderWorkStatusHook(
            message: msg1, sessionId: "qoderWork-q-meta", clientPID: nil, respond: respond
        )
        #expect((await server.sessions["qoderWork-q-meta"])?.status == .idle)

        let msg2 = makeHookMessage(
            type: "PreToolUse", sessionId: "q-meta", toolName: "Read",
            toolInput: ["file_path": AnyCodable("/tmp/test.swift")]
        )
        await server.handleQoderWorkStatusHook(
            message: msg2, sessionId: "qoderWork-q-meta", clientPID: nil, respond: respond
        )
        let s = await server.sessions["qoderWork-q-meta"]
        #expect(s?.status == .idle)
        #expect(s?.currentToolCall != nil)
    }

    @Test("QoderWork PostToolUse clears metadata without changing status")
    func qoderWorkPostToolUseMetadataOnly() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg1 = makeHookMessage(type: "UserPromptSubmit", sessionId: "q-post")
        await server.handleQoderWorkStatusHook(
            message: msg1, sessionId: "qoderWork-q-post", clientPID: nil, respond: respond
        )
        #expect((await server.sessions["qoderWork-q-post"])?.status == .executing)

        let msg2 = makeHookMessage(
            type: "PreToolUse", sessionId: "q-post", toolName: "Bash",
            toolInput: ["command": AnyCodable("ls")]
        )
        await server.handleQoderWorkStatusHook(
            message: msg2, sessionId: "qoderWork-q-post", clientPID: nil, respond: respond
        )
        #expect((await server.sessions["qoderWork-q-post"])?.status == .executing)
        #expect((await server.sessions["qoderWork-q-post"])?.currentToolCall != nil)

        let msg3 = makeHookMessage(type: "PostToolUse", sessionId: "q-post")
        await server.handleQoderWorkStatusHook(
            message: msg3, sessionId: "qoderWork-q-post", clientPID: nil, respond: respond
        )
        let s = await server.sessions["qoderWork-q-post"]
        #expect(s?.status == .executing)
        #expect(s?.currentToolCall == nil)
    }

    @Test("QoderWork Stop transitions to idle, not completed")
    func qoderWorkStopToIdle() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg1 = makeHookMessage(type: "UserPromptSubmit", sessionId: "q-stop")
        await server.handleQoderWorkStatusHook(
            message: msg1, sessionId: "qoderWork-q-stop", clientPID: nil, respond: respond
        )
        #expect((await server.sessions["qoderWork-q-stop"])?.status == .executing)

        let msg2 = makeHookMessage(type: "Stop", sessionId: "q-stop")
        await server.handleQoderWorkStatusHook(
            message: msg2, sessionId: "qoderWork-q-stop", clientPID: nil, respond: respond
        )
        let s = await server.sessions["qoderWork-q-stop"]
        #expect(s?.status == .idle)
    }

    @Test("QoderWork background hooks don't cause status bouncing")
    func qoderWorkNoBouncing() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg1 = makeHookMessage(type: "UserPromptSubmit", sessionId: "q-bounce")
        await server.handleQoderWorkStatusHook(
            message: msg1, sessionId: "qoderWork-q-bounce", clientPID: nil, respond: respond
        )
        let msg2 = makeHookMessage(type: "Stop", sessionId: "q-bounce")
        await server.handleQoderWorkStatusHook(
            message: msg2, sessionId: "qoderWork-q-bounce", clientPID: nil, respond: respond
        )
        #expect((await server.sessions["qoderWork-q-bounce"])?.status == .idle)

        let msg3 = makeHookMessage(
            type: "PreToolUse", sessionId: "q-bounce", toolName: "mcp__heartbeat"
        )
        await server.handleQoderWorkStatusHook(
            message: msg3, sessionId: "qoderWork-q-bounce", clientPID: nil, respond: respond
        )
        #expect((await server.sessions["qoderWork-q-bounce"])?.status == .idle)

        let msg4 = makeHookMessage(type: "PostToolUse", sessionId: "q-bounce")
        await server.handleQoderWorkStatusHook(
            message: msg4, sessionId: "qoderWork-q-bounce", clientPID: nil, respond: respond
        )
        #expect((await server.sessions["qoderWork-q-bounce"])?.status == .idle)
    }

    @Test("QoderWork full turn lifecycle: executing → idle → executing → idle")
    func qoderWorkTurnLifecycle() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }
        let sid = "q-lifecycle"
        let id = "qoderWork-\(sid)"

        let prompt1 = makeHookMessage(type: "UserPromptSubmit", sessionId: sid, prompt: "Fix bug")
        await server.handleQoderWorkStatusHook(
            message: prompt1, sessionId: id, clientPID: nil, respond: respond
        )
        #expect((await server.sessions[id])?.status == .executing)

        let tool1 = makeHookMessage(type: "PreToolUse", sessionId: sid, toolName: "Read")
        await server.handleQoderWorkStatusHook(
            message: tool1, sessionId: id, clientPID: nil, respond: respond
        )
        #expect((await server.sessions[id])?.status == .executing)
        #expect((await server.sessions[id])?.currentToolCall != nil)

        let tool1Done = makeHookMessage(type: "PostToolUse", sessionId: sid)
        await server.handleQoderWorkStatusHook(
            message: tool1Done, sessionId: id, clientPID: nil, respond: respond
        )
        #expect((await server.sessions[id])?.status == .executing)

        let stop1 = makeHookMessage(type: "Stop", sessionId: sid)
        await server.handleQoderWorkStatusHook(
            message: stop1, sessionId: id, clientPID: nil, respond: respond
        )
        #expect((await server.sessions[id])?.status == .idle)

        let prompt2 = makeHookMessage(type: "UserPromptSubmit", sessionId: sid, prompt: "Add tests")
        await server.handleQoderWorkStatusHook(
            message: prompt2, sessionId: id, clientPID: nil, respond: respond
        )
        #expect((await server.sessions[id])?.status == .executing)

        let stop2 = makeHookMessage(type: "Stop", sessionId: sid)
        await server.handleQoderWorkStatusHook(
            message: stop2, sessionId: id, clientPID: nil, respond: respond
        )
        #expect((await server.sessions[id])?.status == .idle)
    }

    @Test("QoderWork process death requires retries before cleanup")
    func qoderWorkProcessDeathRetry() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg = makeHookMessage(type: "UserPromptSubmit", sessionId: "q-retry")
        await server.handleQoderWorkStatusHook(
            message: msg, sessionId: "qoderWork-q-retry", clientPID: nil, respond: respond
        )
        await server.setTerminalPid(99999, for: "qoderWork-q-retry")

        await server.cleanupQoderWorkDeadSessions()
        #expect(await server.sessions["qoderWork-q-retry"] != nil)

        await server.cleanupQoderWorkDeadSessions()
        #expect(await server.sessions["qoderWork-q-retry"] != nil)

        await server.cleanupQoderWorkDeadSessions()
        #expect(await server.sessions["qoderWork-q-retry"] == nil)
    }

    @Test("QoderWork process alive resets retry counter")
    func qoderWorkProcessAliveResetsRetry() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg = makeHookMessage(type: "UserPromptSubmit", sessionId: "q-alive")
        await server.handleQoderWorkStatusHook(
            message: msg, sessionId: "qoderWork-q-alive", clientPID: nil, respond: respond
        )

        await server.setTerminalPid(99999, for: "qoderWork-q-alive")
        await server.cleanupQoderWorkDeadSessions()
        await server.cleanupQoderWorkDeadSessions()
        #expect(await server.sessions["qoderWork-q-alive"] != nil)

        await server.setTerminalPid(ProcessInfo.processInfo.processIdentifier, for: "qoderWork-q-alive")
        await server.cleanupQoderWorkDeadSessions()

        await server.setTerminalPid(99999, for: "qoderWork-q-alive")
        await server.cleanupQoderWorkDeadSessions()
        await server.cleanupQoderWorkDeadSessions()
        #expect(await server.sessions["qoderWork-q-alive"] != nil)

        await server.cleanupQoderWorkDeadSessions()
        #expect(await server.sessions["qoderWork-q-alive"] == nil)
    }

    // MARK: - Dispatch Routing

    @Test("17. Dispatch routes by agent type correctly")
    func dispatchRoutesCorrectly() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg = makeHookMessage(type: "UserPromptSubmit", sessionId: "dispatch-test")

        await server.dispatchHook(
            message: msg, tag: "claude",
            clientPID: nil, clientID: UUID(), respond: respond
        )
        await server.dispatchHook(
            message: msg, tag: "codex",
            clientPID: nil, clientID: UUID(), respond: respond
        )
        await server.dispatchHook(
            message: msg, tag: "qoderwork",
            clientPID: nil, clientID: UUID(), respond: respond
        )

        let sessions = await server.sessions
        #expect(sessions["claudeCode-dispatch-test"] != nil)
        #expect(sessions["codex-dispatch-test"] != nil)
        #expect(sessions["qoderWork-dispatch-test"] != nil)
    }

    // MARK: - Session Removal

    @Test("18. removeSession cleans up all associated state")
    func removeSessionCleansUp() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg = makeHookMessage(type: "UserPromptSubmit")
        await server.handleClaudeStatusHook(message: msg, sessionId: "claudeCode-test-session-1", respond: respond)

        let sessions1 = await server.sessions
        #expect(sessions1["claudeCode-test-session-1"] != nil)

        await server.removeSession("claudeCode-test-session-1")

        let sessions2 = await server.sessions
        #expect(sessions2["claudeCode-test-session-1"] == nil)
    }

    // MARK: - Activity Recording

    @Test("19. Activity dates tracked per session")
    func activityDatesTracked() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg1 = makeHookMessage(type: "SessionStart", sessionId: "codex-act")
        await server.handleGenericStatusHook(
            message: msg1, sessionId: "codex-codex-act",
            agentType: .codex, displayName: "Codex", respond: respond
        )

        let activity = await server.lastActivityDates["codex-codex-act"]
        #expect(activity != nil)

        let timeDiff = Date().timeIntervalSince(activity!)
        #expect(timeDiff < 2.0)
    }

    // MARK: - Summarize Tool Input

    @Test("20. summarizeToolInput formats correctly")
    func summarizeToolInputFormats() async throws {
        let server = try makeBridgeServer()

        let bashResult = await server.summarizeToolInput(
            name: "Bash", input: ["command": AnyCodable("git status")]
        )
        #expect(bashResult == "Bash: git status")

        let editResult = await server.summarizeToolInput(
            name: "Edit", input: ["file_path": AnyCodable("/src/main.swift")]
        )
        #expect(editResult == "Edit: /src/main.swift")

        let agentResult = await server.summarizeToolInput(name: "Agent", input: [:])
        #expect(agentResult == "Agent")
    }

    @Test("21. Long bash command is truncated")
    func longBashTruncated() async throws {
        let server = try makeBridgeServer()
        let longCmd = String(repeating: "a", count: 100)
        let result = await server.summarizeToolInput(
            name: "Bash", input: ["command": AnyCodable(longCmd)]
        )
        #expect(result.count <= 86)
        #expect(result.hasSuffix("..."))
    }

    // MARK: - Generic Handler

    @Test("22. Generic handler creates session and applies event")
    func genericHandlerCreatesSession() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg = makeHookMessage(type: "UserPromptSubmit", sessionId: "gen-1")
        await server.handleGenericStatusHook(
            message: msg, sessionId: "codex-gen-1",
            agentType: .codex, displayName: "Codex", respond: respond
        )

        let session = await server.sessions["codex-gen-1"]
        #expect(session != nil)
        #expect(session?.status == .executing)
        #expect(session?.title == "Codex")
    }

    @Test("23. Generic handler returns empty for unknown hook type")
    func genericHandlerUnknownHook() async throws {
        let server = try makeBridgeServer()
        var captured: HookResponse?
        let respond: @Sendable (HookResponse) -> Void = { captured = $0 }

        let msg = makeHookMessage(type: "UnknownEvent", sessionId: "gen-2")
        await server.handleGenericStatusHook(
            message: msg, sessionId: "codex-gen-2",
            agentType: .codex, displayName: "Codex", respond: respond
        )

        #expect(captured == .empty)
        let session = await server.sessions["codex-gen-2"]
        #expect(session != nil)
        #expect(session?.status == .idle)
    }

    @Test("24. Dispatch routes unknown tag to empty response")
    func dispatchUnknownTag() async throws {
        let server = try makeBridgeServer()
        var captured: HookResponse?
        let respond: @Sendable (HookResponse) -> Void = { captured = $0 }

        let msg = makeHookMessage(type: "SessionStart", sessionId: "x1")
        await server.dispatchHook(
            message: msg, tag: "nonexistent",
            clientPID: nil, clientID: UUID(), respond: respond
        )

        #expect(captured == .empty)
    }

    @Test("Alive process bypasses 48h visibility filter")
    func aliveProcessBypassesVisibilityFilter() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg = makeHookMessage(type: "SessionStart", sessionId: "old-1")
        await server.handleClaudeStatusHook(
            message: msg, sessionId: "claudeCode-old-1", respond: respond
        )

        let threeDaysAgo = Date().addingTimeInterval(-259200)
        await server.setLastActivityDate(threeDaysAgo, for: "claudeCode-old-1")
        await server.setTerminalPid(ProcessInfo.processInfo.processIdentifier, for: "claudeCode-old-1")

        let visible = await server.discoverAllSessions()
        #expect(visible.contains { $0.id == "claudeCode-old-1" })
    }

    // MARK: - Agent Process Death Detection

    @Test("Dead agent process transitions executing session to idle")
    func deadAgentProcessTransitionsToIdle() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg = makeHookMessage(type: "UserPromptSubmit", sessionId: "dead-1")
        await server.handleCodexStatusHook(
            message: msg, sessionId: "codex-dead-1", clientPID: nil, respond: respond
        )
        #expect((await server.sessions["codex-dead-1"])?.status == .executing)

        await server.setAgentProcessPID(99999, for: "codex-dead-1")

        await server.cleanupStaleActiveSessions()

        let session = await server.sessions["codex-dead-1"]
        #expect(session?.status == .idle)
    }

    @Test("Alive agent process keeps session executing")
    func aliveAgentProcessKeepsExecuting() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg = makeHookMessage(type: "UserPromptSubmit", sessionId: "alive-1")
        await server.handleCodexStatusHook(
            message: msg, sessionId: "codex-alive-1", clientPID: nil, respond: respond
        )
        #expect((await server.sessions["codex-alive-1"])?.status == .executing)

        await server.setAgentProcessPID(ProcessInfo.processInfo.processIdentifier, for: "codex-alive-1")

        await server.cleanupStaleActiveSessions()

        let session = await server.sessions["codex-alive-1"]
        #expect(session?.status == .executing)
    }

    @Test("No agent PID tracked — session not affected by cleanup")
    func noAgentPIDNotAffected() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg = makeHookMessage(type: "UserPromptSubmit", sessionId: "no-pid")
        await server.handleCodexStatusHook(
            message: msg, sessionId: "codex-no-pid", clientPID: nil, respond: respond
        )
        #expect((await server.sessions["codex-no-pid"])?.status == .executing)

        await server.cleanupStaleActiveSessions()

        let session = await server.sessions["codex-no-pid"]
        #expect(session?.status == .executing)
    }

    @Test("Idle session not affected even with dead agent PID")
    func idleSessionNotAffectedByDeadPID() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg = makeHookMessage(type: "SessionStart", sessionId: "idle-dead")
        await server.handleCodexStatusHook(
            message: msg, sessionId: "codex-idle-dead", clientPID: nil, respond: respond
        )
        #expect((await server.sessions["codex-idle-dead"])?.status == .idle)

        await server.setAgentProcessPID(99999, for: "codex-idle-dead")

        await server.cleanupStaleActiveSessions()

        let session = await server.sessions["codex-idle-dead"]
        #expect(session?.status == .idle)
    }

    @Test("Dead agent process cleans up tracked PID")
    func deadAgentProcessCleansPID() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg = makeHookMessage(type: "UserPromptSubmit", sessionId: "clean-pid")
        await server.handleCodexStatusHook(
            message: msg, sessionId: "codex-clean-pid", clientPID: nil, respond: respond
        )

        await server.setAgentProcessPID(99999, for: "codex-clean-pid")
        await server.cleanupStaleActiveSessions()

        let pid = await server.agentProcessPIDs["codex-clean-pid"]
        #expect(pid == nil)
    }

    @Test("Dead process still filtered by 48h rule")
    func deadProcessFilteredByTimeout() async throws {
        let server = try makeBridgeServer()
        let respond = { @Sendable (_: HookResponse) in }

        let msg = makeHookMessage(type: "SessionStart", sessionId: "old-2")
        await server.handleClaudeStatusHook(
            message: msg, sessionId: "claudeCode-old-2", respond: respond
        )

        let threeDaysAgo = Date().addingTimeInterval(-259200)
        await server.setLastActivityDate(threeDaysAgo, for: "claudeCode-old-2")
        await server.setTerminalPid(99999, for: "claudeCode-old-2")

        let visible = await server.discoverAllSessions()
        #expect(!visible.contains { $0.id == "claudeCode-old-2" })
    }
}

extension BridgeServer {
    func setLastActivityDate(_ date: Date, for sessionId: String) {
        lastActivityDates[sessionId] = date
    }

    func setTerminalPid(_ pid: Int32, for sessionId: String) {
        sessions[sessionId]?.terminalInfo = TerminalInfo(appName: "cli", pid: pid, windowId: nil)
    }

    func setAgentProcessPID(_ pid: pid_t, for sessionId: String) {
        agentProcessPIDs[sessionId] = pid
    }
}
