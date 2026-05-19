import Foundation

enum AgentType: String, Sendable {
    case qoderWork
    case claudeCode
    case codex
}

struct AgentSession: Identifiable, Sendable, Equatable {
    let id: String
    let agentType: AgentType
    var title: String
    var status: SessionStatus
    var startTime: Date
    var lastUpdate: Date
    var terminalInfo: TerminalInfo?
    var currentToolCall: String?
}

struct TerminalInfo: Sendable, Equatable {
    let appName: String
    let pid: Int32?
    let windowId: String?
}
