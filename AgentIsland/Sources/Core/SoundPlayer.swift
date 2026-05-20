import AppKit

@MainActor
final class SoundPlayer: SoundPlayable {
    private let settings: SettingsStore

    private static let soundMapping: [String: NSSound.Name] = [
        "default": "Tink",
        "chime": "Glass",
        "alert": "Funk",
        "bubble": "Pop",
    ]

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func play(_ event: SoundEvent) {
        guard settings.soundEnabled else { return }

        let name = event.soundName(from: settings)
        guard name != "none" else { return }

        guard let soundName = Self.soundMapping[name] else {
            NSLog("[AgentIsland] Unknown sound name: \(name)")
            return
        }

        guard let sound = NSSound(named: soundName) else {
            NSLog("[AgentIsland] System sound not found: \(soundName)")
            return
        }

        sound.volume = settings.soundVolume
        sound.play()
    }
}
