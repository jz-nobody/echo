import Foundation

enum SuppressionEvaluator {

    @MainActor
    static func shouldSuppress(
        settings: SettingsStore,
        monitor: any FrontmostAppProviding,
        sessions: [AgentSession],
        confirmations: [String: [PendingConfirmation]]
    ) -> Bool {
        guard settings.smartSuppression else { return false }
        let sessionsWithConfirmations = sessions.filter {
            confirmations[$0.id]?.isEmpty == false
        }
        return sessionsWithConfirmations.contains { session in
            monitor.isTerminalOfSession(session)
        }
    }
}
