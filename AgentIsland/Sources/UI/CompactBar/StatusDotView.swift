import SwiftUI

struct StatusDotView: View {
    let status: SessionStatus

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: DesignTokens.statusDotSize, height: DesignTokens.statusDotSize)
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .animation(pulseAnimation, value: isPulsing)
            .onAppear { updatePulse() }
            .onChange(of: status) { _, _ in updatePulse() }
            .accessibilityHidden(true)
    }

    private var pulseAnimation: Animation? {
        switch status {
        case .thinking:
            .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        case .executing:
            .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
        case .waitingConfirmation:
            .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
        default:
            nil
        }
    }

    private func updatePulse() {
        switch status {
        case .thinking, .executing, .waitingConfirmation:
            isPulsing = true
        default:
            isPulsing = false
        }
    }
}
