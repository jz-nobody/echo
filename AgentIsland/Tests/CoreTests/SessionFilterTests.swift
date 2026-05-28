import Testing
import Foundation
@testable import AgentIsland

@Suite("SessionFilter Tests")
struct SessionFilterTests {

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

    @MainActor
    private func makeStore() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "test-filter-\(UUID())")!)
    }

    @Test("built-in filter hides matching session")
    @MainActor
    func builtInFilterHides() {
        let store = makeStore()
        let sessions = [makeSession(title: "Memory Consolidation run")]
        let result = SessionFilter.apply(to: sessions, settings: store)
        #expect(result.isEmpty)
    }

    @Test("built-in filter disabled passes all")
    @MainActor
    func builtInDisabledPassesAll() {
        let store = makeStore()
        store.enableBuiltInFilters = false
        let sessions = [makeSession(title: "Memory Consolidation run")]
        let result = SessionFilter.apply(to: sessions, settings: store)
        #expect(result.count == 1)
    }

    @Test("custom keyword hides matching session")
    @MainActor
    func customKeywordHides() {
        let store = makeStore()
        store.filterKeywords = ["deploy"]
        let sessions = [makeSession(title: "Deploy to staging")]
        let result = SessionFilter.apply(to: sessions, settings: store)
        #expect(result.isEmpty)
    }

    @Test("custom keyword case insensitive")
    @MainActor
    func customKeywordCaseInsensitive() {
        let store = makeStore()
        store.filterKeywords = ["DEPLOY"]
        let sessions = [makeSession(title: "deploy to staging")]
        let result = SessionFilter.apply(to: sessions, settings: store)
        #expect(result.isEmpty)
    }

    @Test("empty keyword does not filter")
    @MainActor
    func emptyKeywordNoFilter() {
        let store = makeStore()
        store.filterKeywords = ["", "  "]
        let sessions = [makeSession(title: "Normal task")]
        let result = SessionFilter.apply(to: sessions, settings: store)
        #expect(result.count == 1)
    }

    @Test("non-matching session passes")
    @MainActor
    func nonMatchingPasses() {
        let store = makeStore()
        store.filterKeywords = ["deploy"]
        let sessions = [makeSession(title: "Fix authentication bug")]
        let result = SessionFilter.apply(to: sessions, settings: store)
        #expect(result.count == 1)
    }

    @Test("multiple filters combine")
    @MainActor
    func multipleFiltersCombine() {
        let store = makeStore()
        store.filterKeywords = ["deploy", "lint"]
        let sessions = [
            makeSession(id: "s1", title: "Deploy to staging"),
            makeSession(id: "s2", title: "Run lint checks"),
            makeSession(id: "s3", title: "Fix auth bug"),
        ]
        let result = SessionFilter.apply(to: sessions, settings: store)
        #expect(result.count == 1)
        #expect(result[0].id == "s3")
    }

    @Test("filter preserves non-matching sessions")
    @MainActor
    func filterPreservesNonMatching() {
        let store = makeStore()
        let sessions = [
            makeSession(id: "s1", title: "Memory Consolidation"),
            makeSession(id: "s2", title: "Normal work"),
            makeSession(id: "s3", title: "claude-mem task"),
        ]
        let result = SessionFilter.apply(to: sessions, settings: store)
        #expect(result.count == 1)
        #expect(result[0].id == "s2")
    }

    // MARK: - Codex Background Session Filters

    @Test("built-in filter hides Memory Writer sessions")
    @MainActor
    func filtersMemoryWriter() {
        let store = makeStore()
        let sessions = [makeSession(title: "Memory Writer consolidating")]
        let result = SessionFilter.apply(to: sessions, settings: store)
        #expect(result.isEmpty)
    }

    @Test("built-in filter hides Guardian-AutoReview sessions")
    @MainActor
    func filtersGuardianAutoReview() {
        let store = makeStore()
        let sessions = [makeSession(title: "Guardian-AutoReview scanning")]
        let result = SessionFilter.apply(to: sessions, settings: store)
        #expect(result.isEmpty)
    }

    @Test("built-in filter hides Chronicle Summary sessions")
    @MainActor
    func filtersChronicleSummary() {
        let store = makeStore()
        let sessions = [makeSession(title: "Chronicle Summary generating")]
        let result = SessionFilter.apply(to: sessions, settings: store)
        #expect(result.isEmpty)
    }

    @Test("Codex background patterns mixed with normal sessions")
    @MainActor
    func codexBackgroundPatternsMixed() {
        let store = makeStore()
        let sessions = [
            makeSession(id: "s1", title: "Memory Writer task"),
            makeSession(id: "s2", title: "Fix login bug"),
            makeSession(id: "s3", title: "Guardian-AutoReview check"),
            makeSession(id: "s4", title: "Chronicle Summary update"),
            makeSession(id: "s5", title: "Implement auth feature"),
        ]
        let result = SessionFilter.apply(to: sessions, settings: store)
        #expect(result.count == 2)
        #expect(result.map(\.id).contains("s2"))
        #expect(result.map(\.id).contains("s5"))
    }
}
