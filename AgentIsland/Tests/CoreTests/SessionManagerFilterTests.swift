import Testing
import Foundation
@testable import AgentIsland

@Suite("SessionManager Filter Tests", .serialized)
struct SessionManagerFilterTests {

    @MainActor
    private func makeSettings() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "test-smf-\(UUID())")!)
    }

    private func makeSession(
        id: String = "s1",
        title: String = "Test Task"
    ) -> AgentSession {
        AgentSession(
            id: id,
            agentType: .qoderWork,
            title: title,
            status: .executing,
            startTime: Date(),
            lastUpdate: Date(),
            terminalInfo: nil,
            currentToolCall: nil
        )
    }

    @Test("pollOnce filters matching sessions")
    @MainActor
    func pollOnceFiltersMatching() async {
        let mock = MockAgentAdaptor()
        await mock.setSessions([
            makeSession(id: "s1", title: "Memory Consolidation task"),
            makeSession(id: "s2", title: "Build feature"),
        ])
        await mock.setUseSessionOwnStatus(true)

        let settings = makeSettings()
        let manager = SessionManager(adaptors: [mock], settingsStore: settings)
        await manager.pollOnce()

        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].id == "s2")
    }

    @Test("pollOnce preserves non-matching sessions")
    @MainActor
    func pollOncePreservesNonMatching() async {
        let mock = MockAgentAdaptor()
        await mock.setSessions([
            makeSession(id: "s1", title: "Fix auth bug"),
            makeSession(id: "s2", title: "Write tests"),
        ])
        await mock.setUseSessionOwnStatus(true)

        let settings = makeSettings()
        let manager = SessionManager(adaptors: [mock], settingsStore: settings)
        await manager.pollOnce()

        #expect(manager.sessions.count == 2)
    }

    @Test("custom keyword filter applied during pollOnce")
    @MainActor
    func customKeywordFilterApplied() async {
        let mock = MockAgentAdaptor()
        await mock.setSessions([
            makeSession(id: "s1", title: "Deploy staging"),
            makeSession(id: "s2", title: "Build feature"),
        ])
        await mock.setUseSessionOwnStatus(true)

        let settings = makeSettings()
        settings.filterKeywords = ["deploy"]
        let manager = SessionManager(adaptors: [mock], settingsStore: settings)
        await manager.pollOnce()

        #expect(manager.sessions.count == 1)
        #expect(manager.sessions[0].id == "s2")
    }

    @Test("disabling built-in filters shows all sessions")
    @MainActor
    func disabledBuiltInShowsAll() async {
        let mock = MockAgentAdaptor()
        await mock.setSessions([
            makeSession(id: "s1", title: "Memory Consolidation task"),
            makeSession(id: "s2", title: "Normal work"),
        ])
        await mock.setUseSessionOwnStatus(true)

        let settings = makeSettings()
        settings.enableBuiltInFilters = false
        let manager = SessionManager(adaptors: [mock], settingsStore: settings)
        await manager.pollOnce()

        #expect(manager.sessions.count == 2)
    }

    @Test("filter changes take effect on next poll")
    @MainActor
    func filterChangesEffectOnNextPoll() async {
        let mock = MockAgentAdaptor()
        await mock.setSessions([
            makeSession(id: "s1", title: "Deploy staging"),
        ])
        await mock.setUseSessionOwnStatus(true)

        let settings = makeSettings()
        let manager = SessionManager(adaptors: [mock], settingsStore: settings)
        await manager.pollOnce()
        #expect(manager.sessions.count == 1)

        settings.filterKeywords = ["deploy"]
        await manager.pollOnce()
        #expect(manager.sessions.isEmpty)
    }
}
