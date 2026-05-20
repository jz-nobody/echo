import Foundation

@MainActor
@Observable
final class PanelState {
    private(set) var isExpanded = false
    var confirmationsActive = false
    private var expandTimer: Timer?

    let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func mouseEntered() {
        expandTimer?.invalidate()
        expandTimer = Timer.scheduledTimer(withTimeInterval: settingsStore.hoverDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.expand()
            }
        }
    }

    func mouseExited() {
        expandTimer?.invalidate()
        expandTimer = nil
        if !confirmationsActive { collapse() }
    }

    func expand() {
        isExpanded = true
    }

    func collapse() {
        isExpanded = false
    }

    func autoExpand() {
        confirmationsActive = true
        expandTimer?.invalidate()
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
