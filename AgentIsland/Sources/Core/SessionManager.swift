import Foundation

@MainActor
@Observable
final class SessionManager {
    private(set) var sessions: [AgentSession] = []
    private(set) var pendingConfirmations: [String: [PendingConfirmation]] = [:]
    private(set) var isPolling = false
    let health: AdaptorHealth

    private let bridgeServer: BridgeServer
    private var pollTask: Task<Void, Never>?
    let pollInterval: TimeInterval
    let idlePollInterval: TimeInterval
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
        bridgeServer: BridgeServer,
        settingsStore: SettingsStore,
        pollInterval: TimeInterval = 1.0,
        idlePollInterval: TimeInterval = 5.0,
        health: AdaptorHealth = AdaptorHealth(),
        soundPlayer: (any SoundPlayable)? = nil
    ) {
        self.bridgeServer = bridgeServer
        self.settingsStore = settingsStore
        self.pollInterval = pollInterval
        self.idlePollInterval = idlePollInterval
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
            forName: BridgeServer.confirmationReceivedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pollOnce()
            }
        }
        statusObserver = NotificationCenter.default.addObserver(
            forName: BridgeServer.statusChangedNotification,
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
        try await bridgeServer.respond(confirmationId: confirmation.id, response: response)
        switch response {
        case .allow, .select, .multiSelect, .freeText:
            soundPlayer?.play(.confirmationApproved)
        case .deny:
            soundPlayer?.play(.confirmationDenied)
        }
        await pollOnce()
    }

    func revokeAutoApprove(session: AgentSession) async {
        await bridgeServer.revokeAutoApprove(sessionId: session.id)
        await pollOnce()
    }

    private func applyHookStatus(from notification: Notification) {
        guard let info = notification.userInfo,
              let sessionId = info["sessionId"] as? String,
              let status = info["status"] as? SessionStatus else { return }

        let prev: SessionStatus
        if let notifiedPrev = info["previousStatus"] as? SessionStatus {
            prev = notifiedPrev
        } else if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            prev = sessions[idx].status
        } else {
            prev = .idle
        }

        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].status = status
        }

        playTransitionSound(from: prev, to: status)

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
        if let event {
            NSLog("[AgentIsland] Sound: \(prev.displayText) → \(status.displayText) → play \(event.rawValue)")
            soundPlayer?.play(event)
        }
    }

    func pollOnce() async {
        let discovered = await bridgeServer.discoverAllSessions()
        let confs = await bridgeServer.getAllPendingConfirmations()

        let filteredSessions = SessionFilter.apply(to: discovered, settings: settingsStore)

        let events = eventDetector.detect(
            sessions: filteredSessions,
            confirmations: confs,
            health: health
        )
        for event in events {
            soundPlayer?.play(event)
        }

        mergeSessions(filteredSessions, confirmations: confs)
        checkIdleReminders(sessions: filteredSessions)
    }

    private func mergeSessions(
        _ discovered: [AgentSession],
        confirmations: [String: [PendingConfirmation]]
    ) {
        let discoveredMap = Dictionary(uniqueKeysWithValues: discovered.map { ($0.id, $0) })
        let discoveredIDs = Set(discovered.map(\.id))

        sessions.removeAll { !discoveredIDs.contains($0.id) }

        for i in sessions.indices {
            guard let disc = discoveredMap[sessions[i].id] else { continue }
            let hookStatus = sessions[i].status
            sessions[i] = disc
            if hookStatus.priority > disc.status.priority {
                sessions[i].status = hookStatus
            }
        }

        let existingIDs = Set(sessions.map(\.id))
        for id in discoveredIDs.subtracting(existingIDs) {
            if let session = discoveredMap[id] {
                sessions.append(session)
            }
        }

        self.pendingConfirmations = confirmations
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
