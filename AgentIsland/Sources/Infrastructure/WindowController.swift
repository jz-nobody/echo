import AppKit
import SwiftUI

final class WindowController {
    private var panel: NSPanel?
    private let barWidth: CGFloat = 200
    private let barHeight: CGFloat = 32

    func showCompactBar() {
        let notchInfo = NotchDetector.detect()
        let panel = createPanel(notchInfo: notchInfo)
        let barView = CompactBarView(
            status: .executing,
            sessionCount: 2,
            elapsedTime: "3m"
        )
        let hostingView = NSHostingView(rootView: barView)
        hostingView.frame = NSRect(x: 0, y: 0, width: barWidth, height: barHeight)
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

