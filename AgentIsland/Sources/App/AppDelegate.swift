import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: WindowController?
    private var sessionManager: SessionManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let mcpClient = MCPClient(baseURL: URL(string: "http://127.0.0.1:52345")!)
        let adaptor = QoderWorkAdaptor(client: mcpClient)
        let manager = SessionManager(adaptors: [adaptor])
        manager.startPolling()

        self.sessionManager = manager
        windowController = WindowController(sessionManager: manager)
        windowController?.showCompactBar()
    }
}
