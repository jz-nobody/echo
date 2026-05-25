import AppKit

struct NotchInfo {
    let hasNotch: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let screenFrame: NSRect
    let barOriginX: CGFloat
    let barOriginY: CGFloat
    let barWidth: CGFloat
}

enum NotchDetector {
    static func detect(for screen: NSScreen? = nil, widthOffset: CGFloat = 0, heightOffset: CGFloat = 0) -> NotchInfo {
        guard let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return NotchInfo(hasNotch: false, notchWidth: 0, notchHeight: 24,
                             screenFrame: .zero, barOriginX: 0, barOriginY: 0, barWidth: 360)
        }
        let frame = targetScreen.frame
        let visibleFrame = targetScreen.visibleFrame

        let menuBarHeight = frame.maxY - visibleFrame.maxY
        let hasNotch = menuBarHeight > 24

        let notchHeight: CGFloat = (hasNotch ? menuBarHeight : 24) + heightOffset
        let notchWidth: CGFloat = hasNotch ? estimateNotchWidth(screen: targetScreen) : 0

        let leftPad: CGFloat = 70
        let rightPad: CGFloat = 100
        let barWidth: CGFloat = (hasNotch ? notchWidth + leftPad + rightPad : 360) + widthOffset
        let barOriginX = hasNotch
            ? frame.midX - notchWidth / 2 - leftPad - widthOffset / 2
            : frame.midX - barWidth / 2
        let barOriginY = frame.maxY - notchHeight

        return NotchInfo(
            hasNotch: hasNotch,
            notchWidth: notchWidth,
            notchHeight: notchHeight,
            screenFrame: frame,
            barOriginX: barOriginX,
            barOriginY: barOriginY,
            barWidth: barWidth
        )
    }

    private static func estimateNotchWidth(screen: NSScreen) -> CGFloat {
        if let topLeft = screen.auxiliaryTopLeftArea,
           let topRight = screen.auxiliaryTopRightArea {
            let leftEnd = topLeft.maxX
            let rightStart = topRight.minX
            return rightStart - leftEnd
        }
        return 180
    }
}
