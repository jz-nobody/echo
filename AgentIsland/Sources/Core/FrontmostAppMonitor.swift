import AppKit
import Foundation

@MainActor
@Observable
final class FrontmostAppMonitor: FrontmostAppProviding {
    private(set) var frontmostAppPID: pid_t?
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        frontmostAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        startObserving()
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func isTerminalOfSession(_ session: AgentSession) -> Bool {
        guard let agentPID = session.terminalInfo?.pid else { return false }
        guard let frontmostPID = frontmostAppPID else { return false }
        guard let terminalPID = ProcessAncestry.findTerminalAppPID(of: agentPID) else {
            return false
        }
        return terminalPID == frontmostPID
    }

    func isFullscreenAppActive() -> Bool {
        guard let screen = NSScreen.main else { return false }
        let screenFrame = screen.frame

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        let myPID = ProcessInfo.processInfo.processIdentifier

        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != myPID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let width = boundsDict["Width"] as? CGFloat,
                  let height = boundsDict["Height"] as? CGFloat else { continue }

            if width >= screenFrame.width && height >= screenFrame.height {
                return true
            }
        }

        return false
    }

    private func startObserving() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.frontmostAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            }
        }
    }
}
