import Foundation

enum AdaptorConnectionState: Sendable, Equatable {
    case online
    case retrying(attempt: Int)
    case offline
}

@MainActor
@Observable
final class AdaptorHealth {
    private(set) var states: [AgentType: AdaptorConnectionState] = [:]
    private var failureCounts: [AgentType: Int] = [:]
    private var offlineSince: [AgentType: Date] = [:]

    let maxFailures: Int
    let offlinePauseDuration: TimeInterval

    nonisolated init(maxFailures: Int = 3, offlinePauseDuration: TimeInterval = 30.0) {
        self.maxFailures = maxFailures
        self.offlinePauseDuration = offlinePauseDuration
    }

    func recordSuccess(for type: AgentType) {
        states[type] = .online
        failureCounts[type] = 0
        offlineSince.removeValue(forKey: type)
    }

    @discardableResult
    func recordFailure(for type: AgentType) -> AdaptorConnectionState {
        let count = (failureCounts[type] ?? 0) + 1
        failureCounts[type] = count

        if count >= maxFailures {
            states[type] = .offline
            if offlineSince[type] == nil {
                offlineSince[type] = Date()
            }
        } else {
            states[type] = .retrying(attempt: count)
        }
        return states[type] ?? .online
    }

    func shouldPoll(for type: AgentType) -> Bool {
        guard let state = states[type] else { return true }
        switch state {
        case .online, .retrying:
            return true
        case .offline:
            guard let since = offlineSince[type] else { return true }
            if Date().timeIntervalSince(since) >= offlinePauseDuration {
                failureCounts[type] = 0
                states[type] = .retrying(attempt: 0)
                offlineSince.removeValue(forKey: type)
                return true
            }
            return false
        }
    }

    var isAnyOffline: Bool {
        states.values.contains(.offline)
    }
}
