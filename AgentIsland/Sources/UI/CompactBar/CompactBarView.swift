import SwiftUI

struct CompactBarView: View {
    let status: SessionStatus
    let sessionCount: Int
    let elapsedTime: String?
    var isOffline: Bool = false
    var confirmationTitle: String? = nil
    var confirmationCount: Int = 0
    var onClose: (() -> Void)? = nil
    var onCloseHover: ((Bool) -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                PetAnimationView(status: status, size: DesignTokens.petSizeCompact)
                    .frame(width: DesignTokens.petSizeCompact, height: DesignTokens.petSizeCompact)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                StatusAnimationView(status: status, size: DesignTokens.statusIndicatorSize)
                    .frame(width: DesignTokens.statusIndicatorSize, height: DesignTokens.statusIndicatorSize)
            }
            .offset(x: -10)

            if confirmationCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text("\(confirmationCount)")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(DesignTokens.statusWaiting)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(DesignTokens.statusWaiting.opacity(0.2))
                .clipShape(Capsule())
            }

            if let time = elapsedTime {
                Text(time)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DesignTokens.textSecondary)
            }

            Spacer(minLength: 4)

            HStack(spacing: 2) {
                if sessionCount > 0 {
                    Text("×\(sessionCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                }

                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "power")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignTokens.textPrimary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in onCloseHover?(hovering) }
                }
            }
            .offset(x: 6)
        }
        .padding(.horizontal, DesignTokens.compactBarPaddingH)
        .frame(height: DesignTokens.compactBarHeight)
        .background(DesignTokens.compactBarBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.compactBarCornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(compactBarAccessibilityLabel)
        .accessibilityHint("Hover to expand agent panel")
    }
    private var compactBarAccessibilityLabel: String {
        var parts: [String] = ["Agent Island"]
        parts.append(isOffline ? "Offline" : status.displayText)
        if confirmationCount > 0 {
            parts.append("\(confirmationCount) confirmation\(confirmationCount == 1 ? "" : "s")")
        }
        if sessionCount > 0 {
            parts.append("\(sessionCount) session\(sessionCount == 1 ? "" : "s")")
        }
        if let time = elapsedTime { parts.append(time) }
        return parts.joined(separator: ", ")
    }
}

#Preview("Running - 2 sessions") {
    CompactBarView(status: .executing, sessionCount: 2, elapsedTime: "3m")
        .padding()
        .background(Color.gray.opacity(0.3))
}

#Preview("Waiting Confirmation") {
    CompactBarView(
        status: .waitingConfirmation, sessionCount: 1, elapsedTime: "12m",
        confirmationTitle: "允许 Bash", confirmationCount: 1
    )
    .padding()
    .background(Color.gray.opacity(0.3))
}

#Preview("Compacting") {
    CompactBarView(status: .compacting, sessionCount: 1, elapsedTime: "5m")
        .padding()
        .background(Color.gray.opacity(0.3))
}

#Preview("Idle") {
    CompactBarView(status: .idle, sessionCount: 0, elapsedTime: nil)
        .padding()
        .background(Color.gray.opacity(0.3))
}
