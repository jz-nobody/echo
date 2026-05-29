import SwiftUI

struct ChoiceOptionRowView: View {
    let option: ChoiceOption
    let index: Int
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                indexBadge

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)

                    if let desc = option.description {
                        Text(desc)
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .lineLimit(3)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()
            }
            .frame(minHeight: DesignTokens.optionRowMinHeight)
            .padding(.horizontal, 8)
            .background(isHovered ? Color.white.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(optionAccessibilityLabel)
        .onHover { hovering in
            withAnimation(AnimationConstants.hoverHighlight) {
                isHovered = hovering
            }
        }
    }

    private var optionAccessibilityLabel: String {
        var label = "Option \(index + 1): \(option.label)"
        if let desc = option.description { label += ", \(desc)" }
        label += ", keyboard shortcut Command \(index + 1)"
        return label
    }

    private var indexBadge: some View {
        let letter = index < 26 ? String(UnicodeScalar(65 + index)!) : "\(index + 1)"
        return Text(letter)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(DesignTokens.textSecondary)
            .frame(width: 20, height: 20)
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}
