import Foundation

enum SoundEvent: String, CaseIterable, Sendable {
    case sessionStart
    case sessionEnd
    case confirmationArrived
    case confirmationApproved
    case confirmationDenied
    case error
    case reconnected
    case idleReminder
    case compactingCompleted
    case askingUser
    case runningCompleted

    @MainActor
    func soundName(from store: SettingsStore) -> String {
        switch self {
        case .sessionStart:        store.soundSessionStart
        case .sessionEnd:          store.soundSessionEnd
        case .confirmationArrived: store.soundConfirmationArrived
        case .confirmationApproved: store.soundConfirmationApproved
        case .confirmationDenied:  store.soundConfirmationDenied
        case .error:               store.soundError
        case .reconnected:         store.soundReconnected
        case .idleReminder:        store.soundIdleReminder
        case .compactingCompleted, .askingUser, .runningCompleted: "custom"
        }
    }
}
