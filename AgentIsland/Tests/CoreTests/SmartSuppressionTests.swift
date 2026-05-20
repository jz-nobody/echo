import Testing
import Foundation
@testable import AgentIsland

@Suite("Smart Suppression Tests")
struct SmartSuppressionTests {

    private func makeSession(
        id: String = "s1",
        agentType: AgentType = .claudeCode,
        status: SessionStatus = .waitingConfirmation,
        terminalInfo: TerminalInfo? = TerminalInfo(appName: "cli", pid: 12345, windowId: nil)
    ) -> AgentSession {
        AgentSession(
            id: id,
            agentType: agentType,
            title: "Task",
            status: status,
            startTime: Date(),
            lastUpdate: Date(),
            terminalInfo: terminalInfo,
            currentToolCall: nil
        )
    }

    private func makeConfirmation(id: String = "c1") -> PendingConfirmation {
        PendingConfirmation(
            id: id,
            type: .permission,
            title: "Edit file",
            details: .permission(PermissionDetails(
                operation: "edit", diff: [], additions: 1, deletions: 0
            )),
            timestamp: Date()
        )
    }

    @MainActor
    private func makeStore(smartSuppression: Bool = true) -> SettingsStore {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "test-suppression-\(UUID())")!)
        store.smartSuppression = smartSuppression
        return store
    }

    // MARK: - SuppressionEvaluator Tests

    @Test("suppression disabled allows all auto-expand")
    @MainActor
    func suppressionDisabled() {
        let store = makeStore(smartSuppression: false)
        let monitor = MockFrontmostAppMonitor()
        monitor.frontmostAppPID = 999
        monitor.setMatching(sessionID: "s1")

        let session = makeSession(id: "s1")
        let confirmations: [String: [PendingConfirmation]] = ["s1": [makeConfirmation()]]

        let result = SuppressionEvaluator.shouldSuppress(
            settings: store, monitor: monitor,
            sessions: [session], confirmations: confirmations
        )
        #expect(!result)
    }

    @Test("no confirmations never suppresses")
    @MainActor
    func noConfirmations() {
        let store = makeStore()
        let monitor = MockFrontmostAppMonitor()
        monitor.frontmostAppPID = 999
        monitor.setMatching(sessionID: "s1")

        let session = makeSession(id: "s1")

        let result = SuppressionEvaluator.shouldSuppress(
            settings: store, monitor: monitor,
            sessions: [session], confirmations: [:]
        )
        #expect(!result)
    }

    @Test("session without terminalInfo not suppressed")
    @MainActor
    func noTerminalInfo() {
        let store = makeStore()
        let monitor = MockFrontmostAppMonitor()
        monitor.frontmostAppPID = 999

        let session = makeSession(id: "s1", agentType: .qoderWork, terminalInfo: nil)
        let confirmations: [String: [PendingConfirmation]] = ["s1": [makeConfirmation()]]

        let result = SuppressionEvaluator.shouldSuppress(
            settings: store, monitor: monitor,
            sessions: [session], confirmations: confirmations
        )
        #expect(!result)
    }

    @Test("terminal frontmost suppresses auto-expand")
    @MainActor
    func terminalFrontmostSuppresses() {
        let store = makeStore()
        let monitor = MockFrontmostAppMonitor()
        monitor.frontmostAppPID = 999
        monitor.setMatching(sessionID: "s1")

        let session = makeSession(id: "s1")
        let confirmations: [String: [PendingConfirmation]] = ["s1": [makeConfirmation()]]

        let result = SuppressionEvaluator.shouldSuppress(
            settings: store, monitor: monitor,
            sessions: [session], confirmations: confirmations
        )
        #expect(result)
    }

    @Test("non-terminal frontmost allows auto-expand")
    @MainActor
    func nonTerminalFrontmostAllows() {
        let store = makeStore()
        let monitor = MockFrontmostAppMonitor()
        monitor.frontmostAppPID = 999

        let session = makeSession(id: "s1")
        let confirmations: [String: [PendingConfirmation]] = ["s1": [makeConfirmation()]]

        let result = SuppressionEvaluator.shouldSuppress(
            settings: store, monitor: monitor,
            sessions: [session], confirmations: confirmations
        )
        #expect(!result)
    }

    @Test("multiple sessions, one matching suppresses")
    @MainActor
    func multipleSessionsOneMatching() {
        let store = makeStore()
        let monitor = MockFrontmostAppMonitor()
        monitor.frontmostAppPID = 999
        monitor.setMatching(sessionID: "s2")

        let sessions = [
            makeSession(id: "s1", agentType: .qoderWork, terminalInfo: nil),
            makeSession(id: "s2"),
        ]
        let confirmations: [String: [PendingConfirmation]] = [
            "s1": [makeConfirmation(id: "c1")],
            "s2": [makeConfirmation(id: "c2")],
        ]

        let result = SuppressionEvaluator.shouldSuppress(
            settings: store, monitor: monitor,
            sessions: sessions, confirmations: confirmations
        )
        #expect(result)
    }

    @Test("session with confirmation but no matching terminal does not suppress")
    @MainActor
    func confirmationNoMatchingTerminal() {
        let store = makeStore()
        let monitor = MockFrontmostAppMonitor()
        monitor.frontmostAppPID = 999
        monitor.setMatching(sessionID: "s2")

        let session = makeSession(id: "s1")
        let confirmations: [String: [PendingConfirmation]] = ["s1": [makeConfirmation()]]

        let result = SuppressionEvaluator.shouldSuppress(
            settings: store, monitor: monitor,
            sessions: [session], confirmations: confirmations
        )
        #expect(!result)
    }

    // MARK: - PanelState autoExpand still works independently

    @Test("hover expand works regardless of suppression")
    @MainActor
    func hoverExpandIndependent() {
        let store = makeStore()
        let state = PanelState(settingsStore: store)

        state.expand()
        #expect(state.isExpanded)
    }

    @Test("autoExpand still works when called directly")
    @MainActor
    func autoExpandDirectCall() {
        let store = makeStore()
        let state = PanelState(settingsStore: store)

        state.autoExpand()
        #expect(state.isExpanded)
        #expect(state.confirmationsActive)
    }
}
