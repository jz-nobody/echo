import SwiftUI

struct ChoicePanelView: View {
    let details: ChoiceDetails
    let agentType: AgentType
    let onSelect: (String) -> Void
    let onMultiSelect: ([String]) -> Void
    let onFreeText: (String) -> Void

    @State private var selectedIds: Set<String> = []
    @State private var isOtherActive = false
    @State private var otherText = ""
    @FocusState private var otherFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(agentLabel) asks")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(agentColor)

            Text(details.question)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(Array(details.options.prefix(9).enumerated()), id: \.element.id) { index, option in
                    if details.multiSelect {
                        MultiSelectOptionRow(
                            option: option,
                            index: index,
                            isSelected: selectedIds.contains(option.id),
                            onToggle: {
                                if selectedIds.contains(option.id) {
                                    selectedIds.remove(option.id)
                                } else {
                                    selectedIds.insert(option.id)
                                    isOtherActive = false
                                }
                            }
                        )
                    } else {
                        ChoiceOptionRowView(
                            option: option,
                            index: index,
                            onSelect: { onSelect(option.id) }
                        )
                    }
                }

                otherRow
            }

            if details.multiSelect && !selectedIds.isEmpty {
                submitButton
            }

            if isOtherActive {
                otherInputField
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(agentLabel) asks: \(details.question)")
    }

    private var otherRow: some View {
        Button {
            if details.multiSelect {
                selectedIds.removeAll()
            }
            isOtherActive.toggle()
            if isOtherActive {
                otherFieldFocused = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOtherActive ? "pencil.circle.fill" : "pencil.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isOtherActive ? agentColor : DesignTokens.textSecondary)

                Text("Other")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.textPrimary)

                Spacer()
            }
            .frame(height: DesignTokens.optionCardHeight)
            .padding(.horizontal, 12)
            .background(isOtherActive ? agentColor.opacity(0.15) : DesignTokens.choiceOptionBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.optionCardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var otherInputField: some View {
        HStack(spacing: 8) {
            TextField("Type your answer...", text: $otherText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(DesignTokens.textPrimary)
                .focused($otherFieldFocused)
                .onSubmit { submitOther() }

            Button("Submit") { submitOther() }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.confirmationAllowText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(otherText.isEmpty ? DesignTokens.textSecondary : DesignTokens.confirmationAllowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .disabled(otherText.isEmpty)
        }
        .padding(10)
        .background(DesignTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var submitButton: some View {
        Button {
            onMultiSelect(Array(selectedIds))
        } label: {
            Text("Confirm (\(selectedIds.count))")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DesignTokens.confirmationAllowText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(DesignTokens.confirmationAllowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func submitOther() {
        guard !otherText.isEmpty else { return }
        onFreeText(otherText)
    }

    private var agentLabel: String {
        AgentColorRegistry.shared.label(for: agentType)
    }

    private var agentColor: Color {
        AgentColorRegistry.shared.color(for: agentType)
    }
}

private struct MultiSelectOptionRow: View {
    let option: ChoiceOption
    let index: Int
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? DesignTokens.statusCompleted : DesignTokens.textSecondary)

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
            .background(isSelected ? DesignTokens.statusCompleted.opacity(0.1) : DesignTokens.choiceOptionBackground)
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
}
