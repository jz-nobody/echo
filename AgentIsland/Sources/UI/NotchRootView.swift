import SwiftUI

struct NotchRootView: View {
    let panelState: PanelState
    var sessionManager: SessionManager

    var body: some View {
        VStack(spacing: 0) {
            CompactBarView(
                status: sessionManager.aggregateStatus,
                sessionCount: sessionManager.activeSessionCount,
                elapsedTime: elapsedTimeText
            )
            .frame(height: DesignTokens.compactBarHeight)

            if panelState.isExpanded {
                ExpandedPanelView(sessions: sessionManager.sessions)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(
            panelState.isExpanded ? AnimationConstants.panelExpand : AnimationConstants.panelCollapse,
            value: panelState.isExpanded
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
