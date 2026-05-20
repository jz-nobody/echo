import Foundation
import Testing
@testable import AgentIsland

@Suite("SettingsStore Tests")
struct SettingsStoreTests {

    @MainActor
    private func makeStore() -> (SettingsStore, UserDefaults) {
        let suite = "test-settings-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SettingsStore(defaults: defaults)
        return (store, defaults)
    }

    @MainActor
    @Test("default values match design spec")
    func defaultValues() {
        let (store, _) = makeStore()
        #expect(store.launchAtLogin == true)
        #expect(store.hoverToExpand == true)
        #expect(store.hoverDelay == 0.15)
        #expect(store.smartSuppression == true)
        #expect(store.hideInFullscreen == true)
        #expect(store.hideWhenNoActiveSessions == false)
        #expect(store.autoCollapseOnMouseExit == true)
        #expect(store.autoReminderDuration == 5.0)
        #expect(store.dismissOnClickOutside == false)
        #expect(store.agentTeamAutoExpand == false)
        #expect(store.idleCleanupInterval == 7200)
        #expect(store.disableClickToJump == false)
        #expect(store.displayMode == .detailed)
        #expect(store.monitorSelection == 0)
        #expect(store.panelFontSize == 11)
        #expect(store.completionCardHeight == 90)
        #expect(store.maxPanelHeight == 560)
        #expect(store.maxPanelWidth == 640)
        #expect(store.notchWidthOffset == 0)
        #expect(store.notchHeightOffset == 0)
        #expect(store.showSubAgentDetails == false)
        #expect(store.soundEnabled == true)
        #expect(store.soundVolume == 0.3)
        #expect(store.soundSessionStart == "default")
        #expect(store.soundError == "default")
    }

    @MainActor
    @Test("persist writes to UserDefaults")
    func persistWrites() {
        let (store, defaults) = makeStore()
        store.hoverDelay = 0.5
        store.soundEnabled = false
        store.maxPanelHeight = 400
        #expect(defaults.double(forKey: "ai.hoverDelay") == 0.5)
        #expect(defaults.bool(forKey: "ai.soundEnabled") == false)
        #expect(defaults.double(forKey: "ai.maxPanelHeight") == 400)
    }

    @MainActor
    @Test("load reads from UserDefaults")
    func loadReads() {
        let suite = "test-settings-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(0.8, forKey: "ai.hoverDelay")
        defaults.set(false, forKey: "ai.launchAtLogin")
        defaults.set("chime", forKey: "ai.soundSessionStart")
        defaults.set("compact", forKey: "ai.displayMode")
        let store = SettingsStore(defaults: defaults)
        #expect(store.hoverDelay == 0.8)
        #expect(store.launchAtLogin == false)
        #expect(store.soundSessionStart == "chime")
        #expect(store.displayMode == .compact)
    }

    @MainActor
    @Test("resetToDefaults restores all")
    func resetToDefaults() {
        let (store, _) = makeStore()
        store.hoverDelay = 1.0
        store.soundEnabled = false
        store.displayMode = .compact
        store.maxPanelHeight = 999
        store.resetToDefaults()
        #expect(store.hoverDelay == 0.15)
        #expect(store.soundEnabled == true)
        #expect(store.displayMode == .detailed)
        #expect(store.maxPanelHeight == 560)
    }

    @MainActor
    @Test("round trip all properties")
    func roundTrip() {
        let suite = "test-settings-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let store1 = SettingsStore(defaults: defaults)
        store1.hoverDelay = 0.42
        store1.launchAtLogin = false
        store1.displayMode = .compact
        store1.panelFontSize = 14
        store1.soundVolume = 0.7
        store1.soundError = "bell"
        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.hoverDelay == 0.42)
        #expect(store2.launchAtLogin == false)
        #expect(store2.displayMode == .compact)
        #expect(store2.panelFontSize == 14)
        #expect(store2.soundVolume == 0.7)
        #expect(store2.soundError == "bell")
    }

    @MainActor
    @Test("isolated suites don't interfere")
    func isolatedSuites() {
        let defaults1 = UserDefaults(suiteName: "test-settings-\(UUID())")!
        let defaults2 = UserDefaults(suiteName: "test-settings-\(UUID())")!
        let store1 = SettingsStore(defaults: defaults1)
        let store2 = SettingsStore(defaults: defaults2)
        store1.hoverDelay = 99
        #expect(store2.hoverDelay == 0.15)
    }

    @MainActor
    @Test("displayMode codable")
    func displayModeCodable() throws {
        let data = try JSONEncoder().encode(DisplayMode.compact)
        let decoded = try JSONDecoder().decode(DisplayMode.self, from: data)
        #expect(decoded == .compact)
        #expect(DisplayMode.allCases.count == 2)
    }

    @MainActor
    @Test("panelState reads live hoverDelay from settingsStore")
    func panelStateReadsLiveHoverDelay() {
        let (store, _) = makeStore()
        let panelState = PanelState(settingsStore: store)
        #expect(panelState.settingsStore.hoverDelay == 0.15)
        store.hoverDelay = 0.5
        #expect(panelState.settingsStore.hoverDelay == 0.5)
    }
}
