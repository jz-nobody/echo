import SwiftUI

struct SubagentSectionView: View {
    let subagents: [SubagentInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("↳ Subagents (\(subagents.count))")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.textSecondary)

            ForEach(subagents) { agent in
                agentRow(agent)
            }
        }
        .padding(.top, 4)
    }

    private func agentRow(_ agent: SubagentInfo) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(agent.isComplete ? DesignTokens.todoCompleted : DesignTokens.todoInProgress)
                .frame(width: 6, height: 6)

            Text("\(agent.agentType) (\(agent.description))")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.textSecondary)
                .lineLimit(1)

            if agent.isComplete {
                Text("完成")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignTokens.todoCompleted)
            }
        }
    }
}
