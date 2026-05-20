import Testing
import Foundation
@testable import AgentIsland

@Suite("SoundEvent Tests")
struct SoundEventTests {

    @Test("SoundEvent has 8 cases")
    func caseCount() {
        #expect(SoundEvent.allCases.count == 8)
    }

    @Test("soundName returns correct setting per event")
    @MainActor
    func soundNameMapping() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "test-sound-\(UUID())")!)
        store.soundSessionStart = "chime"
        store.soundSessionEnd = "alert"
        store.soundConfirmationArrived = "bubble"
        store.soundConfirmationApproved = "none"
        store.soundConfirmationDenied = "default"
        store.soundError = "alert"
        store.soundReconnected = "chime"
        store.soundIdleReminder = "bubble"

        #expect(SoundEvent.sessionStart.soundName(from: store) == "chime")
        #expect(SoundEvent.sessionEnd.soundName(from: store) == "alert")
        #expect(SoundEvent.confirmationArrived.soundName(from: store) == "bubble")
        #expect(SoundEvent.confirmationApproved.soundName(from: store) == "none")
        #expect(SoundEvent.confirmationDenied.soundName(from: store) == "default")
        #expect(SoundEvent.error.soundName(from: store) == "alert")
        #expect(SoundEvent.reconnected.soundName(from: store) == "chime")
        #expect(SoundEvent.idleReminder.soundName(from: store) == "bubble")
    }

    @Test("soundName reflects live setting changes")
    @MainActor
    func soundNameLiveChanges() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "test-sound-\(UUID())")!)

        #expect(SoundEvent.sessionStart.soundName(from: store) == "default")

        store.soundSessionStart = "alert"
        #expect(SoundEvent.sessionStart.soundName(from: store) == "alert")

        store.soundSessionStart = "none"
        #expect(SoundEvent.sessionStart.soundName(from: store) == "none")
    }
}
