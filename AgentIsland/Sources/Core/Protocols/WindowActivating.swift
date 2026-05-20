import Foundation

@MainActor
protocol WindowActivating {
    func jumpToSession(_ session: AgentSession) -> Bool
}
