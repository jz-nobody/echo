import SwiftUI

enum DesignTokens {
    // MARK: - Background
    static let compactBarBackground = Color(nsColor: NSColor(hex: "#000000"))
    static let panelBackground = Color(nsColor: NSColor(hex: "#1C1C1E"))
    static let cardBackground = Color(nsColor: NSColor(hex: "#2C2C2E"))
    static let cardHover = Color(nsColor: NSColor(hex: "#3A3A3C"))
    static let separator = Color(nsColor: NSColor(hex: "#3A3A3C"))

    // MARK: - Status Colors
    static let statusIdle = Color(nsColor: NSColor(hex: "#8E8E93"))
    static let statusThinking = Color(nsColor: NSColor(hex: "#0A84FF"))
    static let statusExecuting = Color(nsColor: NSColor(hex: "#0A84FF"))
    static let statusCompleted = Color(nsColor: NSColor(hex: "#30D158"))
    static let statusWaiting = Color(nsColor: NSColor(hex: "#FF9F0A"))
    static let statusError = Color(nsColor: NSColor(hex: "#FF453A"))

    // MARK: - Agent Tag Colors
    static let tagClaude = Color(nsColor: NSColor(hex: "#D97757"))
    static let tagCodex = Color(nsColor: NSColor(hex: "#10A37F"))
    static let tagQoderWork = Color(nsColor: NSColor(hex: "#0A84FF"))
    static let tagGemini = Color(nsColor: NSColor(hex: "#4285F4"))
    static let tagTerminal = Color(nsColor: NSColor(hex: "#6E6E73"))

    // MARK: - Text
    static let textPrimary = Color.white
    static let textSecondary = Color(nsColor: NSColor(hex: "#8E8E93"))
    static let textCode = Color(nsColor: NSColor(hex: "#30D158"))

    // MARK: - Confirmation
    static let diffAdded = Color(nsColor: NSColor(hex: "#30D158"))
    static let diffRemoved = Color(nsColor: NSColor(hex: "#FF453A"))
    static let choiceOptionBackground = Color(nsColor: NSColor(hex: "#1E3A3A"))
    static let shortcutBadgeBackground = Color(nsColor: NSColor(hex: "#3A3A3C"))
    static let confirmationAllowBackground = Color.white
    static let confirmationAllowText = Color.black
    static let confirmationDenyBackground = Color(nsColor: NSColor(hex: "#3A3A3C"))

    // MARK: - Task & Subagent
    static let todoInProgress = Color(nsColor: NSColor(hex: "#0A84FF"))
    static let todoCompleted = Color(nsColor: NSColor(hex: "#30D158"))
    static let todoPending = Color(nsColor: NSColor(hex: "#8E8E93"))
    static let tagTerminalBackground = Color(nsColor: NSColor(hex: "#48484A"))
    static let tagAutoApproveBackground = Color(nsColor: NSColor(hex: "#FF453A"))
    static let toolBash = Color(nsColor: NSColor(hex: "#D97757"))
    static let toolWrite = Color(nsColor: NSColor(hex: "#30D158"))
    static let toolRead = Color(nsColor: NSColor(hex: "#0A84FF"))

    // MARK: - Dimensions
    static let compactBarHeight: CGFloat = 36
    static let compactBarPaddingH: CGFloat = 12
    static let compactBarCornerRadius: CGFloat = 18
    static let compactBarWidth: CGFloat = 200
    static let statusDotSize: CGFloat = 8
    static let petSizeCompact: CGFloat = 30
    static let petSizeExpanded: CGFloat = 38
    static let panelMaxHeight: CGFloat = 550
    static let panelMaxWidth: CGFloat = 680
    static let panelCornerRadius: CGFloat = 12
    static let confirmationButtonHeight: CGFloat = 44
    static let confirmationButtonRadius: CGFloat = 8
    static let optionCardHeight: CGFloat = 44
    static let optionCardRadius: CGFloat = 8
}

enum AnimationConstants {
    static let panelExpand = Animation.spring(response: 0.35, dampingFraction: 0.92)
    static let panelCollapse = Animation.easeOut(duration: 0.22)
    static let statusTransition = Animation.easeInOut(duration: 0.2)
    static let cardAppear = Animation.easeOut(duration: 0.2)
    static let confirmationSwitch = Animation.easeInOut(duration: 0.2)
    static let hoverHighlight = Animation.linear(duration: 0.1)

    static let hoverDelay: TimeInterval = 0.15
    static let autoReminderDuration: TimeInterval = 5.0
}
