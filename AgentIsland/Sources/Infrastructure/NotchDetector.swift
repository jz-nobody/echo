import AppKit

struct NotchInfo {
    let hasNotch: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let screenFrame: NSRect
    let barOriginX: CGFloat
    let barOriginY: CGFloat
}

enum NotchDetector {
    static func detect(for screen: NSScreen? = nil) -> NotchInfo {
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first!
        let frame = targetScreen.frame
        let visibleFrame = targetScreen.visibleFrame

        let menuBarHeight = frame.maxY - visibleFrame.maxY
        let hasNotch = menuBarHeight > 24

        let notchHeight: CGFloat = hasNotch ? menuBarHeight : 24
        let notchWidth: CGFloat = hasNotch ? estimateNotchWidth(screen: targetScreen) : 0

        let barOriginX: CGFloat
        if hasNotch {
            let notchCenterX = frame.midX
            let notchRightEdge = notchCenterX + (notchWidth / 2)
            barOriginX = notchRightEdge + 4
        } else {
            barOriginX = frame.midX + 100
        }

        let barOriginY = frame.maxY - notchHeight

        return NotchInfo(
            hasNotch: hasNotch,
            notchWidth: notchWidth,
            notchHeight: notchHeight,
            screenFrame: frame,
            barOriginX: barOriginX,
            barOriginY: barOriginY
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
