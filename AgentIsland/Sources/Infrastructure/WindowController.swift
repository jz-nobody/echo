import AppKit
import SwiftUI

final class WindowController {
    private var panel: NSPanel?
    private let barWidth: CGFloat = 200
    private let barHeight: CGFloat = 32

    func showCompactBar() {
        let notchInfo = NotchDetector.detect()
        let panel = createPanel(notchInfo: notchInfo)
        let hostingView = NSHostingView(rootView: CompactBarPlaceholder())
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func createPanel(notchInfo: NotchInfo) -> NSPanel {
        let origin = NSPoint(
            x: notchInfo.barOriginX,
            y: notchInfo.barOriginY
        )
        let size = NSSize(width: barWidth, height: barHeight)
        let frame = NSRect(origin: origin, size: size)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .statusBar + 1
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isFloatingPanel = true

        return panel
    }
}

private struct CompactBarPlaceholder: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(nsColor: NSColor(hex: "#0A84FF")))
                .frame(width: 8, height: 8)
            Text("Agent Island")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(width: 200, height: 32)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
