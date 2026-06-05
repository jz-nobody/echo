import Foundation

enum SessionEvent: Sendable, Equatable {
    case sessionStart
    case userPromptSubmit
    case preToolUse(toolName: String?)
    case postToolUse
    case permissionRequest
    case permissionApproved
    case permissionDenied
    case preCompact
    case stop
    case stopFailure
    case subagentStart
    case subagentStop
    case processTerminated
    case turnCompleted
}

struct SessionState: Sendable, Equatable {
    private(set) var status: SessionStatus
    private(set) var isCompacting: Bool
    private(set) var lastEventDate: Date

    init(status: SessionStatus = .idle) {
        self.status = status
        self.isCompacting = false
        self.lastEventDate = Date()
    }

    mutating func apply(_ event: SessionEvent, at date: Date = Date()) {
        lastEventDate = date

        switch event {
        case .sessionStart:
            status = .idle
            isCompacting = false

        case .userPromptSubmit:
            guard !isActionable else { return }
            status = .executing
            isCompacting = false

        case .preToolUse(let toolName):
            guard !isActionable else { return }
            if isCompacting { isCompacting = false }
            status = Self.refineExecuting(toolName: toolName)

        case .postToolUse:
            guard !isActionable else { return }
            if isCompacting { isCompacting = false }
            status = .executing

        case .permissionRequest:
            status = .waitingConfirmation

        case .permissionApproved:
            status = .executing

        case .permissionDenied:
            status = .idle

        case .preCompact:
            guard !isActionable else { return }
            status = .compacting
            isCompacting = true

        case .stop, .stopFailure:
            status = .completed
            isCompacting = false

        case .subagentStart:
            guard !isActionable else { return }
            status = .executing

        case .subagentStop:
            break

        case .processTerminated:
            status = .idle
            isCompacting = false

        case .turnCompleted:
            status = .idle
            isCompacting = false
        }
    }

    // MARK: - Private

    private var isActionable: Bool {
        status == .waitingConfirmation
    }

    private static let readingTools: Set<String> = [
        "Read", "WebFetch", "WebSearch", "Grep", "Glob"
    ]
    private static let editingTools: Set<String> = [
        "Edit", "Write", "NotebookEdit"
    ]

    static func refineExecuting(toolName: String?) -> SessionStatus {
        guard let tool = toolName else { return .executing }
        if readingTools.contains(tool) { return .reading }
        if editingTools.contains(tool) { return .editing }
        return .executing
    }
}

extension SessionEvent {

    var indicatesPostConfirmationProgress: Bool {
        switch self {
        case .userPromptSubmit, .preToolUse, .postToolUse, .stop, .stopFailure, .turnCompleted: true
        default: false
        }
    }

    static func from(hookType: String, toolName: String?) -> SessionEvent? {
        switch hookType {
        case "SessionStart": .sessionStart
        case "UserPromptSubmit": .userPromptSubmit
        case "PreToolUse": .preToolUse(toolName: toolName)
        case "PostToolUse", "PostToolUseFailure": .postToolUse
        case "PreCompact": .preCompact
        case "Stop": .stop
        case "StopFailure": .stopFailure
        case "SubagentStart": .subagentStart
        case "SubagentStop": .subagentStop
        default: nil
        }
    }

}
