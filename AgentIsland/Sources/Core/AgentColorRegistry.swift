import SwiftUI

@MainActor
final class AgentColorRegistry {
    static let shared = AgentColorRegistry()

    private var customAssignments: [String: Int] = [:]
    private var nextPaletteIndex = 0

    func label(for type: AgentType) -> String {
        switch type {
        case .qoderWork: "Qoder"
        case .claudeCode: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .qoder: "Qoder"
        case .custom(let name): name.prefix(1).uppercased() + name.dropFirst()
        }
    }

    func color(for type: AgentType) -> Color {
        switch type {
        case .qoderWork: DesignTokens.tagQoderWork
        case .claudeCode: DesignTokens.tagClaude
        case .codex: DesignTokens.tagCodex
        case .qoder: DesignTokens.tagQoder
        case .gemini: DesignTokens.tagGemini
        case .custom(let name): dynamicColor(for: name)
        }
    }

    private func dynamicColor(for name: String) -> Color {
        let palette = DesignTokens.dynamicPalette
        if let index = customAssignments[name] {
            return palette[index % palette.count]
        }
        let index = nextPaletteIndex
        customAssignments[name] = index
        nextPaletteIndex += 1
        return palette[index % palette.count]
    }
}
