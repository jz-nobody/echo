import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: WindowController?
    private var sessionManager: SessionManager?
    private var settingsStore: SettingsStore?
    private var bridgeServer: BridgeServer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            let server = try BridgeServer()
            Task { await server.start() }
            self.bridgeServer = server
        } catch {
            NSLog("[AgentIsland] BridgeServer init failed: \(error)")
        }

        do {
            try HookInstaller.ensureHooksInstalled()
        } catch {
            NSLog("[AgentIsland] HookInstaller failed: \(error)")
        }

        let settings = SettingsStore()
        settings.loginItemManager = LoginItemManager()
        self.settingsStore = settings

        let soundPlayer = SoundPlayer(settings: settings)
        let manager = SessionManager(
            bridgeServer: bridgeServer!,
            settingsStore: settings,
            soundPlayer: soundPlayer
        )
        manager.startPolling()

        self.sessionManager = manager
        let frontmostAppMonitor = FrontmostAppMonitor()
        let windowActivator = WindowActivator(settingsStore: settings)
        windowController = WindowController(
            sessionManager: manager,
            settingsStore: settings,
            frontmostAppMonitor: frontmostAppMonitor,
            windowActivator: windowActivator
        )
        windowController?.showCompactBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { await bridgeServer?.stop() }
    }
}
