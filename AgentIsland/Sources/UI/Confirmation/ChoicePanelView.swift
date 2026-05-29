import SwiftUI

struct ChoicePanelView: View {
    let details: ChoiceDetails
    let agentType: AgentType
    let onSelect: (String) -> Void
    let onMultiSelect: ([String]) -> Void
    let onFreeText: (String) -> Void

    @State private var selectedIds: Set<String> = []
    @State private var isOtherActive = false
    @State private var isOtherHovered = false
    @State private var otherText = ""
    @State private var appeared = false
    @FocusState private var otherFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            VStack(alignment: .leading, spacing: 10) {
                questionContainer
                optionsContainer

                if isOtherActive {
                    otherInputField
                }

                if details.multiSelect && !selectedIds.isEmpty {
                    submitButton
                }
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 12, y: 4)
        .onAppear { appeared = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(agentLabel) asks: \(details.question)")
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(agentLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: NSColor(hex: "#1C1C1E")))

            Text(details.multiSelect ? "多选问题" : "单选问题")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(agentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(agentColor.opacity(0.12))
                .clipShape(Capsule())

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DesignTokens.choiceHeaderBackground)
    }

    // MARK: - Question

    private var questionContainer: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("Q")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(agentColor)
                .frame(width: 18, height: 18)
                .background(agentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text(details.question)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
                .truncationMode(.tail)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.contentContainerRadius, style: .continuous))
    }

    // MARK: - Options Container

    private var optionsContainer: some View {
        ScrollView {
            VStack(spacing: 0) {
                let capped = Array(details.options.prefix(9))
                ForEach(Array(capped.enumerated()), id: \.element.id) { index, option in
                    optionRow(for: option, index: index)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 6)
                        .animation(
                            AnimationConstants.optionStagger
                                .delay(Double(index) * AnimationConstants.optionStaggerDelay),
                            value: appeared
                        )

                    if index < capped.count - 1 {
                        optionDivider
                    }
                }

                optionDivider

                otherRow
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 6)
                    .animation(
                        AnimationConstants.optionStagger
                            .delay(Double(min(details.options.count, 9)) * AnimationConstants.optionStaggerDelay),
                        value: appeared
                    )
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 280)
    }

    @ViewBuilder
    private func optionRow(for option: ChoiceOption, index: Int) -> some View {
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

    private var optionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 0.5)
            .padding(.horizontal, 12)
    }

    // MARK: - Other Row

    private var otherRow: some View {
        Button {
            if details.multiSelect { selectedIds.removeAll() }
            isOtherActive.toggle()
            if isOtherActive { otherFieldFocused = true }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOtherActive ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isOtherActive ? agentColor : DesignTokens.textSecondary)
                    .contentTransition(.symbolEffect(.replace))

                Text("其他")
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.textPrimary)

                Spacer()
            }
            .frame(minHeight: DesignTokens.optionRowMinHeight)
            .padding(.horizontal, 8)
            .background(
                (isOtherActive || isOtherHovered)
                    ? Color.white.opacity(0.08)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AnimationConstants.hoverHighlight) {
                isOtherHovered = hovering
            }
        }
    }

    // MARK: - Other Input Field

    private var otherInputField: some View {
        HStack(spacing: 8) {
            TextField("请输入", text: $otherText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.textPrimary)
                .focused($otherFieldFocused)
                .onSubmit { submitOther() }

            Button("提交") { submitOther() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.confirmationAllowText)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(otherText.isEmpty
                    ? DesignTokens.textSecondary.opacity(0.3)
                    : DesignTokens.choiceHeaderBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .disabled(otherText.isEmpty)
        }
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.contentContainerRadius, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Submit Button

    private var submitButton: some View {
        Button {
            onMultiSelect(Array(selectedIds))
        } label: {
            Text("确认 (\(selectedIds.count))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.confirmationAllowText)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(DesignTokens.choiceHeaderBackground)
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

// MARK: - Multi-Select Option Row

private struct MultiSelectOptionRow: View {
    let option: ChoiceOption
    let index: Int
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? DesignTokens.statusCompleted : Color.white.opacity(0.2))
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)

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
            .background(
                (isSelected || isHovered)
                    ? Color.white.opacity(0.08)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AnimationConstants.hoverHighlight) {
                isHovered = hovering
            }
        }
    }
}
