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

    private static let customSoundFiles: [SoundEvent: String] = [
        .compactingCompleted: "压缩完成",
        .askingUser: "询问用户",
        .runningCompleted: "开始运行",
    ]

    private var lastPlayed: [SoundEvent: Date] = [:]
    private static let dedupeInterval: TimeInterval = 3

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func play(_ event: SoundEvent) {
        guard settings.soundEnabled else { return }

        if let last = lastPlayed[event],
           Date().timeIntervalSince(last) < Self.dedupeInterval {
            return
        }
        lastPlayed[event] = Date()

        if let fileName = Self.customSoundFiles[event] {
            playCustom(fileName)
            return
        }

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

    private func playCustom(_ fileName: String) {
        guard let url = Self.soundsDirectory?.appendingPathComponent("\(fileName).wav"),
              FileManager.default.fileExists(atPath: url.path) else {
            NSLog("[AgentIsland] Custom sound not found: %@.wav", fileName)
            return
        }

        guard let sound = NSSound(contentsOf: url, byReference: true) else {
            NSLog("[AgentIsland] Failed to load sound: %@", url.path)
            return
        }

        sound.volume = settings.soundVolume
        sound.play()
    }

    private static let soundsDirectory: URL? = {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Sounds"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        let execURL = (Bundle.main.executableURL ?? URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]))
            .resolvingSymlinksInPath()
        let projectRoot = execURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return projectRoot.appendingPathComponent("Resources/Sounds")
    }()
}
