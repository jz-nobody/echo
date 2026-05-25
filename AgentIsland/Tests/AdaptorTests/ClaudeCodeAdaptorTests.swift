import Testing
import Foundation
@testable import AgentIsland

@Suite("ClaudeCodeAdaptor Tests", .serialized)
struct ClaudeCodeAdaptorTests {

    private func makeAdaptor(confirmationTimeout: TimeInterval = 60) throws -> ClaudeCodeAdaptor {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-island-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let socketPath = tmpDir.appendingPathComponent("test.sock").path
        return try ClaudeCodeAdaptor(
            sessionsDirectoryPath: tmpDir.path,
            socketPath: socketPath,
            confirmationTimeout: confirmationTimeout
        )
    }

    @Test("agentType is claudeCode")
    func agentType() throws {
        let adaptor = try makeAdaptor()
        #expect(adaptor.agentType == .claudeCode)
    }

    @Test("isAvailable returns true when sessions directory exists")
    func isAvailableTrue() async throws {
        let adaptor = try makeAdaptor()
        let available = await adaptor.isAvailable
        #expect(available == true)
    }

    @Test("discoverSessions returns empty when no sessions")
    func discoverSessionsEmpty() async throws {
        let adaptor = try makeAdaptor()
        let sessions = try await adaptor.discoverSessions()
        #expect(sessions.isEmpty)
    }

    @Test("updateSessions populates activeSessions")
    func updateSessionsPopulates() async throws {
        let adaptor = try makeAdaptor()
        let files = [
            ClaudeSessionFile(
                pid: 1234,
                sessionId: "sess-1",
                cwd: "/Users/dev/project-a",
                startedAt: 1779212717359,
                version: "2.1.0",
                kind: "interactive",
                entrypoint: "cli",
                status: nil,
                updatedAt: nil
            )
        ]
        await adaptor.updateSessions(files)
        let sessions = try await adaptor.discoverSessions()
        #expect(sessions.count == 1)
        #expect(sessions.first?.title == "project-a")
        #expect(sessions.first?.agentType == .claudeCode)
    }

    @Test("handlePermissionRequest creates PendingConfirmation")
    func handlePermissionRequest() async throws {
        let adaptor = try makeAdaptor()

        let files = [
            ClaudeSessionFile(
                pid: 5678,
                sessionId: "sess-2",
                cwd: "/Users/dev/my-app",
                startedAt: 1779212717359,
                version: "2.1.0",
                kind: "interactive",
                entrypoint: "claude-vscode",
                status: nil,
                updatedAt: nil
            )
        ]
        await adaptor.updateSessions(files)

        let msg = HookMessage(
            type: "PermissionRequest",
            sessionId: "sess-2",
            toolName: "Bash",
            toolInput: ["command": AnyCodable("rm -rf /tmp/test")],
            permissionLevel: nil
        )

        var receivedResponse: HookResponse?
        await adaptor.handlePermissionRequest(msg) { response in
            receivedResponse = response
        }

        let confs = try await adaptor.getPendingConfirmations(
            session: AgentSession(
                id: "sess-2", agentType: .claudeCode, title: "my-app",
                status: .executing, startTime: Date(), lastUpdate: Date()
            )
        )
        #expect(confs.count == 1)
        #expect(confs.first?.title.contains("Bash") == true)
        #expect(confs.first?.type == .permission)
        #expect(receivedResponse == nil)
    }

    @Test("respond calls callback with correct decision")
    func respondCallsCallback() async throws {
        let adaptor = try makeAdaptor()

        let files = [
            ClaudeSessionFile(
                pid: 9999,
                sessionId: "sess-3",
                cwd: "/Users/dev/test",
                startedAt: 1779212717359,
                version: "2.1.0",
                kind: "interactive",
                entrypoint: "cli",
                status: nil,
                updatedAt: nil
            )
        ]
        await adaptor.updateSessions(files)

        let msg = HookMessage(
            type: "PermissionRequest",
            sessionId: "sess-3",
            toolName: "Write",
            toolInput: ["file_path": AnyCodable("/tmp/test.txt")],
            permissionLevel: nil
        )

        var receivedResponse: HookResponse?
        await adaptor.handlePermissionRequest(msg) { response in
            receivedResponse = response
        }

        let session = AgentSession(
            id: "sess-3", agentType: .claudeCode, title: "test",
            status: .waitingConfirmation, startTime: Date(), lastUpdate: Date()
        )
        let confs = try await adaptor.getPendingConfirmations(session: session)
        let conf = try #require(confs.first)

        try await adaptor.respond(session: session, confirmation: conf, response: .allow)

        #expect(receivedResponse?.decision == "allow")

        let remaining = try await adaptor.getPendingConfirmations(session: session)
        #expect(remaining.isEmpty)
    }

    @Test("respond with deny sends deny decision")
    func respondDeny() async throws {
        let adaptor = try makeAdaptor()
        await adaptor.updateSessions([
            ClaudeSessionFile(
                pid: 1111, sessionId: "sess-4", cwd: "/tmp/x",
                startedAt: 1779212717359, version: "2.1.0",
                kind: "interactive", entrypoint: "cli", status: nil, updatedAt: nil
            )
        ])

        var receivedResponse: HookResponse?
        await adaptor.handlePermissionRequest(
            HookMessage(
                type: "PermissionRequest", sessionId: "sess-4",
                toolName: "Bash", toolInput: ["command": AnyCodable("danger")],
                permissionLevel: nil
            )
        ) { response in receivedResponse = response }

        let session = AgentSession(
            id: "sess-4", agentType: .claudeCode, title: "x",
            status: .waitingConfirmation, startTime: Date(), lastUpdate: Date()
        )
        let conf = try #require(try await adaptor.getPendingConfirmations(session: session).first)
        try await adaptor.respond(session: session, confirmation: conf, response: .deny)
        #expect(receivedResponse?.decision == "deny")
    }

    @Test("getStatus returns waitingConfirmation when pending")
    func getStatusWaitingConfirmation() async throws {
        let adaptor = try makeAdaptor()
        await adaptor.updateSessions([
            ClaudeSessionFile(
                pid: 2222, sessionId: "sess-5", cwd: "/tmp/y",
                startedAt: 1779212717359, version: "2.1.0",
                kind: "interactive", entrypoint: "cli", status: nil, updatedAt: nil
            )
        ])

        await adaptor.handlePermissionRequest(
            HookMessage(
                type: "PermissionRequest", sessionId: "sess-5",
                toolName: "Edit", toolInput: [:], permissionLevel: nil
            )
        ) { _ in }

        let session = AgentSession(
            id: "sess-5", agentType: .claudeCode, title: "y",
            status: .executing, startTime: Date(), lastUpdate: Date()
        )
        let status = try await adaptor.getStatus(session: session)
        #expect(status == .waitingConfirmation)
    }

    @Test("stale confirmations are cleaned up during discoverSessions")
    func staleConfirmationCleanup() async throws {
        let adaptor = try makeAdaptor(confirmationTimeout: 0)

        await adaptor.updateSessions([
            ClaudeSessionFile(
                pid: 4444, sessionId: "sess-stale", cwd: "/tmp/stale",
                startedAt: 1779212717359, version: "2.1.0",
                kind: "interactive", entrypoint: "cli", status: nil, updatedAt: nil
            )
        ])

        var callbackResponse: HookResponse?
        await adaptor.handlePermissionRequest(
            HookMessage(
                type: "PermissionRequest", sessionId: "sess-stale",
                toolName: "Bash", toolInput: ["command": AnyCodable("echo test")],
                permissionLevel: nil
            )
        ) { response in
            callbackResponse = response
        }

        let session = AgentSession(
            id: "sess-stale", agentType: .claudeCode, title: "stale",
            status: .executing, startTime: Date(), lastUpdate: Date()
        )
        let statusBefore = try await adaptor.getStatus(session: session)
        #expect(statusBefore == .waitingConfirmation)

        let _ = try await adaptor.discoverSessions()

        let statusAfter = try await adaptor.getStatus(session: session)
        #expect(statusAfter != .waitingConfirmation)
        #expect(callbackResponse?.decision == "ask")
    }

    // MARK: - Status Hook Tests

    @Test("handleStatusHook PreToolUse with Read sets reading status")
    func statusHookPreToolUseRead() async throws {
        let adaptor = try makeAdaptor()
        await adaptor.updateSessions([
            ClaudeSessionFile(
                pid: 7001, sessionId: "sess-hook-1", cwd: "/tmp/hook",
                startedAt: 1779212717359, version: "2.1.0",
                kind: "interactive", entrypoint: "cli", status: nil, updatedAt: nil
            )
        ])

        var receivedResponse: HookResponse?
        await adaptor.handleStatusHook(
            HookMessage(
                type: "PreToolUse", sessionId: "sess-hook-1",
                toolName: "Read", toolInput: nil, permissionLevel: nil
            )
        ) { response in receivedResponse = response }

        let session = AgentSession(
            id: "sess-hook-1", agentType: .claudeCode, title: "hook",
            status: .idle, startTime: Date(), lastUpdate: Date()
        )
        let status = try await adaptor.getStatus(session: session)
        #expect(status == .reading)
        #expect(receivedResponse?.decision == nil)
    }

    @Test("handleStatusHook PreToolUse with Bash sets executing status")
    func statusHookPreToolUseBash() async throws {
        let adaptor = try makeAdaptor()
        await adaptor.updateSessions([
            ClaudeSessionFile(
                pid: 7002, sessionId: "sess-hook-2", cwd: "/tmp/hook",
                startedAt: 1779212717359, version: "2.1.0",
                kind: "interactive", entrypoint: "cli", status: nil, updatedAt: nil
            )
        ])

        await adaptor.handleStatusHook(
            HookMessage(
                type: "PreToolUse", sessionId: "sess-hook-2",
                toolName: "Bash", toolInput: nil, permissionLevel: nil
            )
        ) { _ in }

        let session = AgentSession(
            id: "sess-hook-2", agentType: .claudeCode, title: "hook",
            status: .idle, startTime: Date(), lastUpdate: Date()
        )
        let status = try await adaptor.getStatus(session: session)
        #expect(status == .executing)
    }

    @Test("handleStatusHook PreToolUse with Edit sets editing status")
    func statusHookPreToolUseEdit() async throws {
        let adaptor = try makeAdaptor()
        await adaptor.updateSessions([
            ClaudeSessionFile(
                pid: 7003, sessionId: "sess-hook-3", cwd: "/tmp/hook",
                startedAt: 1779212717359, version: "2.1.0",
                kind: "interactive", entrypoint: "cli", status: nil, updatedAt: nil
            )
        ])

        await adaptor.handleStatusHook(
            HookMessage(
                type: "PreToolUse", sessionId: "sess-hook-3",
                toolName: "Edit", toolInput: nil, permissionLevel: nil
            )
        ) { _ in }

        let session = AgentSession(
            id: "sess-hook-3", agentType: .claudeCode, title: "hook",
            status: .idle, startTime: Date(), lastUpdate: Date()
        )
        let status = try await adaptor.getStatus(session: session)
        #expect(status == .editing)
    }

    @Test("handleStatusHook PostToolUse sets executing status")
    func statusHookPostToolUse() async throws {
        let adaptor = try makeAdaptor()
        await adaptor.updateSessions([
            ClaudeSessionFile(
                pid: 7004, sessionId: "sess-hook-4", cwd: "/tmp/hook",
                startedAt: 1779212717359, version: "2.1.0",
                kind: "interactive", entrypoint: "cli", status: nil, updatedAt: nil
            )
        ])

        await adaptor.handleStatusHook(
            HookMessage(
                type: "PostToolUse", sessionId: "sess-hook-4",
                toolName: "Bash", toolInput: nil, permissionLevel: nil
            )
        ) { _ in }

        let session = AgentSession(
            id: "sess-hook-4", agentType: .claudeCode, title: "hook",
            status: .idle, startTime: Date(), lastUpdate: Date()
        )
        let status = try await adaptor.getStatus(session: session)
        #expect(status == .executing)
    }

    @Test("handleStatusHook PreCompact sets compacting status")
    func statusHookPreCompact() async throws {
        let adaptor = try makeAdaptor()
        await adaptor.updateSessions([
            ClaudeSessionFile(
                pid: 7005, sessionId: "sess-hook-5", cwd: "/tmp/hook",
                startedAt: 1779212717359, version: "2.1.0",
                kind: "interactive", entrypoint: "cli", status: nil, updatedAt: nil
            )
        ])

        await adaptor.handleStatusHook(
            HookMessage(
                type: "PreCompact", sessionId: "sess-hook-5",
                toolName: nil, toolInput: nil, permissionLevel: nil
            )
        ) { _ in }

        let session = AgentSession(
            id: "sess-hook-5", agentType: .claudeCode, title: "hook",
            status: .idle, startTime: Date(), lastUpdate: Date()
        )
        let status = try await adaptor.getStatus(session: session)
        #expect(status == .compacting)
    }

    @Test("handleStatusHook Stop sets idle status")
    func statusHookStop() async throws {
        let adaptor = try makeAdaptor()
        await adaptor.updateSessions([
            ClaudeSessionFile(
                pid: 7006, sessionId: "sess-hook-6", cwd: "/tmp/hook",
                startedAt: 1779212717359, version: "2.1.0",
                kind: "interactive", entrypoint: "cli", status: nil, updatedAt: nil
            )
        ])

        await adaptor.handleStatusHook(
            HookMessage(
                type: "Stop", sessionId: "sess-hook-6",
                toolName: nil, toolInput: nil, permissionLevel: nil
            )
        ) { _ in }

        let session = AgentSession(
            id: "sess-hook-6", agentType: .claudeCode, title: "hook",
            status: .executing, startTime: Date(), lastUpdate: Date()
        )
        let status = try await adaptor.getStatus(session: session)
        #expect(status == .idle)
    }

    @Test("handleStatusHook UserPromptSubmit sets executing status")
    func statusHookUserPromptSubmit() async throws {
        let adaptor = try makeAdaptor()
        await adaptor.updateSessions([
            ClaudeSessionFile(
                pid: 7007, sessionId: "sess-hook-7", cwd: "/tmp/hook",
                startedAt: 1779212717359, version: "2.1.0",
                kind: "interactive", entrypoint: "cli", status: nil, updatedAt: nil
            )
        ])

        await adaptor.handleStatusHook(
            HookMessage(
                type: "UserPromptSubmit", sessionId: "sess-hook-7",
                toolName: nil, toolInput: nil, permissionLevel: nil
            )
        ) { _ in }

        let session = AgentSession(
            id: "sess-hook-7", agentType: .claudeCode, title: "hook",
            status: .idle, startTime: Date(), lastUpdate: Date()
        )
        let status = try await adaptor.getStatus(session: session)
        #expect(status == .executing)
    }

    @Test("handleStatusHook responds with empty (no decision)")
    func statusHookRespondsEmpty() async throws {
        let adaptor = try makeAdaptor()
        await adaptor.updateSessions([
            ClaudeSessionFile(
                pid: 7008, sessionId: "sess-hook-8", cwd: "/tmp/hook",
                startedAt: 1779212717359, version: "2.1.0",
                kind: "interactive", entrypoint: "cli", status: nil, updatedAt: nil
            )
        ])

        var receivedResponse: HookResponse?
        await adaptor.handleStatusHook(
            HookMessage(
                type: "PreToolUse", sessionId: "sess-hook-8",
                toolName: "Bash", toolInput: nil, permissionLevel: nil
            )
        ) { response in receivedResponse = response }

        #expect(receivedResponse == .empty)
        #expect(receivedResponse?.decision == nil)
        #expect(receivedResponse?.reason == nil)
    }

    // MARK: - Stale Session Tests

    @Test("updateSessions removes stale sessions and clears their pending requests")
    func updateSessionsRemovesStale() async throws {
        let adaptor = try makeAdaptor()

        await adaptor.updateSessions([
            ClaudeSessionFile(
                pid: 3333, sessionId: "sess-6", cwd: "/tmp/z",
                startedAt: 1779212717359, version: "2.1.0",
                kind: "interactive", entrypoint: "cli", status: nil, updatedAt: nil
            )
        ])

        var staleCallbackCalled = false
        await adaptor.handlePermissionRequest(
            HookMessage(
                type: "PermissionRequest", sessionId: "sess-6",
                toolName: "Bash", toolInput: [:], permissionLevel: nil
            )
        ) { response in
            staleCallbackCalled = true
        }

        await adaptor.updateSessions([])

        let sessions = try await adaptor.discoverSessions()
        #expect(sessions.isEmpty)
        #expect(staleCallbackCalled == true)
    }
}
