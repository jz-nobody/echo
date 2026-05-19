import SwiftUI

struct SessionRowView: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 10) {
            StatusDotView(status: session.status)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)

                if let tool = session.currentToolCall {
                    Text(tool)
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            agentTag
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(DesignTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var agentTag: some View {
        Text(agentLabel)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tagColor)
            .clipShape(Capsule())
    }

    private var agentLabel: String {
        switch session.agentType {
        case .qoderWork: "Qoder"
        case .claudeCode: "Claude"
        case .codex: "Codex"
        }
    }

    private var tagColor: Color {
        switch session.agentType {
        case .qoderWork: DesignTokens.tagQoderWork
        case .claudeCode: DesignTokens.tagClaude
        case .codex: DesignTokens.tagCodex
        }
    }
}
