import SwiftUI

struct NotchRootView: View {
    let panelState: PanelState
    var sessionManager: SessionManager
    let confirmationQueue: ConfirmationQueue
    let frontmostAppMonitor: FrontmostAppMonitor
    let windowActivator: any WindowActivating

    @State private var previousStatuses: [String: SessionStatus] = [:]
    @State private var userDismissedConfirmations = false
    @State private var previousConfirmationCount = 0

    private struct ExpandedHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            if panelState.isExpanded, panelState.showQuitConfirmation {
                QuitConfirmationView(
                    onCancel: {
                        panelState.showQuitConfirmation = false
                        panelState.collapse()
                    },
                    onConfirm: {
                        NSApplication.shared.terminate(nil)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignTokens.panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.panelCornerRadius))
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.3, anchor: .top).combined(with: .opacity)
                    )
                )
            } else if panelState.isExpanded {
                ExpandedPanelView(
                    sessions: sessionManager.sessions,
                    confirmationQueue: confirmationQueue,
                    onSessionTap: { session in
                        _ = windowActivator.jumpToSession(session)
                        panelState.collapse()
                    },
                    onAddToFilter: { keyword in
                        guard !panelState.settingsStore.filterKeywords.contains(keyword) else { return }
                        panelState.settingsStore.filterKeywords.append(keyword)
                    },
                    onRevokeAutoApprove: { session in
                        Task {
                            await sessionManager.revokeAutoApprove(session: session)
                        }
                    },
                    onRespond: { item, response in
                        confirmationQueue.removeItem(id: item.id)
                        Task {
                            do {
                                try await sessionManager.respond(
                                    session: item.session,
                                    confirmation: item.confirmation,
                                    response: response
                                )
                            } catch {
                                NSLog("[AgentIsland] Respond failed: \(error)")
                            }
                            confirmationQueue.update(
                                from: sessionManager.pendingConfirmations,
                                sessions: sessionManager.sessions
                            )
                        }
                    }
                )
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ExpandedHeightKey.self, value: proxy.size.height)
                })
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.3, anchor: .top).combined(with: .opacity)
                    )
                )
            }

        }
        .onPreferenceChange(ExpandedHeightKey.self) { height in
            if panelState.isExpanded && height > 0 {
                panelState.expandedContentHeight = height
            }
        }
        .animation(
            panelState.isExpanded ? AnimationConstants.panelExpand : AnimationConstants.panelCollapse,
            value: panelState.isExpanded
        )
        .onChange(of: sessionManager.totalConfirmationCount) {
            let newCount = sessionManager.totalConfirmationCount
            if newCount > previousConfirmationCount {
                userDismissedConfirmations = false
            }
            previousConfirmationCount = newCount

            confirmationQueue.update(
                from: sessionManager.pendingConfirmations,
                sessions: sessionManager.sessions
            )
            if !confirmationQueue.isEmpty {
                if panelState.isExpanded {
                    panelState.cancelAutoCollapse()
                } else if !userDismissedConfirmations {
                    panelState.expandForConfirmation()
                }
            } else if panelState.wasAutoExpandedForConfirmation {
                panelState.delayedCollapse()
            }
        }
        .onChange(of: panelState.isExpanded) {
            if panelState.isExpanded {
                confirmationQueue.update(
                    from: sessionManager.pendingConfirmations,
                    sessions: sessionManager.sessions
                )
            } else if !confirmationQueue.isEmpty {
                userDismissedConfirmations = true
            }
        }
        .onChange(of: frontmostAppMonitor.frontmostAppPID) {
            if !confirmationQueue.isEmpty && !panelState.isExpanded && !userDismissedConfirmations {
                panelState.expandForConfirmation()
            }
        }
        .onChange(of: sessionManager.sessions) {
            let currentStatuses = Dictionary(
                uniqueKeysWithValues: sessionManager.sessions.map { ($0.id, $0.status) }
            )
            defer { previousStatuses = currentStatuses }

            guard !panelState.isExpanded else { return }

            for (id, currentStatus) in currentStatuses {
                guard case .completed = currentStatus else { continue }
                guard let previous = previousStatuses[id] else { continue }
                let wasActive: Bool
                switch previous {
                case .executing, .reading, .editing, .thinking, .compacting, .waitingConfirmation:
                    wasActive = true
                default:
                    wasActive = false
                }
                guard wasActive else { continue }

                if let session = sessionManager.sessions.first(where: { $0.id == id }),
                   !frontmostAppMonitor.isTerminalOfSession(session) {
                    panelState.autoExpand()
                    return
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

}
