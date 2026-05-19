import AppKit
import SwiftUI

@MainActor
final class WindowController: NSObject {
    private var panel: NSPanel?
    private let panelState = PanelState()
    private var hostingView: NSHostingView<AnyView>?
    private var notchInfo: NotchInfo?

    private let barWidth: CGFloat = 200
    private let barHeight: CGFloat = 32
    private let expandedHeight: CGFloat = 300
    private let expandedWidth: CGFloat = 400

    override init() {
        super.init()
    }

    func showCompactBar() {
        let info = NotchDetector.detect()
        self.notchInfo = info
        let panel = createPanel(notchInfo: info)

        let rootView = NotchRootView(
            panelState: panelState,
            status: .executing,
            sessionCount: 2,
            elapsedTime: "3m"
        )
        let hosting = NSHostingView(rootView: AnyView(rootView))
        hosting.frame = NSRect(x: 0, y: 0, width: barWidth, height: barHeight)
        panel.contentView = hosting

        self.hostingView = hosting
        self.panel = panel
        panel.orderFrontRegardless()

        setupTracking(panel: panel)
        setupKeyMonitor()
    }

    private func createPanel(notchInfo: NotchInfo) -> NSPanel {
        let origin = NSPoint(x: notchInfo.barOriginX, y: notchInfo.barOriginY)
        let size = NSSize(width: barWidth, height: barHeight)

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
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
        panel.acceptsMouseMovedEvents = true

        return panel
    }

    private func setupTracking(panel: NSPanel) {
        let trackingView = TrackingView(
            onMouseEntered: { [weak self] in
                self?.panelState.mouseEntered()
                self?.updatePanelFrame()
            },
            onMouseExited: { [weak self] in
                self?.panelState.mouseExited()
                self?.updatePanelFrame()
            }
        )
        trackingView.frame = panel.contentView?.bounds ?? .zero
        trackingView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(trackingView)
    }

    private func setupKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panelState.isExpanded else { return event }
            if event.keyCode == 53 { // ESC
                self.panelState.collapse()
                self.updatePanelFrame()
                return nil
            }
            return event
        }
    }

    private func updatePanelFrame() {
        guard let panel, let notchInfo, let hostingView else { return }
        let targetHeight = panelState.isExpanded ? (barHeight + expandedHeight) : barHeight
        let targetWidth = panelState.isExpanded ? max(barWidth, expandedWidth) : barWidth
        let newOriginY = notchInfo.barOriginY + barHeight - targetHeight

        NSAnimationContext.runAnimationGroup { context in
            context.duration = panelState.isExpanded ? 0.3 : 0.25
            context.timingFunction = CAMediaTimingFunction(name: panelState.isExpanded ? .easeOut : .easeIn)
            panel.animator().setFrame(
                NSRect(x: notchInfo.barOriginX, y: newOriginY, width: targetWidth, height: targetHeight),
                display: true
            )
        }
        hostingView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
    }
}

