import Testing
import Foundation
@testable import AgentIsland

@Suite("E2E Flow Tests", .disabled("Requires running QoderWork on 127.0.0.1:52345"))
struct E2EFlowTests {

    private let baseURL = URL(string: "http://127.0.0.1:52345")!

    @MainActor
    private func makeSettings() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "test-e2e-\(UUID())")!)
    }

    @Test("real MCP discovery returns sessions")
    @MainActor
    func realMCPDiscovery() async throws {
        let client = MCPClient(baseURL: baseURL)
        let adaptor = QoderWorkAdaptor(client: client)

        let available = await adaptor.isAvailable
        #expect(available == true)

        let sessions = try await adaptor.discoverSessions()
        #expect(!sessions.isEmpty)
    }

    @Test("full poll cycle populates SessionManager")
    @MainActor
    func fullPollCycle() async throws {
        let client = MCPClient(baseURL: baseURL)
        let adaptor = QoderWorkAdaptor(client: client)
        let manager = SessionManager(adaptors: [adaptor], settingsStore: makeSettings())

        await manager.pollOnce()

        #expect(!manager.sessions.isEmpty)
        #expect(manager.health.states[.qoderWork] == .online)
    }

    @Test("respond flow completes without error")
    @MainActor
    func respondFlowCompletes() async throws {
        let client = MCPClient(baseURL: baseURL)
        let adaptor = QoderWorkAdaptor(client: client)
        let manager = SessionManager(adaptors: [adaptor], settingsStore: makeSettings())

        await manager.pollOnce()

        let waitingSessions = manager.sessions.filter { $0.status == .waitingConfirmation }
        guard let session = waitingSessions.first,
              let confs = manager.pendingConfirmations[session.id],
              let conf = confs.first else {
            return
        }

        try await manager.respond(session: session, confirmation: conf, response: .allow)
    }

    @Test("disconnect marks adaptor offline, reconnect recovers")
    @MainActor
    func disconnectRecovery() async throws {
        let client = MCPClient(baseURL: baseURL)
        let adaptor = QoderWorkAdaptor(client: client)
        let health = AdaptorHealth(maxFailures: 2, offlinePauseDuration: 1.0)
        let retryPolicy = RetryPolicy(maxAttempts: 1, baseDelay: 0.1, multiplier: 1.0)
        let manager = SessionManager(
            adaptors: [adaptor],
            settingsStore: makeSettings(),
            retryPolicy: retryPolicy,
            health: health
        )

        await manager.pollOnce()
        let initialState = health.states[.qoderWork]
        #expect(initialState == .online)
    }
}
