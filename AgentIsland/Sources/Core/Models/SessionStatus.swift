import SwiftUI

enum SessionStatus: Sendable, Equatable {
    case idle
    case thinking
    case executing
    case completed
    case waitingConfirmation
    case error(String)

    var displayText: String {
        switch self {
        case .idle: "空闲中"
        case .thinking: "思考中"
        case .executing: "执行中"
        case .completed: "已完成"
        case .waitingConfirmation: "等待确认"
        case .error: "错误"
        }
    }

    var color: Color {
        switch self {
        case .idle: DesignTokens.statusIdle
        case .thinking: DesignTokens.statusThinking
        case .executing: DesignTokens.statusExecuting
        case .completed: DesignTokens.statusCompleted
        case .waitingConfirmation: DesignTokens.statusWaiting
        case .error: DesignTokens.statusError
        }
    }

    var priority: Int {
        switch self {
        case .waitingConfirmation: 4
        case .error: 3
        case .executing: 2
        case .thinking: 1
        case .completed: 0
        case .idle: -1
        }
    }

    static func highest(_ statuses: [SessionStatus]) -> SessionStatus {
        statuses.max(by: { $0.priority < $1.priority }) ?? .idle
    }
}
