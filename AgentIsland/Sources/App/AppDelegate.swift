import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: WindowController?
    private var sessionManager: SessionManager?
    private var settingsStore: SettingsStore?
    private var claudeCodeAdaptor: ClaudeCodeAdaptor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        var adaptors: [any AgentAdaptor] = []

        let mcpClient = MCPClient(baseURL: URL(string: "http://127.0.0.1:52345")!)
        let qoderAdaptor = QoderWorkAdaptor(client: mcpClient)
        adaptors.append(qoderAdaptor)

        do {
            let claudeAdaptor = try ClaudeCodeAdaptor()
            Task { await claudeAdaptor.startMonitoring() }
            self.claudeCodeAdaptor = claudeAdaptor
            adaptors.append(claudeAdaptor)
        } catch {
            NSLog("[AgentIsland] ClaudeCodeAdaptor init failed: \(error)")
        }

        do {
            try HookInstaller.ensureHooksInstalled()
        } catch {
            NSLog("[AgentIsland] HookInstaller failed: \(error)")
        }

        let settings = SettingsStore()
        self.settingsStore = settings

        let soundPlayer = SoundPlayer(settings: settings)
        let manager = SessionManager(adaptors: adaptors, soundPlayer: soundPlayer)
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
        Task { await claudeCodeAdaptor?.stopMonitoring() }
    }
}
