import Foundation

actor BridgeServer {

    static let confirmationReceivedNotification = Notification.Name("AgentIsland.confirmationReceived")
    static let statusChangedNotification = Notification.Name("AgentIsland.statusChanged")
    static let sessionVisibilityTimeout: TimeInterval = 172800

    // Agent registry
    let agentConfigs: [String: AgentConfig]
    var agentServers: [String: IPCServer] = [:]

    // Sessions — keyed by internal ID (agentType-hookSessionId)
    var sessions: [String: AgentSession] = [:]
    var sessionStates: [String: SessionState] = [:]

    // Confirmations
    var pendingConfirmations: [String: PendingConfirmation] = [:]
    var confirmationToSession: [String: String] = [:]
    var responseCallbacks: [String: @Sendable (HookResponse) -> Void] = [:]
    var questionInputs: [String: [String: AnyCodable]] = [:]
    var clientToConfirmation: [UUID: String] = [:]

    // Activity
    var lastActivityDates: [String: Date] = [:]

    // Claude-specific
    var sessionWatcher: SessionFileWatcher?
    var sessionFiles: [String: ClaudeSessionFile] = [:]
    var revokedAutoApprove: Set<String> = []
    var localAutoApprove: Set<String> = []
    var cachedTodos: [String: [TodoItem]] = [:]

    // QoderWork-specific
    var sessionClientPIDs: [String: pid_t] = [:]
    var backgroundSessionIds: Set<String> = []
    var activeSubagents: [String: [SubagentInfo]] = [:]
    var transcriptPaths: [String: String] = [:]
    var qoderWorkChatIds: [String: String] = [:]
    var chatToWorkspace: [String: String] = [:]

    // Config
    let confirmationTimeout: TimeInterval

    var claudeSessionsPath: String {
        guard let config = agentConfigs["claude"] else {
            return NSHomeDirectory() + "/.claude/sessions"
        }
        return (config.hookSettingsPath as NSString)
            .deletingLastPathComponent + "/sessions"
    }

    var qoderWorkProjectsPath: String {
        guard let config = agentConfigs["qoderwork"] else {
            return NSHomeDirectory() + "/.qoderwork/projects"
        }
        return (config.hookSettingsPath as NSString)
            .deletingLastPathComponent + "/projects"
    }

    init(
        configs: [AgentConfig] = AgentConfig.allDefaults,
        confirmationTimeout: TimeInterval = 86400
    ) throws {
        self.confirmationTimeout = confirmationTimeout

        var configMap: [String: AgentConfig] = [:]
        for config in configs {
            configMap[config.tag] = config
        }
        self.agentConfigs = configMap

        let fm = FileManager.default
        for config in configs {
            if config.requiresExistingDir {
                let dir = (config.hookSettingsPath as NSString).deletingLastPathComponent
                guard fm.fileExists(atPath: dir) else { continue }
            }
            let server = try IPCServer(socketPath: config.socketPath, tag: config.tag)
            agentServers[config.tag] = server
        }
    }

    func start() {
        for (_, server) in agentServers {
            server.delegate = self
            server.start()
        }
        startClaudeSessionWatcher()
    }

    func stop() {
        for (_, server) in agentServers {
            server.stop()
        }
        sessionWatcher?.stop()
        sessionWatcher = nil
    }

    // MARK: - Public API

    func discoverAllSessions() -> [AgentSession] {
        cleanupStaleConfirmations()

        for (_, config) in agentConfigs {
            if let timeout = config.idleTimeout {
                cleanupIdleSessions(agentType: config.agentType, timeout: timeout)
            }
        }

        cleanupQoderWorkDeadSessions()
        discoverQoderWorkSessions()
        enrichAllQoderWorkTranscripts()
        deduplicateQoderWorkByTitle()
        refreshClaudeConversationData()

        let now = Date()
        return sessions.values
            .filter { !backgroundSessionIds.contains($0.id) }
            .filter { session in
                let lastActivity = lastActivityDates[session.id] ?? session.lastUpdate
                return now.timeIntervalSince(lastActivity) < Self.sessionVisibilityTimeout
            }
            .sorted { a, b in
                let aTime = lastActivityDates[a.id] ?? a.lastUpdate
                let bTime = lastActivityDates[b.id] ?? b.lastUpdate
                return aTime > bTime
            }
    }

    func getAllPendingConfirmations() -> [String: [PendingConfirmation]] {
        var grouped: [String: [PendingConfirmation]] = [:]
        for (confId, conf) in pendingConfirmations {
            guard let sessionId = confirmationToSession[confId] else { continue }
            grouped[sessionId, default: []].append(conf)
        }
        return grouped
    }

    func revokeAutoApprove(sessionId: String) {
        revokedAutoApprove.insert(sessionId)
        localAutoApprove.remove(sessionId)
        sessions[sessionId]?.permissionMode = nil
    }


    // MARK: - Internal Helpers

    func internalSessionId(agentType: AgentType, hookSessionId: String) -> String {
        "\(agentType)-\(hookSessionId)"
    }

    func ensureSessionExists(
        id: String, agentType: AgentType, title: String, cwd: String? = nil
    ) {
        guard sessions[id] == nil else { return }
        sessions[id] = AgentSession(
            id: id, agentType: agentType, title: title,
            status: .idle, startTime: Date(), lastUpdate: Date(),
            terminalInfo: nil, currentToolCall: nil
        )
    }

    func recordActivity(sessionId: String) {
        lastActivityDates[sessionId] = Date()
    }

    func applyEvent(_ event: SessionEvent, sessionId: String) {
        var state = sessionStates[sessionId] ?? SessionState()
        let previousStatus = state.status
        state.apply(event)
        sessionStates[sessionId] = state

        if var session = sessions[sessionId] {
            session.status = state.status
            session.lastUpdate = Date()
            sessions[sessionId] = session
        }

        NotificationCenter.default.post(
            name: Self.statusChangedNotification, object: nil,
            userInfo: [
                "sessionId": sessionId,
                "status": state.status,
                "previousStatus": previousStatus,
            ]
        )
    }

    func removeSession(_ id: String) {
        sessions.removeValue(forKey: id)
        sessionStates.removeValue(forKey: id)
        lastActivityDates.removeValue(forKey: id)

        let confsForSession = confirmationToSession.filter { $0.value == id }.map(\.key)
        for confId in confsForSession {
            responseCallbacks[confId]?(HookResponse(decision: "ask", reason: "Session ended"))
            responseCallbacks.removeValue(forKey: confId)
            questionInputs.removeValue(forKey: confId)
            pendingConfirmations.removeValue(forKey: confId)
            confirmationToSession.removeValue(forKey: confId)
            if let clientEntry = clientToConfirmation.first(where: { $0.value == confId }) {
                clientToConfirmation.removeValue(forKey: clientEntry.key)
            }
        }
    }
}
