import SwiftUI

struct ConfirmationPanelView: View {
    let queue: ConfirmationQueue
    let onRespond: (QueuedConfirmation, ConfirmationResponse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if queue.count > 1 {
                queueIndicator
            }

            if let item = queue.currentItem {
                confirmationContent(for: item)
                    .id(item.id)
                    .transition(.opacity)
            }
        }
        .animation(AnimationConstants.confirmationSwitch, value: queue.currentItem?.id)
        .padding(16)
        .frame(maxWidth: DesignTokens.panelMaxWidth, alignment: .leading)
    }

    @ViewBuilder
    private func confirmationContent(for item: QueuedConfirmation) -> some View {
        switch item.confirmation.details {
        case .permission(let details):
            PermissionPanelView(
                details: details,
                agentType: item.session.agentType,
                onAllow: { onRespond(item, .allow) },
                onAllowAlways: { onRespond(item, .allowAlways(toolName: details.toolName)) },
                onAutoApprove: { onRespond(item, .autoApprove) },
                onDeny: { onRespond(item, .deny) }
            )
        case .choice(let details):
            ChoicePanelView(
                details: details,
                agentType: item.session.agentType,
                onSelect: { optionId in onRespond(item, .select(optionId: optionId)) },
                onMultiSelect: { optionIds in onRespond(item, .multiSelect(optionIds: optionIds)) },
                onFreeText: { text in onRespond(item, .freeText(text)) }
            )
        }
    }

    private var queueIndicator: some View {
        Text("\(queue.currentIndex + 1) of \(queue.count)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DesignTokens.textSecondary)
            .accessibilityLabel("Confirmation \(queue.currentIndex + 1) of \(queue.count)")
    }
}
