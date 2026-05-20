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
            details: .permission(PermissionDetails(operation: "edit", diff: [], additions: 1, deletions: 0)),
            timestamp: Date()
        )
    }

    @Test("aggregateStatus returns highest priority status")
    @MainActor
    func aggregateStatusReturnsHighest() async {
        let mock = MockAgentAdaptor()
        await mock.setSessions([
            makeSession(id: "s1", status: .executing),
            makeSession(id: "s2", status: .waitingConfirmation)
        ])
        await mock.setUseSessionOwnStatus(true)

        let manager = SessionManager(adaptors: [mock], settingsStore: makeSettings())
        await manager.pollOnce()

        #expect(manager.aggregateStatus == .waitingConfirmation)
    }

    @Test("activeSessionCount excludes idle and completed")
    @MainActor
    func activeSessionCountExcludes() async {
        let mock = MockAgentAdaptor()
        await mock.setSessions([
            makeSession(id: "s1", status: .idle),
            makeSession(id: "s2", status: .executing),
            makeSession(id: "s3", status: .completed)
        ])
        await mock.setUseSessionOwnStatus(true)

        let manager = SessionManager(adaptors: [mock], settingsStore: makeSettings())
        await manager.pollOnce()

        #expect(manager.activeSessionCount == 1)
    }

    @Test("pollOnce updates sessions from adaptor")
    @MainActor
    func pollOnceUpdatesSessions() async {
        let mock = MockAgentAdaptor()
        let session = makeSession(id: "task-1", status: .executing, title: "Build feature")
        await mock.setSessions([session])
        await mock.setStatus(.thinking)

        let manager = SessionManager(adaptors: [mock], settingsStore: makeSettings())
        #expect(manager.sessions.isEmpty)

        await manager.pollOnce()

        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].id == "task-1")
        #expect(manager.sessions[0].status == .thinking)
    }

    @Test("pollOnce fetches confirmations for waitingConfirmation sessions")
    @MainActor
    func pollOnceFetchesConfirmations() async {
        let mock = MockAgentAdaptor()
        let session = makeSession(id: "task-1", status: .waitingConfirmation)
        await mock.setSessions([session])
        await mock.setStatus(.waitingConfirmation)
        let confirmation = makeConfirmation(id: "conf-1")
        await mock.setConfirmations([confirmation])

        let manager = SessionManager(adaptors: [mock], settingsStore: makeSettings())
        await manager.pollOnce()

        #expect(manager.pendingConfirmations["task-1"]?.count == 1)
        #expect(manager.pendingConfirmations["task-1"]?[0].id == "conf-1")
    }

    @Test("pollOnce skips unavailable adaptor")
    @MainActor
    func pollOnceSkipsUnavailable() async {
        let mock = MockAgentAdaptor()
        await mock.setAvailable(false)
        await mock.setSessions([makeSession()])

        let manager = SessionManager(adaptors: [mock], settingsStore: makeSettings())
        await manager.pollOnce()

        #expect(manager.sessions.isEmpty)
    }

    @Test("respond delegates to adaptor")
    @MainActor
    func respondDelegatesToAdaptor() async throws {
        let mock = MockAgentAdaptor()
        await mock.setAvailable(true)
        await mock.setSessions([])

        let manager = SessionManager(adaptors: [mock], settingsStore: makeSettings())
        let session = makeSession(id: "task-1")
        let confirmation = makeConfirmation()

        try await manager.respond(session: session, confirmation: confirmation, response: .allow)

        let called = await mock.wasRespondCalled()
        #expect(called == true)
    }

    @Test("startPolling sets isPolling flag")
    @MainActor
    func startPollingSetsFlag() {
        let mock = MockAgentAdaptor()
        let manager = SessionManager(adaptors: [mock], settingsStore: makeSettings())

        #expect(manager.isPolling == false)
        manager.startPolling()
        #expect(manager.isPolling == true)
        manager.stopPolling()
    }

    @Test("stopPolling clears isPolling flag")
    @MainActor
    func stopPollingClearsFlag() {
        let mock = MockAgentAdaptor()
        let manager = SessionManager(adaptors: [mock], settingsStore: makeSettings())

        manager.startPolling()
        manager.stopPolling()
        #expect(manager.isPolling == false)
    }
}
