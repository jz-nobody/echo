import SwiftUI

struct TaskSectionView: View {
    let todos: [TodoItem]

    private var completedCount: Int { todos.filter { $0.status == .completed }.count }
    private var inProgressCount: Int { todos.filter { $0.status == .inProgress }.count }
    private var pendingCount: Int { todos.filter { $0.status == .pending }.count }

    private var visibleTodos: [TodoItem] {
        let nonCompleted = todos.filter { $0.status != .completed }
        let completed = todos.filter { $0.status == .completed }
        let visibleCompleted = completed.suffix(2)
        return nonCompleted + visibleCompleted
    }

    private var hiddenCompletedCount: Int {
        max(0, completedCount - 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summaryText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.textSecondary)

            ForEach(Array(visibleTodos.enumerated()), id: \.offset) { _, todo in
                todoRow(todo)
            }

            if hiddenCompletedCount > 0 {
                Text("  ... +\(hiddenCompletedCount) 已完成")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.textSecondary.opacity(0.6))
            }
        }
        .padding(.top, 4)
    }

    private var summaryText: String {
        var parts: [String] = []
        if completedCount > 0 { parts.append("\(completedCount) 已完成") }
        if inProgressCount > 0 { parts.append("\(inProgressCount) 进行中") }
        if pendingCount > 0 { parts.append("\(pendingCount) 待处理") }
        return "任务 (\(parts.joined(separator: ", ")))"
    }

    private func todoRow(_ todo: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 6) {
            todoIcon(todo.status)
                .frame(width: 12, alignment: .center)

            Text(todo.status == .inProgress ? todo.activeForm : todo.content)
                .font(.system(size: 11))
                .foregroundStyle(todo.status == .completed
                    ? DesignTokens.textSecondary.opacity(0.5)
                    : DesignTokens.textSecondary)
                .strikethrough(todo.status == .completed)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func todoIcon(_ status: TodoStatus) -> some View {
        switch status {
        case .inProgress:
            Circle()
                .fill(DesignTokens.todoInProgress)
                .frame(width: 6, height: 6)
                .padding(.top, 4)
        case .pending:
            RoundedRectangle(cornerRadius: 2)
                .stroke(DesignTokens.todoPending, lineWidth: 1)
                .frame(width: 10, height: 10)
                .padding(.top, 2)
        case .completed:
            Image(systemName: "checkmark.square.fill")
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.todoCompleted)
                .padding(.top, 1)
        }
    }
}
