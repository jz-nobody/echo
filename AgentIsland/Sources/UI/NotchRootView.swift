import SwiftUI

struct NotchRootView: View {
    let panelState: PanelState
    let status: SessionStatus
    let sessionCount: Int
    let elapsedTime: String?

    var body: some View {
        VStack(spacing: 0) {
            CompactBarView(
                status: status,
                sessionCount: sessionCount,
                elapsedTime: elapsedTime
            )
            .frame(height: DesignTokens.compactBarHeight)

            if panelState.isExpanded {
                ExpandedPanelView()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(
            panelState.isExpanded ? AnimationConstants.panelExpand : AnimationConstants.panelCollapse,
            value: panelState.isExpanded
        )
    }
}
