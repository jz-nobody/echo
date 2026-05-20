import Testing
import Foundation
@testable import AgentIsland

@Suite("FrontmostAppMonitor Tests")
struct FrontmostAppMonitorTests {

    private func makeSession(
        id: String = "s1",
        terminalInfo: TerminalInfo? = nil
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

    @Test("isTerminalOfSession returns false when no terminalInfo")
    @MainActor
    func noTerminalInfo() {
        let monitor = MockFrontmostAppMonitor()
        monitor.frontmostAppPID = 1234

        let session = makeSession(terminalInfo: nil)
        #expect(!monitor.isTerminalOfSession(session))
    }

    @Test("isTerminalOfSession returns false when pid is nil")
    @MainActor
    func nilPID() {
        let monitor = MockFrontmostAppMonitor()
        monitor.frontmostAppPID = 1234

        let session = makeSession(
            terminalInfo: TerminalInfo(appName: "cli", pid: nil, windowId: nil)
        )
        #expect(!monitor.isTerminalOfSession(session))
    }

    @Test("mock matching returns true for configured session")
    @MainActor
    func mockMatching() {
        let monitor = MockFrontmostAppMonitor()
        monitor.frontmostAppPID = 1234
        monitor.setMatching(sessionID: "s1")

        let session = makeSession(id: "s1")
        #expect(monitor.isTerminalOfSession(session))
    }

    @Test("mock matching returns false for unconfigured session")
    @MainActor
    func mockNotMatching() {
        let monitor = MockFrontmostAppMonitor()
        monitor.frontmostAppPID = 1234
        monitor.setMatching(sessionID: "s2")

        let session = makeSession(id: "s1")
        #expect(!monitor.isTerminalOfSession(session))
    }

    @Test("isFullscreenAppActive returns configured value")
    @MainActor
    func fullscreenConfig() {
        let monitor = MockFrontmostAppMonitor()

        #expect(!monitor.isFullscreenAppActive())

        monitor.fullscreenActive = true
        #expect(monitor.isFullscreenAppActive())
    }

    @Test("clearMatching removes all matching sessions")
    @MainActor
    func clearMatching() {
        let monitor = MockFrontmostAppMonitor()
        monitor.setMatching(sessionID: "s1")
        monitor.setMatching(sessionID: "s2")

        monitor.clearMatching()

        let session = makeSession(id: "s1")
        #expect(!monitor.isTerminalOfSession(session))
    }
}
