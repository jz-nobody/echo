import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: WindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        windowController = WindowController()
        windowController?.showCompactBar()
    }
}
