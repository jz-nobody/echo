import SwiftUI

struct PermissionPanelView: View {
    let details: PermissionDetails
    let onAllow: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permission Request")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)

            Text(details.operation)
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.textSecondary)
                .lineLimit(2)

            if !details.diff.isEmpty {
                diffArea
            }

            statsLine

            buttonRow
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Permission request: \(details.operation)")
    }

    private var diffArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(details.diff.enumerated()), id: \.offset) { _, line in
                    DiffLineView(line: line)
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 160)
        .background(DesignTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel("Code diff, \(details.additions) additions, \(details.deletions) deletions")
    }

    private var statsLine: some View {
        HStack(spacing: 12) {
            if details.additions > 0 {
                Text("+\(details.additions)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.diffAdded)
            }
            if details.deletions > 0 {
                Text("-\(details.deletions)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.diffRemoved)
            }
        }
    }

    private var buttonRow: some View {
        HStack(spacing: 12) {
            Button(action: onDeny) {
                HStack(spacing: 6) {
                    Text("Deny")
                    Text("⌘N")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: DesignTokens.confirmationButtonHeight)
                .background(DesignTokens.confirmationDenyBackground)
                .foregroundStyle(DesignTokens.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.confirmationButtonRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Deny, keyboard shortcut Command N")

            Button(action: onAllow) {
                HStack(spacing: 6) {
                    Text("Allow")
                    Text("⌘Y")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.confirmationAllowText.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .frame(height: DesignTokens.confirmationButtonHeight)
                .background(DesignTokens.confirmationAllowBackground)
                .foregroundStyle(DesignTokens.confirmationAllowText)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.confirmationButtonRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Allow, keyboard shortcut Command Y")
        }
    }
}
