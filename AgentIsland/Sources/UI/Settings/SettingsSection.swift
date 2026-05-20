import SwiftUI

enum SettingsGroup: String, CaseIterable {
    case main
    case advanced
    case app
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case integration
    case notification
    case display
    case sound
    case usage
    case shortcuts
    case ssh
    case labs
    case passport
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .integration: "集成"
        case .notification: "通知"
        case .display: "显示"
        case .sound: "声音"
        case .usage: "用量"
        case .shortcuts: "快捷键"
        case .ssh: "SSH 远程"
        case .labs: "实验室"
        case .passport: "通行证"
        case .about: "关于"
        }
    }

    var icon: String {
        switch self {
        case .general: "gear.circle.fill"
        case .integration: "square.fill"
        case .notification: "bell.fill"
        case .display: "textformat.size"
        case .sound: "speaker.wave.2.fill"
        case .usage: "gauge.medium"
        case .shortcuts: "keyboard.fill"
        case .ssh: "globe"
        case .labs: "exclamationmark.triangle.fill"
        case .passport: "shield.fill"
        case .about: "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general: .gray
        case .integration: .blue
        case .notification: .red
        case .display: .blue
        case .sound: .pink
        case .usage: .red
        case .shortcuts: .gray
        case .ssh: .blue
        case .labs: .orange
        case .passport: .blue
        case .about: .blue
        }
    }

    var group: SettingsGroup {
        switch self {
        case .general, .integration, .notification, .display, .sound, .usage:
            .main
        case .shortcuts, .ssh, .labs:
            .advanced
        case .passport, .about:
            .app
        }
    }

    static func sections(in group: SettingsGroup) -> [SettingsSection] {
        allCases.filter { $0.group == group }
    }
}
