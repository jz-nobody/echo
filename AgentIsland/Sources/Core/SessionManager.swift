import Foundation

@MainActor
@Observable
final class SessionManager {
    private(set) var sessions: [AgentSession] = []
    private(set) var pendingConfirmations: [String: [PendingConfirmation]] = [:]
    private(set) var isPolling = false
    let health: AdaptorHealth

    private let adaptors: [any AgentAdaptor]
    private var pollTask: Task<Void, Never>?
    let pollInterval: TimeInterval
    let retryPolicy: RetryPolicy
    private let settingsStore: SettingsStore
    private let soundPlayer: (any SoundPlayable)?
    private let eventDetector = SessionEventDetector()
    private var idleTimers: [String: Date] = [:]

    var aggregateStatus: SessionStatus {
        SessionStatus.highest(sessions.map(\.status))
    }

    var activeSessionCount: Int {
        sessions.filter { $0.status != .idle && $0.status != .completed }.count
    }

    init(
        adaptors: [any AgentAdaptor],
        settingsStore: SettingsStore,
        pollInterval: TimeInterval = 2.0,
        retryPolicy: RetryPolicy = .standard,
        health: AdaptorHealth = AdaptorHealth(),
        soundPlayer: (any SoundPlayable)? = nil
    ) {
        self.adaptors = adaptors
        self.settingsStore = settingsStore
        self.pollInterval = pollInterval
        self.retryPolicy = retryPolicy
        self.health = health
        self.soundPlayer = soundPlayer
    }

    func startPolling() {
        guard pollTask == nil else { return }
        isPolling = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(for: .seconds(self?.pollInterval ?? 2))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
    }

    func respond(
        session: AgentSession,
        confirmation: PendingConfirmation,
        response: ConfirmationResponse
    ) async throws {
        for adaptor in adaptors where adaptor.agentType == session.agentType {
            try await adaptor.respond(session: session, confirmation: confirmation, response: response)
        }
        switch response {
        case .allow, .select:
            soundPlayer?.play(.confirmationApproved)
        case .deny:
            soundPlayer?.play(.confirmationDenied)
        }
        await pollOnce()
    }

    func pollOnce() async {
        var newSessions: [AgentSession] = []
        var newConfirmations: [String: [PendingConfirmation]] = [:]

        for adaptor in adaptors {
            let type = adaptor.agentType
            guard health.shouldPoll(for: type) else { continue }

            guard await adaptor.isAvailable else {
                health.recordFailure(for: type)
                continue
            }

            do {
                let discovered = try await retryPolicy.execute {
                    try await adaptor.discoverSessions()
                }
                health.recordSuccess(for: type)

                for var session in discovered {
                    if let status = try? await adaptor.getStatus(session: session) {
                        session.status = status
                    }
                    if session.status == .waitingConfirmation {
                        if let confs = try? await adaptor.getPendingConfirmations(session: session) {
                            newConfirmations[session.id] = confs
                        }
                    }
                    newSessions.append(session)
                }
            } catch {
                health.recordFailure(for: type)
                continue
            }
        }

        let filteredSessions = SessionFilter.apply(to: newSessions, settings: settingsStore)
        self.sessions = filteredSessions
        self.pendingConfirmations = newConfirmations

        let events = eventDetector.detect(
            sessions: newSessions,
            confirmations: newConfirmations,
            health: health
        )
        for event in events {
            soundPlayer?.play(event)
        }

        checkIdleReminders(sessions: newSessions)
    }

    private func checkIdleReminders(sessions: [AgentSession]) {
        let idleSessions = sessions.filter { $0.status == .idle }
        let activeIDs = Set(sessions.map(\.id))

        idleTimers = idleTimers.filter { id, _ in
            activeIDs.contains(id) && idleSessions.contains(where: { $0.id == id })
        }

        for session in idleSessions where idleTimers[session.id] == nil {
            idleTimers[session.id] = Date()
        }

        let threshold: TimeInterval = 300
        for (_, idleSince) in idleTimers {
            if Date().timeIntervalSince(idleSince) >= threshold {
                soundPlayer?.play(.idleReminder)
                idleTimers = idleTimers.mapValues { _ in Date() }
                break
            }
        }
    }
}
