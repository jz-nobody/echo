import Foundation

@MainActor
@Observable
final class PanelState {
    private(set) var isExpanded = false
    private(set) var wasAutoExpandedForConfirmation = false
    var showQuitConfirmation = false
    private var expandTimer: Timer?
    private var collapseTimer: Timer?
    private var autoCollapseTimer: Timer?
    let mouseExitDelay: TimeInterval
    let autoCollapseDelay: TimeInterval
    @ObservationIgnored var onExpandChange: (() -> Void)?
    @ObservationIgnored var expandedContentHeight: CGFloat = 0 {
        didSet {
            guard isExpanded, expandedContentHeight != oldValue else { return }
            onExpandChange?()
        }
    }

    let settingsStore: SettingsStore

    init(
        settingsStore: SettingsStore,
        mouseExitDelay: TimeInterval = 1.0,
        autoCollapseDelay: TimeInterval = 3.0
    ) {
        self.settingsStore = settingsStore
        self.mouseExitDelay = mouseExitDelay
        self.autoCollapseDelay = autoCollapseDelay
    }

    func mouseEntered() {
        collapseTimer?.invalidate()
        collapseTimer = nil
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
        expandTimer?.invalidate()
        expandTimer = Timer.scheduledTimer(withTimeInterval: settingsStore.hoverDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.expand()
            }
        }
    }

    func mouseExited() {
        expandTimer?.invalidate()
        expandTimer = nil
        guard settingsStore.autoCollapseOnMouseExit else { return }
        guard !wasAutoExpandedForConfirmation else { return }
        collapseTimer?.invalidate()
        collapseTimer = nil
        collapse()
    }

    func cancelPendingExpand() {
        expandTimer?.invalidate()
        expandTimer = nil
    }

    func expand() {
        collapseTimer?.invalidate()
        collapseTimer = nil
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
        wasAutoExpandedForConfirmation = false
        isExpanded = true
        onExpandChange?()
    }

    func collapse() {
        collapseTimer?.invalidate()
        collapseTimer = nil
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
        expandTimer?.invalidate()
        expandTimer = nil
        showQuitConfirmation = false
        wasAutoExpandedForConfirmation = false
        isExpanded = false
        onExpandChange?()
    }

    func autoExpand() {
        expandTimer?.invalidate()
        collapseTimer?.invalidate()
        collapseTimer = nil
        autoCollapseTimer?.invalidate()
        isExpanded = true
        onExpandChange?()
        autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: autoCollapseDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.collapse()
            }
        }
    }

    func expandForConfirmation() {
        expandTimer?.invalidate()
        collapseTimer?.invalidate()
        collapseTimer = nil
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
        wasAutoExpandedForConfirmation = true
        isExpanded = true
        onExpandChange?()
    }

    func delayedCollapse() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.collapse()
            }
        }
    }

    func cancelAutoCollapse() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
    }

    func toggle() {
        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }
}
