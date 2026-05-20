import Foundation
@testable import AgentIsland

@MainActor
final class MockWindowActivator: WindowActivating {
    private(set) var jumpedSessions: [AgentSession] = []
    var jumpResult: Bool = true

    func jumpToSession(_ session: AgentSession) -> Bool {
        jumpedSessions.append(session)
        return jumpResult
    }
}
