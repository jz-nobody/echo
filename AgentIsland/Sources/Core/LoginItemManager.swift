import ServiceManagement

@MainActor
final class LoginItemManager: LoginItemManaging {
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[AgentIsland] Login item %@: %@", enabled ? "register" : "unregister", "\(error)")
        }
    }
}
