import SwiftUI

struct ChoiceOptionRowView: View {
    let option: ChoiceOption
    let index: Int
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                shortcutBadge

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: 14))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .lineLimit(1)

                    if let desc = option.description {
                        Text(desc)
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .frame(height: DesignTokens.optionCardHeight)
            .padding(.horizontal, 12)
            .background(DesignTokens.choiceOptionBackground)
            .brightness(isHovered ? 0.1 : 0)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.optionCardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AnimationConstants.hoverHighlight) {
                isHovered = hovering
            }
        }
    }

    private var shortcutBadge: some View {
        Text("⌘\(index + 1)")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(DesignTokens.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(DesignTokens.shortcutBadgeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
