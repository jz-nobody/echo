import SwiftUI

struct PermissionPanelView: View {
    let details: PermissionDetails
    let agentType: AgentType
    let onAllow: () -> Void
    let onAllowAlways: () -> Void
    let onAutoApprove: () -> Void
    let onDeny: () -> Void

    private var supportsAllowAlways: Bool {
        agentType != .codex
    }

    private var displayToolName: String {
        let parts = details.operation.split(separator: ":", maxSplits: 1)
        return String(parts.first ?? "Permission")
    }

    private var operationDetail: String {
        let parts = details.operation.split(separator: ":", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : details.operation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.statusWaiting)
                Text(displayToolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
            }

            Text(operationDetail)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(DesignTokens.textSecondary)
                .lineLimit(3)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignTokens.contentContainerBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.contentContainerRadius, style: .continuous))

            if !details.diff.isEmpty {
                diffArea
            }

            buttonRow
        }
        .padding(12)
        .background(DesignTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        .frame(maxHeight: 140)
        .background(DesignTokens.contentContainerBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.contentContainerRadius, style: .continuous))
        .accessibilityLabel("Code diff, \(details.additions) additions, \(details.deletions) deletions")
    }

    private var buttonRow: some View {
        HStack(spacing: 8) {
            Button(action: onDeny) {
                Text("拒绝")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(DesignTokens.confirmationDenyBackground)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("拒绝, ⌘N")

            Button(action: onAllow) {
                Text("允许一次")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(DesignTokens.confirmationAllowBackground)
                    .foregroundStyle(DesignTokens.confirmationAllowText)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("允许一次, ⌘Y")

            if supportsAllowAlways {
                Button(action: onAllowAlways) {
                    Text("始终允许")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color(nsColor: NSColor(hex: "#0A84FF")))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("始终允许, ⌘⇧Y")
            }

            Button(action: onAutoApprove) {
                Text("自动批准")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(DesignTokens.tagAutoApproveBackground)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("自动批准, ⌘⇧A")
        }
    }
}
