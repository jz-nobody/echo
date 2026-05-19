import SwiftUI

struct CompactBarView: View {
    let status: SessionStatus
    let sessionCount: Int
    let elapsedTime: String?
    var isOffline: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            StatusDotView(status: status)

            Text(isOffline ? "Offline" : status.displayText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOffline ? DesignTokens.statusError : DesignTokens.textPrimary)

            Spacer(minLength: 4)

            if sessionCount > 0 {
                Text("\(sessionCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(DesignTokens.cardBackground)
                    .clipShape(Capsule())
            }

            if let time = elapsedTime {
                Text(time)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
        .padding(.horizontal, DesignTokens.compactBarPaddingH)
        .frame(height: DesignTokens.compactBarHeight)
        .background(DesignTokens.compactBarBackground)
        .clipShape(
            RoundedRectangle(
                cornerRadius: DesignTokens.compactBarCornerRadius,
                style: .continuous
            )
        )
    }
}

#Preview("Running - 2 sessions") {
    CompactBarView(status: .executing, sessionCount: 2, elapsedTime: "3m")
        .padding()
        .background(Color.gray.opacity(0.3))
}

#Preview("Waiting Confirmation") {
    CompactBarView(status: .waitingConfirmation, sessionCount: 1, elapsedTime: "12m")
        .padding()
        .background(Color.gray.opacity(0.3))
}

#Preview("Idle") {
    CompactBarView(status: .idle, sessionCount: 0, elapsedTime: nil)
        .padding()
        .background(Color.gray.opacity(0.3))
}
