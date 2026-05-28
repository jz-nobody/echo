import AppKit
import Foundation

@MainActor
final class WindowActivator: WindowActivating {
    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func jumpToSession(_ session: AgentSession) -> Bool {
        guard !settingsStore.disableClickToJump else { return false }
        guard let agentPID = session.terminalInfo?.pid else { return false }

        let runningAppPIDs = Set(
            NSWorkspace.shared.runningApplications.map { $0.processIdentifier }
        )

        let terminalPID: pid_t
        if runningAppPIDs.contains(agentPID) {
            terminalPID = agentPID
        } else if let found = ProcessAncestry.findTerminalAppPID(of: agentPID) {
            terminalPID = found
        } else {
            return false
        }

        guard let app = NSRunningApplication(processIdentifier: terminalPID) else {
            return false
        }

        let title = session.title
        let appElement = AXUIElementCreateApplication(terminalPID)
        let snapshot = snapshotWindows(appElement: appElement)
        let targetIndex = WindowMatcher.selectTarget(windows: snapshot, sessionTitle: title)

        if let targetIndex, let targetWindow = axWindow(at: targetIndex, appElement: appElement) {
            unminimizeIfNeeded(targetWindow)
            AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(targetWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)

            if !app.isActive {
                app.activate()
            }
        } else {
            app.activate()
        }

        return true
    }

    // MARK: - Window Snapshots

    private func snapshotWindows(appElement: AXUIElement) -> [WindowCandidate] {
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXWindowsAttribute as CFString, &windowsRef
        ) == .success, let windows = windowsRef as? [AXUIElement] else {
            return []
        }

        return windows.enumerated().map { index, window in
            var titleRef: CFTypeRef?
            let title: String
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
               let t = titleRef as? String {
                title = t
            } else {
                title = ""
            }

            var minRef: CFTypeRef?
            let isMinimized = AXUIElementCopyAttributeValue(
                window, kAXMinimizedAttribute as CFString, &minRef
            ) == .success && (minRef as? Bool) == true

            var mainRef: CFTypeRef?
            let isMain = AXUIElementCopyAttributeValue(
                window, kAXMainAttribute as CFString, &mainRef
            ) == .success && (mainRef as? Bool) == true

            return WindowCandidate(index: index, title: title, isMinimized: isMinimized, isMain: isMain)
        }
    }

    private func axWindow(at index: Int, appElement: AXUIElement) -> AXUIElement? {
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXWindowsAttribute as CFString, &windowsRef
        ) == .success, let windows = windowsRef as? [AXUIElement],
              index < windows.count else {
            return nil
        }
        return windows[index]
    }

    private func unminimizeIfNeeded(_ window: AXUIElement) {
        var minRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            window, kAXMinimizedAttribute as CFString, &minRef
        ) == .success, let isMin = minRef as? Bool, isMin {
            AXUIElementSetAttributeValue(
                window, kAXMinimizedAttribute as CFString, kCFBooleanFalse
            )
        }
    }

    // MARK: - Terminal Detection

    private func isTerminalApp(bundleIdentifier: String?) -> Bool {
        switch bundleIdentifier {
        case "com.apple.Terminal", "com.googlecode.iterm2":
            return true
        default:
            return false
        }
    }
}
