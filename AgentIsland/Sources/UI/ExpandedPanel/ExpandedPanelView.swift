import SwiftUI

struct ExpandedPanelView: View {
    let sessions: [AgentSession]
    let confirmationQueue: ConfirmationQueue
    var onSessionTap: ((AgentSession) -> Void)? = nil
    let onRespond: (QueuedConfirmation, ConfirmationResponse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !confirmationQueue.isEmpty {
                ConfirmationPanelView(queue: confirmationQueue, onRespond: onRespond)
            } else {
                sessionListContent
            }

            Spacer()
        }
        .frame(maxWidth: DesignTokens.panelMaxWidth, minHeight: 120)
        .background(DesignTokens.panelBackground)
        .clipShape(
            RoundedRectangle(cornerRadius: DesignTokens.panelCornerRadius, style: .continuous)
        )
        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 4)
    }

    private var sessionListContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Sessions")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)

            if sessions.isEmpty {
                Text("No active tasks")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(DesignTokens.textSecondary)
            } else {
                ForEach(sessions) { session in
                    SessionRowView(session: session, onTap: {
                        onSessionTap?(session)
                    })
                }
            }
        }
        .padding(16)
    }
}
