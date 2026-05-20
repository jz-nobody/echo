import Foundation

@MainActor
protocol FrontmostAppProviding: AnyObject {
    var frontmostAppPID: pid_t? { get }
    func isTerminalOfSession(_ session: AgentSession) -> Bool
    func isFullscreenAppActive() -> Bool
}
