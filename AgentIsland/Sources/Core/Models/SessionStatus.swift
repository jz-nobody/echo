import SwiftUI

enum SessionStatus: Sendable, Equatable {
    case idle
    case thinking
    case reading
    case editing
    case executing
    case compacting
    case completed
    case waitingConfirmation
    case error(String)

    var displayText: String {
        switch self {
        case .idle: "就绪"
        case .thinking: "思考中"
        case .reading: "查询中"
        case .editing: "编辑中"
        case .executing: "运行中"
        case .compacting: "压缩中"
        case .completed: "已完成"
        case .waitingConfirmation: "询问中"
        case .error: "错误"
        }
    }

    var color: Color {
        switch self {
        case .idle: DesignTokens.statusIdle
        case .thinking: DesignTokens.statusThinking
        case .reading: DesignTokens.statusReading
        case .editing: DesignTokens.statusEditing
        case .executing: DesignTokens.statusExecuting
        case .compacting: DesignTokens.statusCompacting
        case .completed: DesignTokens.statusCompleted
        case .waitingConfirmation: DesignTokens.statusWaiting
        case .error: DesignTokens.statusError
        }
    }

    var priority: Int {
        switch self {
        case .waitingConfirmation: 5
        case .error: 4
        case .compacting: 3
        case .executing: 2
        case .editing: 2
        case .reading: 2
        case .thinking: 1
        case .completed: 0
        case .idle: -1
        }
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    var isActive: Bool {
        switch self {
        case .thinking, .reading, .editing, .executing: true
        default: false
        }
    }

    static func highest(_ statuses: [SessionStatus]) -> SessionStatus {
        statuses.max(by: { $0.priority < $1.priority }) ?? .idle
    }
}
