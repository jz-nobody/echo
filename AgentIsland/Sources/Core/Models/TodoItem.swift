import Foundation

struct TodoItem: Sendable, Equatable {
    let content: String
    let status: TodoStatus
    let activeForm: String
}

enum TodoStatus: String, Sendable, Equatable {
    case pending
    case inProgress = "in_progress"
    case completed
}
