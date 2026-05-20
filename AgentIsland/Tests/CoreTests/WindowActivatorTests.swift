import Testing
import Foundation
@testable import AgentIsland

@Suite("WindowActivator Tests")
struct WindowActivatorTests {

    private func makeSession(
        id: String = "s1",
        terminalInfo: TerminalInfo? = TerminalInfo(appName: "cli", pid: 99999, windowId: nil)
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
        let store = SettingsStore(defaults: UserDefaults(suiteName: "test-activator-\(UUID())")!)
        store.disableClickToJump = disableClickToJump
        return store
    }

    @Test("jumpToSession returns false when disabled")
    @MainActor
    func jumpDisabled() {
        let store = makeStore(disableClickToJump: true)
        let activator = WindowActivator(settingsStore: store)
        let session = makeSession()

        let result = activator.jumpToSession(session)
        #expect(!result)
    }

    @Test("jumpToSession returns false when no terminalInfo")
    @MainActor
    func noTerminalInfo() {
        let store = makeStore()
        let activator = WindowActivator(settingsStore: store)
        let session = makeSession(terminalInfo: nil)

        let result = activator.jumpToSession(session)
        #expect(!result)
    }

    @Test("jumpToSession returns false when pid is nil")
    @MainActor
    func nilPID() {
        let store = makeStore()
        let activator = WindowActivator(settingsStore: store)
        let session = makeSession(
            terminalInfo: TerminalInfo(appName: "cli", pid: nil, windowId: nil)
        )

        let result = activator.jumpToSession(session)
        #expect(!result)
    }

    @Test("jumpToSession returns false when agent process not found")
    @MainActor
    func processNotFound() {
        let store = makeStore()
        let activator = WindowActivator(settingsStore: store)
        let session = makeSession(
            terminalInfo: TerminalInfo(appName: "cli", pid: 1, windowId: nil)
        )

        let result = activator.jumpToSession(session)
        #expect(!result)
    }

    @Test("mock records jumped sessions")
    @MainActor
    func mockRecords() {
        let mock = MockWindowActivator()
        let session = makeSession()

        let result = mock.jumpToSession(session)

        #expect(result)
        #expect(mock.jumpedSessions.count == 1)
        #expect(mock.jumpedSessions[0].id == "s1")
    }

    @Test("mock returns configured result")
    @MainActor
    func mockConfigurableResult() {
        let mock = MockWindowActivator()
        mock.jumpResult = false

        let result = mock.jumpToSession(makeSession())

        #expect(!result)
        #expect(mock.jumpedSessions.count == 1)
    }
}
