import Foundation
@testable import AgentIsland

@MainActor
final class MockFrontmostAppMonitor: FrontmostAppProviding {
    var frontmostAppPID: pid_t? = nil
    var fullscreenActive: Bool = false
    private var matchingSessionIDs: Set<String> = []

    func isFullscreenAppActive() -> Bool { fullscreenActive }

    func setMatching(sessionID: String) {
        matchingSessionIDs.insert(sessionID)
    }

    func clearMatching() {
        matchingSessionIDs.removeAll()
    }

    func isTerminalOfSession(_ session: AgentSession) -> Bool {
        matchingSessionIDs.contains(session.id)
    }
}
