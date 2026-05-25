import SwiftUI

struct ChoicePanelView: View {
    let details: ChoiceDetails
    let agentType: AgentType
    let onSelect: (String) -> Void

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
                    ChoiceOptionRowView(
                        option: option,
                        index: index,
                        onSelect: { onSelect(option.id) }
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(agentLabel) asks: \(details.question)")
    }

    private var agentLabel: String {
        AgentColorRegistry.shared.label(for: agentType)
    }

    private var agentColor: Color {
        AgentColorRegistry.shared.color(for: agentType)
    }
}
