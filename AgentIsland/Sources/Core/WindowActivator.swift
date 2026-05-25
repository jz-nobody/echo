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
        guard let terminalPID = ProcessAncestry.findTerminalAppPID(of: agentPID) else {
            return false
        }
        guard let app = NSRunningApplication(processIdentifier: terminalPID) else {
            return false
        }

        let raised = raiseTargetWindow(
            terminalPID: terminalPID,
            agentPID: agentPID,
            sessionTitle: session.title,
            bundleIdentifier: app.bundleIdentifier
        )

        app.unhide()
        app.activate()

        return raised
    }

    // MARK: - Window Activation

    private func raiseTargetWindow(
        terminalPID: pid_t,
        agentPID: pid_t,
        sessionTitle: String,
        bundleIdentifier: String?
    ) -> Bool {
        let tty = controllingTTY(of: agentPID)

        if let tty, tryAppleScript(
            bundleIdentifier: bundleIdentifier,
            tty: tty
        ) {
            return true
        }

        return raiseViaAccessibility(
            terminalPID: terminalPID,
            sessionTitle: sessionTitle
        )
    }

    // MARK: - Accessibility API (primary)

    private func raiseViaAccessibility(
        terminalPID: pid_t,
        sessionTitle: String
    ) -> Bool {
        let appElement = AXUIElementCreateApplication(terminalPID)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXWindowsAttribute as CFString, &windowsRef
        ) == .success, let windows = windowsRef as? [AXUIElement] else {
            return false
        }

        let target = pickBestWindow(windows: windows, sessionTitle: sessionTitle)
        guard let window = target else { return false }

        var minimizedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            window, kAXMinimizedAttribute as CFString, &minimizedRef
        ) == .success, let isMinimized = minimizedRef as? Bool, isMinimized {
            AXUIElementSetAttributeValue(
                window, kAXMinimizedAttribute as CFString, kCFBooleanFalse
            )
        }

        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        return true
    }

    private func pickBestWindow(
        windows: [AXUIElement],
        sessionTitle: String
    ) -> AXUIElement? {
        var exactSegmentMatches: [AXUIElement] = []
        var substringMatches: [AXUIElement] = []

        for window in windows {
            var titleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                window, kAXTitleAttribute as CFString, &titleRef
            ) == .success, let title = titleRef as? String else { continue }

            if hasExactSegmentMatch(title: title, sessionTitle: sessionTitle) {
                exactSegmentMatches.append(window)
            } else if title.localizedCaseInsensitiveContains(sessionTitle) {
                substringMatches.append(window)
            }
        }

        let candidates: [AXUIElement]
        if !exactSegmentMatches.isEmpty {
            candidates = exactSegmentMatches
        } else if !substringMatches.isEmpty {
            candidates = substringMatches
        } else {
            candidates = windows
        }

        if candidates.count == 1 { return candidates[0] }

        if let minimized = firstMinimized(in: candidates) {
            return minimized
        }

        if let nonMain = firstNonMain(in: candidates) {
            return nonMain
        }

        return candidates.first
    }

    private func hasExactSegmentMatch(title: String, sessionTitle: String) -> Bool {
        let segments = title.components(separatedBy: " — ")
        return segments.contains { $0.caseInsensitiveCompare(sessionTitle) == .orderedSame }
    }

    private func firstMinimized(in windows: [AXUIElement]) -> AXUIElement? {
        for window in windows {
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                window, kAXMinimizedAttribute as CFString, &ref
            ) == .success, let isMin = ref as? Bool, isMin {
                return window
            }
        }
        return nil
    }

    private func firstNonMain(in windows: [AXUIElement]) -> AXUIElement? {
        guard windows.count > 1 else { return nil }
        for window in windows {
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                window, kAXMainAttribute as CFString, &ref
            ) == .success, let isMain = ref as? Bool, !isMain {
                return window
            }
        }
        return nil
    }

    // MARK: - AppleScript (precise TTY matching, requires Automation permission)

    private func tryAppleScript(bundleIdentifier: String?, tty: String) -> Bool {
        let source: String?
        switch bundleIdentifier {
        case "com.apple.Terminal":
            source = terminalAppleScript(tty: tty)
        case "com.googlecode.iterm2":
            source = itermAppleScript(tty: tty)
        default:
            source = nil
        }
        guard let source else { return false }
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }

    private func terminalAppleScript(tty: String) -> String {
        """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        if miniaturized of w then
                            set miniaturized of w to false
                        end if
                        set index of w to 1
                        set frontmost of w to true
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
    }

    private func itermAppleScript(tty: String) -> String {
        """
        tell application "iTerm2"
            repeat with w in windows
                repeat with aTab in tabs of w
                    repeat with s in sessions of aTab
                        if tty of s is "\(tty)" then
                            if miniaturized of w then
                                set miniaturized of w to false
                            end if
                            select w
                            select aTab
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
    }

    // MARK: - Helpers

    private func controllingTTY(of pid: pid_t) -> String? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let tdev = info.kp_eproc.e_tdev
        guard tdev != 0, tdev != UInt32(bitPattern: -1) else { return nil }
        guard let namePtr = devname(tdev, S_IFCHR) else { return nil }
        return "/dev/" + String(cString: namePtr)
    }
}
