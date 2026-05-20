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
        return app.activate()
    }
}
