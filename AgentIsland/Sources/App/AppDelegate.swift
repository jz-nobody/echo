import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: WindowController?
    private var sessionManager: SessionManager?
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

        let manager = SessionManager(adaptors: adaptors)
        manager.startPolling()

        self.sessionManager = manager
        windowController = WindowController(sessionManager: manager)
        windowController?.showCompactBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { await claudeCodeAdaptor?.stopMonitoring() }
    }
}
