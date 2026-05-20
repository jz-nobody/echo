import Foundation
import Testing
@testable import AgentIsland

@Suite("LoginItem Tests")
struct LoginItemTests {

    @MainActor
    private func makeStore() -> (SettingsStore, MockLoginItemManager) {
        let suite = "test-settings-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SettingsStore(defaults: defaults)
        let mock = MockLoginItemManager()
        store.loginItemManager = mock
        mock.reset()
        return (store, mock)
    }

    @MainActor
    @Test("setting loginItemManager syncs current launchAtLogin value")
    func settingManagerSyncs() {
        let suite = "test-settings-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SettingsStore(defaults: defaults)
        let mock = MockLoginItemManager()
        store.loginItemManager = mock
        #expect(mock.calls == [true])
    }

    @MainActor
    @Test("setting loginItemManager syncs false when launchAtLogin is false")
    func settingManagerSyncsFalse() {
        let suite = "test-settings-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "ai.launchAtLogin")
        let store = SettingsStore(defaults: defaults)
        let mock = MockLoginItemManager()
        store.loginItemManager = mock
        #expect(mock.calls == [false])
    }

    @MainActor
    @Test("toggling launchAtLogin calls loginItemManager")
    func toggleCallsManager() {
        let (store, mock) = makeStore()
        store.launchAtLogin = false
        #expect(mock.calls == [false])
        store.launchAtLogin = true
        #expect(mock.calls == [false, true])
    }

    @MainActor
    @Test("resetToDefaults calls loginItemManager with default value")
    func resetCallsManager() {
        let (store, mock) = makeStore()
        store.launchAtLogin = false
        mock.reset()
        store.resetToDefaults()
        #expect(mock.calls == [true])
    }

    @MainActor
    @Test("no loginItemManager does not crash")
    func nilManagerSafe() {
        let suite = "test-settings-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SettingsStore(defaults: defaults)
        store.launchAtLogin = false
        store.launchAtLogin = true
    }
}
