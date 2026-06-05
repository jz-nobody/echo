import Foundation

struct PendingConfirmation: Identifiable, Sendable, Equatable {
    let id: String
    let type: ConfirmationType
    let title: String
    let details: ConfirmationDetails
    let timestamp: Date
}

enum ConfirmationType: Sendable, Equatable {
    case permission
    case choice
}

enum ConfirmationDetails: Sendable, Equatable {
    case permission(PermissionDetails)
    case choice(ChoiceDetails)
}

struct PermissionDetails: Sendable, Equatable {
    let toolName: String
    let operation: String
    let diff: [DiffLine]
    let additions: Int
    let deletions: Int
}

struct DiffLine: Sendable, Equatable {
    let lineNumber: Int
    let content: String
    let type: DiffLineType
}

enum DiffLineType: Sendable, Equatable {
    case added
    case removed
    case context
}

struct ChoiceDetails: Sendable, Equatable {
    let question: String
    let header: String?
    let options: [ChoiceOption]
    let multiSelect: Bool
    var questionIndex: Int?
    var totalQuestions: Int?
}

struct ChoiceOption: Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    let description: String?
}

struct QuestionGroup {
    let confirmationIds: [String]
    let sessionId: String
    let clientID: UUID
    let respond: @Sendable (HookResponse) -> Void
    var answers: [String: String]
    let originalInput: [String: AnyCodable]
    let totalCount: Int
}
