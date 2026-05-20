import Foundation

struct SubagentInfo: Sendable, Equatable, Identifiable {
    let id: String
    let description: String
    let agentType: String
    let isComplete: Bool
}
