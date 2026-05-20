import Foundation

@MainActor
@Observable
final class PanelState {
    private(set) var isExpanded = false
    var confirmationsActive = false
    private var expandTimer: Timer?
    private var collapseTimer: Timer?
    private let autoCollapseDelay: TimeInterval
    @ObservationIgnored var onExpandChange: (() -> Void)?
    @ObservationIgnored var expandedContentHeight: CGFloat = 0 {
        didSet {
            guard isExpanded, expandedContentHeight != oldValue else { return }
            onExpandChange?()
        }
    }

    let settingsStore: SettingsStore

    init(settingsStore: SettingsStore, autoCollapseDelay: TimeInterval = 5.0) {
        self.settingsStore = settingsStore
        self.autoCollapseDelay = autoCollapseDelay
    }

    func mouseEntered() {
        collapseTimer?.invalidate()
        collapseTimer = nil
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
        guard !confirmationsActive else { return }
        guard settingsStore.autoCollapseOnMouseExit else { return }
        collapseTimer?.invalidate()
        collapseTimer = Timer.scheduledTimer(withTimeInterval: autoCollapseDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.collapse()
            }
        }
    }

    func expand() {
        collapseTimer?.invalidate()
        collapseTimer = nil
        isExpanded = true
        onExpandChange?()
    }

    func collapse() {
        collapseTimer?.invalidate()
        collapseTimer = nil
        isExpanded = false
        onExpandChange?()
    }

    func autoExpand() {
        confirmationsActive = true
        expandTimer?.invalidate()
        collapseTimer?.invalidate()
        collapseTimer = nil
        expand()
    }

    func toggle() {
        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }
}
