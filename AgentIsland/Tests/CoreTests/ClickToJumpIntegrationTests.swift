import Testing
import Foundation
@testable import AgentIsland

@Suite("Click-to-Jump Integration Tests")
struct ClickToJumpIntegrationTests {

    private func makeSession(
        id: String = "s1",
        terminalInfo: TerminalInfo? = TerminalInfo(appName: "cli", pid: 12345, windowId: nil)
    ) -> AgentSession {
        AgentSession(
            id: id,
            agentType: .claudeCode,
            title: "Task",
            status: .executing,
            startTime: Date(),
            lastUpdate: Date(),
            terminalInfo: terminalInfo,
            currentToolCall: nil
        )
    }

    @MainActor
    private func makeStore(disableClickToJump: Bool = false) -> SettingsStore {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "test-jump-\(UUID())")!)
        store.disableClickToJump = disableClickToJump
        return store
    }

    @Test("successful jump collapses panel")
    @MainActor
    func successfulJumpCollapses() {
        let store = makeStore()
        let panelState = PanelState(settingsStore: store)
        let mock = MockWindowActivator()
        mock.jumpResult = true

        panelState.expand()
        #expect(panelState.isExpanded)

        let session = makeSession()
        if mock.jumpToSession(session) {
            panelState.collapse()
        }

        #expect(!panelState.isExpanded)
    }

    @Test("failed jump does not collapse panel")
    @MainActor
    func failedJumpKeepsPanel() {
        let store = makeStore()
        let panelState = PanelState(settingsStore: store)
        let mock = MockWindowActivator()
        mock.jumpResult = false

        panelState.expand()
        #expect(panelState.isExpanded)

        let session = makeSession()
        if mock.jumpToSession(session) {
            panelState.collapse()
        }

        #expect(panelState.isExpanded)
    }

    @Test("session without terminal info fails gracefully")
    @MainActor
    func noTerminalInfoGraceful() {
        let store = makeStore()
        let activator = WindowActivator(settingsStore: store)
        let panelState = PanelState(settingsStore: store)
        panelState.expand()

        let session = makeSession(terminalInfo: nil)
        if activator.jumpToSession(session) {
            panelState.collapse()
        }

        #expect(panelState.isExpanded)
    }

    @Test("disabled setting prevents jump")
    @MainActor
    func disabledPreventsJump() {
        let store = makeStore(disableClickToJump: true)
        let activator = WindowActivator(settingsStore: store)
        let panelState = PanelState(settingsStore: store)
        panelState.expand()

        let session = makeSession()
        if activator.jumpToSession(session) {
            panelState.collapse()
        }

        #expect(panelState.isExpanded)
    }
}
