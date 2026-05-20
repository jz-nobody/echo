import Foundation

@MainActor
final class SessionEventDetector {

    struct Snapshot {
        let sessionIDs: Set<String>
        let sessionStatuses: [String: SessionStatus]
        let confirmationIDs: Set<String>
        let adaptorOnline: Set<AgentType>
    }

    private var previousSnapshot: Snapshot?

    func detect(
        sessions: [AgentSession],
        confirmations: [String: [PendingConfirmation]],
        health: AdaptorHealth
    ) -> [SoundEvent] {
        let snapshot = makeSnapshot(
            sessions: sessions,
            confirmations: confirmations,
            health: health
        )

        defer { previousSnapshot = snapshot }

        guard let previous = previousSnapshot else {
            return []
        }

        var events: [SoundEvent] = []

        detectSessionStart(previous: previous, current: snapshot, into: &events)
        detectSessionEnd(previous: previous, current: snapshot, into: &events)
        detectConfirmationArrived(previous: previous, current: snapshot, into: &events)
        detectError(previous: previous, current: snapshot, into: &events)
        detectReconnected(previous: previous, current: snapshot, into: &events)

        return events
    }

    func reset() {
        previousSnapshot = nil
    }

    private func makeSnapshot(
        sessions: [AgentSession],
        confirmations: [String: [PendingConfirmation]],
        health: AdaptorHealth
    ) -> Snapshot {
        let sessionIDs = Set(sessions.map(\.id))
        var sessionStatuses: [String: SessionStatus] = [:]
        for session in sessions {
            sessionStatuses[session.id] = session.status
        }

        var confirmationIDs = Set<String>()
        for (_, confs) in confirmations {
            for conf in confs {
                confirmationIDs.insert(conf.id)
            }
        }

        var adaptorOnline = Set<AgentType>()
        for (type, state) in health.states {
            if state == .online {
                adaptorOnline.insert(type)
            }
        }

        return Snapshot(
            sessionIDs: sessionIDs,
            sessionStatuses: sessionStatuses,
            confirmationIDs: confirmationIDs,
            adaptorOnline: adaptorOnline
        )
    }

    private func detectSessionStart(
        previous: Snapshot,
        current: Snapshot,
        into events: inout [SoundEvent]
    ) {
        let newIDs = current.sessionIDs.subtracting(previous.sessionIDs)
        for id in newIDs {
            if let status = current.sessionStatuses[id],
               status != .idle, status != .completed {
                events.append(.sessionStart)
            }
        }
    }

    private func detectSessionEnd(
        previous: Snapshot,
        current: Snapshot,
        into events: inout [SoundEvent]
    ) {
        let goneIDs = previous.sessionIDs.subtracting(current.sessionIDs)
        if !goneIDs.isEmpty {
            events.append(.sessionEnd)
        }

        for id in previous.sessionIDs.intersection(current.sessionIDs) {
            let oldStatus = previous.sessionStatuses[id]
            let newStatus = current.sessionStatuses[id]
            if oldStatus != .completed, newStatus == .completed {
                events.append(.sessionEnd)
            }
        }
    }

    private func detectConfirmationArrived(
        previous: Snapshot,
        current: Snapshot,
        into events: inout [SoundEvent]
    ) {
        let newConfs = current.confirmationIDs.subtracting(previous.confirmationIDs)
        if !newConfs.isEmpty {
            events.append(.confirmationArrived)
        }
    }

    private func detectError(
        previous: Snapshot,
        current: Snapshot,
        into events: inout [SoundEvent]
    ) {
        for id in current.sessionIDs {
            guard let newStatus = current.sessionStatuses[id] else { continue }
            if case .error = newStatus {
                let oldStatus = previous.sessionStatuses[id]
                let wasError: Bool
                if let old = oldStatus, case .error = old {
                    wasError = true
                } else {
                    wasError = false
                }
                if !wasError {
                    events.append(.error)
                }
            }
        }
    }

    private func detectReconnected(
        previous: Snapshot,
        current: Snapshot,
        into events: inout [SoundEvent]
    ) {
        let reconnected = current.adaptorOnline.subtracting(previous.adaptorOnline)
        if !reconnected.isEmpty {
            events.append(.reconnected)
        }
    }
}
