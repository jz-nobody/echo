import Testing
import Foundation
@testable import AgentIsland

@Suite("ClaudeCodeAdaptor Tests", .serialized)
struct ClaudeCodeAdaptorTests {

    private func makeAdaptor() throws -> ClaudeCodeAdaptor {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-island-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let socketPath = tmpDir.appendingPathComponent("test.sock").path
        return try ClaudeCodeAdaptor(
            sessionsDirectoryPath: tmpDir.path,
            socketPath: socketPath
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
