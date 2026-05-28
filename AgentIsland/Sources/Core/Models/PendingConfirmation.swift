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
}

struct ChoiceOption: Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    let description: String?
}
