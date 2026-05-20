@testable import AgentIsland

@MainActor
final class MockSoundPlayer: SoundPlayable {
    private(set) var playedEvents: [SoundEvent] = []

    func play(_ event: SoundEvent) {
        playedEvents.append(event)
    }

    func reset() {
        playedEvents = []
    }
}
