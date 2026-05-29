import Testing
import Foundation
@testable import AgentIsland

@Suite("SessionManager Tests", .serialized)
struct SessionManagerTests {

    @MainActor
    private func makeSettings() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "test-sm-\(UUID())")!)
    }

    private func makeSession(
        id: String = "s1",
        status: SessionStatus = .executing,
        title: String = "Test Task"
    ) -> AgentSession {
        AgentSession(
            id: id,
            agentType: .qoderWork,
            title: title,
            status: status,
            startTime: Date(),
            lastUpdate: Date(),
            terminalInfo: nil,
            currentToolCall: nil
        )
    }

    private func makeConfirmation(id: String = "c1") -> PendingConfirmation {
        PendingConfirmation(
            id: id,
            type: .permission,
            title: "Edit file",
            details: .permission(PermissionDetails(toolName: "Edit", operation: "edit", diff: [], additions: 1, deletions: 0)),
            timestamp: Date()
        )
    }

    @Test("aggregateStatus returns highest priority status")
    @MainActor
    func aggregateStatusReturnsHighest() async throws {
        let server = try makeMockBridgeServer()
        await server.injectSession(makeSession(id: "s1", status: .executing, title: "Task A"))
        await server.injectSession(makeSession(id: "s2", status: .waitingConfirmation, title: "Task B"))

        let manager = SessionManager(bridgeServer: server, settingsStore: makeSettings())
        await manager.pollOnce()

        #expect(manager.aggregateStatus == .waitingConfirmation)
    }

    @Test("activeSessionCount excludes idle and completed")
    @MainActor
    func activeSessionCountExcludes() async throws {
        let server = try makeMockBridgeServer()
        await server.injectSession(makeSession(id: "s1", status: .idle, title: "Idle Task"))
        await server.injectSession(makeSession(id: "s2", status: .executing, title: "Running Task"))
        await server.injectSession(makeSession(id: "s3", status: .completed, title: "Done Task"))

        let manager = SessionManager(bridgeServer: server, settingsStore: makeSettings())
        await manager.pollOnce()

        #expect(manager.activeSessionCount == 1)
    }

    @Test("pollOnce updates sessions from bridge server")
    @MainActor
    func pollOnceUpdatesSessions() async throws {
        let server = try makeMockBridgeServer()
        await server.injectSession(makeSession(id: "task-1", status: .executing, title: "Build feature"))

        let manager = SessionManager(bridgeServer: server, settingsStore: makeSettings())
        #expect(manager.sessions.isEmpty)

        await manager.pollOnce()

        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].id == "task-1")
    }

    @Test("pollOnce fetches confirmations for waitingConfirmation sessions")
    @MainActor
    func pollOnceFetchesConfirmations() async throws {
        let server = try makeMockBridgeServer()
        let session = makeSession(id: "task-1", status: .waitingConfirmation)
        await server.injectSession(session)
        let conf = makeConfirmation(id: "conf-1")
        await server.injectConfirmation(conf, sessionId: "task-1")

        let manager = SessionManager(bridgeServer: server, settingsStore: makeSettings())
        await manager.pollOnce()

        #expect(manager.pendingConfirmations["task-1"]?.count == 1)
        #expect(manager.pendingConfirmations["task-1"]?[0].id == "conf-1")
    }

    @Test("respond delegates to bridge server")
    @MainActor
    func respondDelegatesToBridgeServer() async throws {
        let server = try makeMockBridgeServer()
        var captured: HookResponse?
        let respond: @Sendable (HookResponse) -> Void = { captured = $0 }

        let session = makeSession(id: "task-1")
        let conf = makeConfirmation(id: "c1")
        await server.injectSession(session)
        await server.injectConfirmation(conf, sessionId: "task-1", respond: respond)

        let manager = SessionManager(bridgeServer: server, settingsStore: makeSettings())
        try await manager.respond(session: session, confirmation: conf, response: .allow)

        #expect(captured?.decision == "allow")
    }

    @Test("startPolling sets isPolling flag")
    @MainActor
    func startPollingSetsFlag() throws {
        let server = try makeMockBridgeServer()
        let manager = SessionManager(bridgeServer: server, settingsStore: makeSettings())

        #expect(manager.isPolling == false)
        manager.startPolling()
        #expect(manager.isPolling == true)
        manager.stopPolling()
    }

    @Test("stopPolling clears isPolling flag")
    @MainActor
    func stopPollingClearsFlag() throws {
        let server = try makeMockBridgeServer()
        let manager = SessionManager(bridgeServer: server, settingsStore: makeSettings())

        manager.startPolling()
        manager.stopPolling()
        #expect(manager.isPolling == false)
    }
}
