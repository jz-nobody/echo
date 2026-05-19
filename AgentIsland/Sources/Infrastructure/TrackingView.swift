import AppKit

final class TrackingView: NSView {
    private let onMouseEntered: @MainActor () -> Void
    private let onMouseExited: @MainActor () -> Void

    init(
        onMouseEntered: @escaping @MainActor () -> Void,
        onMouseExited: @escaping @MainActor () -> Void
    ) {
        self.onMouseEntered = onMouseEntered
        self.onMouseExited = onMouseExited
        super.init(frame: .zero)
        setupTracking()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupTracking() {
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited()
    }
}
