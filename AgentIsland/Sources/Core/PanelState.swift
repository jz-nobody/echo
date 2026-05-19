import Foundation

@MainActor
@Observable
final class PanelState {
    private(set) var isExpanded = false
    private var expandTimer: Timer?

    let hoverDelay: TimeInterval

    init(hoverDelay: TimeInterval = AnimationConstants.hoverDelay) {
        self.hoverDelay = hoverDelay
    }

    func mouseEntered() {
        expandTimer?.invalidate()
        expandTimer = Timer.scheduledTimer(withTimeInterval: hoverDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.expand()
            }
        }
    }

    func mouseExited() {
        expandTimer?.invalidate()
        expandTimer = nil
        collapse()
    }

    func expand() {
        isExpanded = true
    }

    func collapse() {
        isExpanded = false
    }

    func toggle() {
        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }
}
