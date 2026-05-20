import AppKit
import SwiftUI

@MainActor
final class WindowController: NSObject {
    private var panel: NSPanel?
    private let panelState: PanelState
    private let sessionManager: SessionManager
    private let settingsStore: SettingsStore
    private let frontmostAppMonitor: FrontmostAppMonitor
    private let windowActivator: WindowActivator
    private let confirmationQueue = ConfirmationQueue()
    private var hostingView: NSHostingView<AnyView>?
    private var barHostingView: NSHostingView<AnyView>?
    private var notchInfo: NotchInfo?
    private var fullscreenObserver: NSObjectProtocol?
    private var displayChangeObserver: NSObjectProtocol?
    private var globalClickMonitor: Any?
    private lazy var settingsWindowController = SettingsWindowController(settingsStore: settingsStore)

    private let barWidth: CGFloat = 200
    private let barHeight: CGFloat = 32
    private var suppressMouseExit = false
    private var isFullyCollapsed = true
    private var expandSequence = 0

    init(sessionManager: SessionManager, settingsStore: SettingsStore, frontmostAppMonitor: FrontmostAppMonitor, windowActivator: WindowActivator) {
        self.sessionManager = sessionManager
        self.settingsStore = settingsStore
        self.frontmostAppMonitor = frontmostAppMonitor
        self.windowActivator = windowActivator
        self.panelState = PanelState(settingsStore: settingsStore)
        super.init()
        self.panelState.onExpandChange = { [weak self] in
            self?.updatePanelFrame()
        }
    }

    func showCompactBar() {
        let info = NotchDetector.detect()
        self.notchInfo = info
        let panel = createPanel(notchInfo: info)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: barWidth, height: barHeight))

        let rootView = NotchRootView(
            panelState: panelState, sessionManager: sessionManager,
            confirmationQueue: confirmationQueue,
            frontmostAppMonitor: frontmostAppMonitor, windowActivator: windowActivator
        )
        let hosting = NSHostingView(rootView: AnyView(rootView))
        hosting.frame = NSRect(x: 0, y: 0, width: barWidth, height: barHeight)
        container.addSubview(hosting)

        let barView = CompactBarWrapper(sessionManager: sessionManager)
        let barHosting = NSHostingView(rootView: AnyView(barView))
        barHosting.frame = NSRect(x: 0, y: 0, width: barWidth, height: barHeight)
        container.addSubview(barHosting)

        panel.contentView = container
        self.hostingView = hosting
        self.barHostingView = barHosting
        self.panel = panel
        panel.orderFrontRegardless()
        setupTracking(panel: panel); setupKeyMonitor()
        setupFullscreenObserver(); setupDisplayChangeObserver()
        if settingsStore.dismissOnClickOutside {
            installGlobalClickMonitor()
        }
    }

    private func createPanel(notchInfo: NotchInfo) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: NSPoint(x: notchInfo.barOriginX, y: notchInfo.barOriginY),
                                size: NSSize(width: barWidth, height: barHeight)),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .statusBar + 1
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.isMovable = false; panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false; panel.isFloatingPanel = true
        panel.acceptsMouseMovedEvents = true
        return panel
    }

    private func setupTracking(panel: NSPanel) {
        let trackingView = TrackingView(
            onMouseEntered: { [weak self] in self?.panelState.mouseEntered() },
            onMouseExited: { [weak self] in
                guard let self, !self.suppressMouseExit else { return }
                self.panelState.mouseExited()
            }
        )
        trackingView.frame = panel.contentView?.bounds ?? .zero
        trackingView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(trackingView)
    }
    private func setupKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command, event.charactersIgnoringModifiers == "," {
                self.settingsWindowController.showSettings()
                return nil
            }

            guard self.panelState.isExpanded else { return event }

            if event.keyCode == 53 {
                self.panelState.confirmationsActive = false
                self.panelState.collapse()
                return nil
            }

            guard let current = self.confirmationQueue.currentItem else { return event }

            if flags == .command, let chars = event.charactersIgnoringModifiers {
                switch chars {
                case "y":
                    if current.confirmation.type == .permission {
                        self.handleConfirmationResponse(current, .allow)
                        return nil
                    }
                case "n":
                    if current.confirmation.type == .permission {
                        self.handleConfirmationResponse(current, .deny)
                        return nil
                    }
                default:
                    if let digit = Int(chars), digit >= 1, digit <= 9 {
                        if case .choice(let details) = current.confirmation.details {
                            let index = digit - 1
                            if index < details.options.count {
                                self.handleConfirmationResponse(current, .select(optionId: details.options[index].id))
                                return nil
                            }
                        }
                    }
                }
            }
            return event
        }
    }

    private func handleConfirmationResponse(_ item: QueuedConfirmation, _ response: ConfirmationResponse) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await sessionManager.respond(
                    session: item.session,
                    confirmation: item.confirmation,
                    response: response
                )
            } catch {
                NSLog("[AgentIsland] Confirmation response failed: \(error)")
            }
            confirmationQueue.update(
                from: sessionManager.pendingConfirmations,
                sessions: sessionManager.sessions
            )
            if confirmationQueue.isEmpty {
                panelState.confirmationsActive = false
                panelState.collapse()
            }
        }
    }

    private func setupFullscreenObserver() {
        fullscreenObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel else { return }
                let shouldHide = self.settingsStore.hideInFullscreen
                    && self.frontmostAppMonitor.isFullscreenAppActive()
                panel.setIsVisible(!shouldHide)
            }
        }
    }

    private func setupDisplayChangeObserver() {
        displayChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel != nil else { return }
                self.notchInfo = NotchDetector.detect()
                self.updatePanelFrame()
            }
        }
    }

    private func installGlobalClickMonitor() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel else { return }
                guard self.panelState.isExpanded else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) {
                    self.panelState.confirmationsActive = false
                    self.panelState.collapse()
                }
            }
        }
    }

    private func updatePanelFrame() {
        guard let panel, let notchInfo, let hostingView else { return }

        let isExpanded = panelState.isExpanded

        if isExpanded {
            barHostingView?.isHidden = true
            let targetWidth = max(barWidth, settingsStore.maxPanelWidth)
            let contentH = panelState.expandedContentHeight
            let targetHeight = contentH > 0
                ? min(contentH, settingsStore.maxPanelHeight)
                : settingsStore.maxPanelHeight

            let barCenterX = notchInfo.barOriginX + barWidth / 2
            let newOriginX = max(
                notchInfo.screenFrame.minX + 8,
                min(barCenterX - targetWidth / 2, notchInfo.screenFrame.maxX - targetWidth - 8)
            )
            let newOriginY = notchInfo.barOriginY + barHeight - targetHeight

            if isFullyCollapsed {
                isFullyCollapsed = false
                suppressMouseExit = true
                expandSequence += 1
                let seq = expandSequence

                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(400))
                    guard let self, self.expandSequence == seq else { return }
                    self.suppressMouseExit = false
                    if let panel = self.panel, !panel.frame.contains(NSEvent.mouseLocation) {
                        self.panelState.mouseExited()
                    }
                }
            }

            hostingView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
            panel.setFrame(
                NSRect(x: newOriginX, y: newOriginY, width: targetWidth, height: targetHeight),
                display: true
            )
        } else {
            isFullyCollapsed = true
            hostingView.frame = NSRect(x: 0, y: 0, width: barWidth, height: barHeight)
            panel.setFrame(
                NSRect(x: notchInfo.barOriginX, y: notchInfo.barOriginY,
                       width: barWidth, height: barHeight),
                display: true
            )
            barHostingView?.frame = NSRect(x: 0, y: 0, width: barWidth, height: barHeight)
            barHostingView?.isHidden = false
        }
    }
}

private struct CompactBarWrapper: View {
    var sessionManager: SessionManager

    var body: some View {
        CompactBarView(
            status: sessionManager.aggregateStatus,
            sessionCount: sessionManager.activeSessionCount,
            elapsedTime: elapsedTimeText,
            isOffline: sessionManager.health.isAnyOffline
        )
        .frame(width: DesignTokens.compactBarWidth, height: DesignTokens.compactBarHeight)
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
