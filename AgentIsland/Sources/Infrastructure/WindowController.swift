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
    private let trialManager: TrialManager
    private let confirmationQueue = ConfirmationQueue()
    private var hostingView: NSHostingView<AnyView>?
    private var barHostingView: NSHostingView<AnyView>?
    private var notchInfo: NotchInfo?
    private var displayChangeObserver: NSObjectProtocol?
    private var spaceChangeObserver: NSObjectProtocol?
    private var globalClickMonitor: Any?
    private lazy var settingsWindowController = SettingsWindowController(settingsStore: settingsStore, trialManager: trialManager)

    private let barHeight: CGFloat = 32
    private let hitAreaTopPadding: CGFloat = 10
    private var suppressMouseExit = false
    private var isFullyCollapsed = true
    private var expandSequence = 0
    private var collapseAnimation: NSAnimationContext?
    private var isAnimatingCollapse = false

    init(sessionManager: SessionManager, settingsStore: SettingsStore, frontmostAppMonitor: FrontmostAppMonitor, windowActivator: WindowActivator, trialManager: TrialManager) {
        self.sessionManager = sessionManager
        self.settingsStore = settingsStore
        self.frontmostAppMonitor = frontmostAppMonitor
        self.windowActivator = windowActivator
        self.trialManager = trialManager
        self.panelState = PanelState(settingsStore: settingsStore)
        super.init()
        self.panelState.onExpandChange = { [weak self] in
            self?.updatePanelFrame()
        }
    }

    func showCompactBar() {
        let info = detectNotch()
        self.notchInfo = info
        let panel = createPanel(notchInfo: info)
        let panelHeight = info.notchHeight
        let barWidth = info.barWidth

        let container = NSView(frame: NSRect(x: 0, y: 0, width: barWidth, height: panelHeight))

        let rootView = NotchRootView(
            panelState: panelState, sessionManager: sessionManager,
            confirmationQueue: confirmationQueue,
            frontmostAppMonitor: frontmostAppMonitor, windowActivator: windowActivator,
            trialManager: trialManager
        )
        let hosting = NSHostingView(rootView: AnyView(rootView))
        hosting.frame = NSRect(x: 0, y: 0, width: barWidth, height: panelHeight)
        container.addSubview(hosting)

        let barView = CompactBarWrapper(sessionManager: sessionManager, onTap: { [weak self] in
            self?.panelState.expand()
        }, onClose: { [weak self] in
            guard let self else { return }
            self.panelState.showQuitConfirmation = true
            self.panelState.expand()
        }, onCloseHover: { [weak self] hovering in
            if hovering {
                self?.panelState.cancelPendingExpand()
            }
        })
        let barHosting = NSHostingView(rootView: AnyView(barView))
        barHosting.frame = NSRect(x: 0, y: 0, width: barWidth, height: panelHeight)
        container.addSubview(barHosting)

        panel.contentView = container
        self.hostingView = hosting
        self.barHostingView = barHosting
        self.panel = panel
        panel.orderFrontRegardless()
        setupTracking(panel: panel); setupKeyMonitor()
        setupDisplayChangeObserver(); setupSpaceChangeObserver()
        observeNotchOffsetChanges()
        if settingsStore.dismissOnClickOutside {
            installGlobalClickMonitor()
        }
    }

    private func createPanel(notchInfo: NotchInfo) -> NSPanel {
        let panel = NotchPanel(
            contentRect: NSRect(origin: NSPoint(x: notchInfo.barOriginX, y: notchInfo.barOriginY),
                                size: NSSize(width: notchInfo.barWidth, height: notchInfo.notchHeight)),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .statusBar
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle, .stationary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.isMovable = false; panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.ignoresMouseEvents = false
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
                self.panelState.collapse()
                return nil
            }

            guard let current = self.confirmationQueue.currentItem else { return event }

            guard let chars = event.charactersIgnoringModifiers else { return event }

            if flags == [.command, .shift], chars == "y" {
                if current.confirmation.type == .permission,
                   case .permission(let details) = current.confirmation.details {
                    self.handleConfirmationResponse(current, .allowAlways(toolName: details.toolName))
                    return nil
                }
            }

            if flags == [.command, .shift], chars == "a" {
                if current.confirmation.type == .permission {
                    self.handleConfirmationResponse(current, .autoApprove)
                    return nil
                }
            }

            if flags == .command {
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
                        if case .choice(let details) = current.confirmation.details, !details.multiSelect {
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
                panelState.collapse()
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
                self.notchInfo = self.detectNotch()
                self.updatePanelFrame()
            }
        }
    }

    private func detectNotch() -> NotchInfo {
        NotchDetector.detect(
            widthOffset: settingsStore.notchWidthOffset,
            heightOffset: settingsStore.notchHeightOffset
        )
    }

    private func observeNotchOffsetChanges() {
        withObservationTracking {
            _ = settingsStore.notchWidthOffset
            _ = settingsStore.notchHeightOffset
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.panel != nil else { return }
                self.notchInfo = self.detectNotch()
                self.repositionPanel()
                self.observeNotchOffsetChanges()
            }
        }
    }

    private func repositionPanel() {
        guard let panel, let notchInfo else { return }
        let frame = NSRect(
            origin: NSPoint(x: notchInfo.barOriginX, y: notchInfo.barOriginY),
            size: NSSize(width: notchInfo.barWidth, height: notchInfo.notchHeight)
        )
        if !panelState.isExpanded {
            panel.setFrame(frame, display: true)
            hostingView?.frame = NSRect(origin: .zero, size: frame.size)
            barHostingView?.frame = NSRect(origin: .zero, size: frame.size)
        }
    }

    private func setupSpaceChangeObserver() {
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.panel?.orderFrontRegardless()
            }
        }
    }

    private func installGlobalClickMonitor() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel else { return }
                guard self.panelState.isExpanded else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) {
                    self.panelState.collapse()
                }
            }
        }
    }

    private func updatePanelFrame() {
        guard let panel, let notchInfo, let hostingView else { return }

        let isExpanded = panelState.isExpanded
        let barWidth = notchInfo.barWidth

        if isExpanded {
            panel.makeKey()
            isAnimatingCollapse = false
            hostingView.alphaValue = 1
            hostingView.isHidden = false
            barHostingView?.alphaValue = 0
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
            let newOriginY = notchInfo.barOriginY + notchInfo.notchHeight - targetHeight

            if isFullyCollapsed {
                isFullyCollapsed = false
                suppressMouseExit = true
                expandSequence += 1
                let seq = expandSequence

                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(400))
                    guard let self, self.expandSequence == seq else { return }
                    self.suppressMouseExit = false
                    if let panel = self.panel {
                        var checkFrame = panel.frame
                        checkFrame.size.height += self.hitAreaTopPadding
                        if !checkFrame.contains(NSEvent.mouseLocation) {
                            self.panelState.mouseExited()
                        }
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
            isAnimatingCollapse = true
            let collapsedHeight = notchInfo.notchHeight
            let targetFrame = NSRect(
                x: notchInfo.barOriginX, y: notchInfo.barOriginY,
                width: barWidth, height: collapsedHeight
            )

            hostingView.alphaValue = 0
            hostingView.isHidden = true
            barHostingView?.alphaValue = 1
            barHostingView?.isHidden = false

            // Instantly collapse height to avoid vertical bar drift,
            // then animate only the width narrowing
            let widthOnlyFrame = NSRect(
                x: panel.frame.origin.x, y: notchInfo.barOriginY,
                width: panel.frame.width, height: collapsedHeight
            )
            panel.setFrame(widthOnlyFrame, display: false)
            hostingView.frame = NSRect(x: 0, y: 0, width: barWidth, height: collapsedHeight)
            barHostingView?.frame = NSRect(x: 0, y: 0, width: Int(panel.frame.width), height: Int(collapsedHeight))

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetFrame, display: true)
            }, completionHandler: { [weak self] in
                guard let self, self.isAnimatingCollapse else { return }
                self.isAnimatingCollapse = false
                self.barHostingView?.frame = NSRect(x: 0, y: 0, width: barWidth, height: collapsedHeight)
                hostingView.frame = NSRect(x: 0, y: 0, width: barWidth, height: collapsedHeight)
                hostingView.alphaValue = 1
                hostingView.isHidden = false
            })
        }
    }
}

private struct CompactBarWrapper: View {
    var sessionManager: SessionManager
    var onTap: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil
    var onCloseHover: ((Bool) -> Void)? = nil

    var body: some View {
        CompactBarView(
            status: sessionManager.aggregateStatus,
            sessionCount: sessionManager.sessions.count,
            elapsedTime: nil,
            isOffline: sessionManager.health.isAnyOffline,
            confirmationTitle: firstConfirmationTitle,
            confirmationCount: totalConfirmationCount,
            onClose: onClose,
            onCloseHover: onCloseHover
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    private var firstConfirmationTitle: String? {
        for (_, confs) in sessionManager.pendingConfirmations {
            if let first = confs.first {
                return first.title
            }
        }
        return nil
    }

    private var totalConfirmationCount: Int {
        sessionManager.pendingConfirmations.values.reduce(0) { $0 + $1.count }
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

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown && !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }
}
