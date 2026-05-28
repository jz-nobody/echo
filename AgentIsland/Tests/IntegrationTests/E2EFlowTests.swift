import Testing
import Foundation
@testable import AgentIsland

@Suite("E2E Flow Tests", .disabled("Requires running hook bridge"))
struct E2EFlowTests {

    @MainActor
    private func makeSettings() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "test-e2e-\(UUID())")!)
    }

    @Test("BridgeServer starts and accepts connections")
    @MainActor
    func bridgeServerStarts() async throws {
        let server = try makeMockBridgeServer()
        await server.start()

        let sessions = await server.discoverAllSessions()
        #expect(sessions.isEmpty)

        await server.stop()
    }

    @Test("full poll cycle with BridgeServer")
    @MainActor
    func fullPollCycle() async throws {
        let server = try makeMockBridgeServer()
        await server.start()

        let manager = SessionManager(bridgeServer: server, settingsStore: makeSettings())
        await manager.pollOnce()

        #expect(manager.sessions.isEmpty)
        await server.stop()
    }
}
