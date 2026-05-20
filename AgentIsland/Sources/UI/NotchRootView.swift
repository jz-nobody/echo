import SwiftUI

struct NotchRootView: View {
    let panelState: PanelState
    var sessionManager: SessionManager
    let confirmationQueue: ConfirmationQueue
    let frontmostAppMonitor: FrontmostAppMonitor
    let windowActivator: any WindowActivating

    var body: some View {
        VStack(spacing: 0) {
            CompactBarView(
                status: sessionManager.aggregateStatus,
                sessionCount: sessionManager.activeSessionCount,
                elapsedTime: elapsedTimeText,
                isOffline: sessionManager.health.isAnyOffline
            )
            .frame(height: DesignTokens.compactBarHeight)

            if panelState.isExpanded {
                ExpandedPanelView(
                    sessions: sessionManager.sessions,
                    confirmationQueue: confirmationQueue,
                    onSessionTap: { session in
                        if windowActivator.jumpToSession(session) {
                            panelState.collapse()
                        }
                    },
                    onAddToFilter: { keyword in
                        guard !panelState.settingsStore.filterKeywords.contains(keyword) else { return }
                        panelState.settingsStore.filterKeywords.append(keyword)
                    },
                    onRespond: { item, response in
                        Task {
                            try? await sessionManager.respond(
                                session: item.session,
                                confirmation: item.confirmation,
                                response: response
                            )
                        }
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(
            panelState.isExpanded ? AnimationConstants.panelExpand : AnimationConstants.panelCollapse,
            value: panelState.isExpanded
        )
        .onChange(of: sessionManager.pendingConfirmations.count) {
            confirmationQueue.update(
                from: sessionManager.pendingConfirmations,
                sessions: sessionManager.sessions
            )
            if !confirmationQueue.isEmpty {
                if !shouldSuppressAutoExpand() {
                    panelState.autoExpand()
                }
            } else {
                panelState.confirmationsActive = false
            }
        }
        .onChange(of: frontmostAppMonitor.frontmostAppPID) {
            if !confirmationQueue.isEmpty && !panelState.isExpanded {
                if !shouldSuppressAutoExpand() {
                    panelState.autoExpand()
                }
            }
        }
    }

    private func shouldSuppressAutoExpand() -> Bool {
        SuppressionEvaluator.shouldSuppress(
            settings: panelState.settingsStore,
            monitor: frontmostAppMonitor,
            sessions: sessionManager.sessions,
            confirmations: sessionManager.pendingConfirmations
        )
    }

    private var elapsedTimeText: String? {
        let activeSessions = sessionManager.sessions.filter {
            $0.status != .idle && $0.status != .completed
        }
        guard let earliest = activeSessions.min(by: { $0.startTime < $1.startTime }) else {
            return nil
        }
        let elapsed = Int(Date().timeIntervalSince(earliest.startTime))
        if elapsed < 60 { return "\(elapsed)s" }
        if elapsed < 3600 { return "\(elapsed / 60)m" }
        return "\(elapsed / 3600)h\((elapsed % 3600) / 60)m"
    }
}
