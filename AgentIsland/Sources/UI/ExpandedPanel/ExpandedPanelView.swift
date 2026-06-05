import SwiftUI

struct ExpandedPanelView: View {
    let sessions: [AgentSession]
    let confirmationQueue: ConfirmationQueue
    var onSessionTap: ((AgentSession) -> Void)? = nil
    var onAddToFilter: ((String) -> Void)? = nil
    var onRevokeAutoApprove: ((AgentSession) -> Void)? = nil
    let onRespond: (QueuedConfirmation, ConfirmationResponse) -> Void

    @State private var scrollContentHeight: CGFloat = DesignTokens.panelMaxHeight

    private struct ScrollContentHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private let bottomFadeHeight: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sessions.isEmpty && confirmationQueue.isEmpty {
                emptyState
            } else {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if !activeSessions.isEmpty {
                                sectionHeader("运行中", count: activeSessions.count)
                                ForEach(activeSessions) { session in
                                    sessionRow(session)
                                }
                            }

                            if !idleSessions.isEmpty {
                                sectionHeader("就绪", count: idleSessions.count)
                                ForEach(idleSessions) { session in
                                    sessionRow(session)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, bottomFadeHeight + 12)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ScrollContentHeightKey.self, value: proxy.size.height)
                        })
                    }
                    .frame(height: min(scrollContentHeight, DesignTokens.panelMaxHeight))
                    .onPreferenceChange(ScrollContentHeightKey.self) { height in
                        scrollContentHeight = height
                    }

                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [
                                DesignTokens.panelBackground.opacity(0),
                                DesignTokens.panelBackground
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: bottomFadeHeight)

                        DesignTokens.panelBackground
                            .frame(height: 8)
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: DesignTokens.panelMaxWidth)
        .background(DesignTokens.panelBackground)
        .clipShape(
            RoundedRectangle(cornerRadius: DesignTokens.panelCornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.panelCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent panel")
    }

    @ViewBuilder
    private func inlineConfirmation(_ item: QueuedConfirmation, session: AgentSession) -> some View {
        switch item.confirmation.details {
        case .permission(let details):
            PermissionPanelView(
                details: details,
                agentType: session.agentType,
                onAllow: { onRespond(item, .allow) },
                onAllowAlways: { onRespond(item, .allowAlways(toolName: details.toolName)) },
                onAutoApprove: { onRespond(item, .autoApprove) },
                onDeny: { onRespond(item, .deny) }
            )
        case .choice(let details):
            ChoicePanelView(
                details: details,
                agentType: session.agentType,
                onSelect: { onRespond(item, .select(optionId: $0)) },
                onMultiSelect: { onRespond(item, .multiSelect(optionIds: $0)) },
                onFreeText: { onRespond(item, .freeText($0)) }
            )
        }
    }

    private var activeSessions: [AgentSession] {
        sessions
            .filter { $0.status != .idle }
            .sorted { $0.lastUpdate > $1.lastUpdate }
    }

    private var idleSessions: [AgentSession] {
        sessions
            .filter { $0.status == .idle }
            .sorted { $0.lastUpdate > $1.lastUpdate }
    }

    @ViewBuilder
    private func sessionRow(_ session: AgentSession) -> some View {
        SessionRowView(
            session: session,
            onTap: { onSessionTap?(session) },
            onAddToFilter: onAddToFilter,
            onRevokeAutoApprove: { onRevokeAutoApprove?(session) }
        )

        if let item = firstConfirmation(for: session) {
            inlineConfirmation(item, session: session)
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(DesignTokens.textPrimary.opacity(0.5))
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.textPrimary.opacity(0.35))
        }
        .padding(.leading, 4)
        .padding(.top, 8)
    }

    private func firstConfirmation(for session: AgentSession) -> QueuedConfirmation? {
        confirmationQueue.items.first { $0.session.id == session.id }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Sessions")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)
            Text("No active tasks")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(16)
    }
}
