import Foundation

enum SessionFilter {
    static let builtInPatterns = [
        "Memory Consolidation",
        "claude-mem",
        "background sync",
    ]

    @MainActor
    static func apply(
        to sessions: [AgentSession],
        settings: SettingsStore
    ) -> [AgentSession] {
        sessions.filter { !shouldFilter($0, settings: settings) }
    }

    @MainActor
    static func shouldFilter(
        _ session: AgentSession,
        settings: SettingsStore
    ) -> Bool {
        if settings.enableBuiltInFilters {
            for pattern in builtInPatterns {
                if session.title.localizedCaseInsensitiveContains(pattern) {
                    return true
                }
            }
        }
        for keyword in settings.filterKeywords {
            if !keyword.isEmpty &&
               session.title.localizedCaseInsensitiveContains(keyword) {
                return true
            }
        }
        return false
    }
}
