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
    let idlePollInterval: TimeInterval
    let retryPolicy: RetryPolicy
    private let settingsStore: SettingsStore
    private let soundPlayer: (any SoundPlayable)?
    private let eventDetector = SessionEventDetector()
    private var idleTimers: [String: Date] = [:]

    var aggregateStatus: SessionStatus {
        SessionStatus.highest(sessions.map(\.status))
    }

    var totalConfirmationCount: Int {
        pendingConfirmations.values.reduce(0) { $0 + $1.count }
    }

    var activeSessionCount: Int {
        sessions.filter { $0.status != .idle && $0.status != .completed }.count
    }

    init(
        adaptors: [any AgentAdaptor],
        settingsStore: SettingsStore,
        pollInterval: TimeInterval = 1.0,
        idlePollInterval: TimeInterval = 5.0,
        retryPolicy: RetryPolicy = .standard,
        health: AdaptorHealth = AdaptorHealth(),
        soundPlayer: (any SoundPlayable)? = nil
    ) {
        self.adaptors = adaptors
        self.settingsStore = settingsStore
        self.pollInterval = pollInterval
        self.idlePollInterval = idlePollInterval
        self.retryPolicy = retryPolicy
        self.health = health
        self.soundPlayer = soundPlayer
    }

    private var confirmationObserver: NSObjectProtocol?
    private var statusObserver: NSObjectProtocol?

    func startPolling() {
        guard pollTask == nil else { return }
        isPolling = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                let interval = (self?.activeSessionCount ?? 0) > 0
                    ? (self?.pollInterval ?? 1)
                    : (self?.idlePollInterval ?? 5)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
        confirmationObserver = NotificationCenter.default.addObserver(
            forName: ClaudeCodeAdaptor.confirmationReceivedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pollOnce()
            }
        }
        statusObserver = NotificationCenter.default.addObserver(
            forName: ClaudeCodeAdaptor.statusChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.applyHookStatus(from: notification)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
        if let observer = confirmationObserver {
            NotificationCenter.default.removeObserver(observer)
            confirmationObserver = nil
        }
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
            statusObserver = nil
        }
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

    func revokeAutoApprove(session: AgentSession) async {
        for adaptor in adaptors where adaptor.agentType == session.agentType {
            await adaptor.revokeAutoApprove(session: session)
        }
        await pollOnce()
    }

    private func applyHookStatus(from notification: Notification) {
        guard let info = notification.userInfo,
              let sessionId = info["sessionId"] as? String,
              let status = info["status"] as? SessionStatus else {
            DebugLog.log("APPLY-HOOK: GUARD FAILED - info=\(notification.userInfo.debugDescription)")
            return
        }
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            let prev = sessions[idx].status
            sessions[idx].status = status
            DebugLog.log("APPLY-HOOK: session=\(sessionId.prefix(8)) \(prev.displayText)→\(status.displayText) idx=\(idx)")
            playTransitionSound(from: prev, to: status)
        } else {
            DebugLog.log("APPLY-HOOK: session=\(sessionId.prefix(8)) NOT FOUND in sessions (count=\(sessions.count))")
        }
        if status != .waitingConfirmation && pendingConfirmations[sessionId] != nil {
            pendingConfirmations.removeValue(forKey: sessionId)
        }
    }

    private func playTransitionSound(from prev: SessionStatus, to status: SessionStatus) {
        let event: SoundEvent?
        if prev == .compacting && status != .compacting {
            event = .compactingCompleted
        } else if prev != .waitingConfirmation && status == .waitingConfirmation {
            event = .askingUser
        } else if prev.isActive && (status == .completed || status == .idle) {
            event = .runningCompleted
        } else {
            event = nil
        }
        if let event { soundPlayer?.play(event) }
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
