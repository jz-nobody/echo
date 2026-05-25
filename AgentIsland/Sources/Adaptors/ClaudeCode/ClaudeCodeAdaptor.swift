import Foundation

actor ClaudeCodeAdaptor: AgentAdaptor, IPCServerDelegate {
    nonisolated let agentType: AgentType = .claudeCode

    private var activeSessions: [String: AgentSession] = [:]
    private var sessionFiles: [String: ClaudeSessionFile] = [:]
    private var sessionStates: [String: SessionState] = [:]
    private var pendingRequests: [String: [PendingConfirmation]] = [:]
    private var responseCallbacks: [String: @Sendable (HookResponse) -> Void] = [:]
    private var questionInputs: [String: [String: AnyCodable]] = [:]
    private var cachedTodos: [String: [TodoItem]] = [:]
    private var revokedAutoApprove: Set<String> = []
    private var sessionWatcher: SessionFileWatcher?
    private let ipcServer: IPCServer
    let sessionsDirectoryPath: String
    private let confirmationTimeout: TimeInterval

    init(
        sessionsDirectoryPath: String = NSHomeDirectory() + "/.claude/sessions",
        socketPath: String = IPCProtocol.socketPath,
        confirmationTimeout: TimeInterval = 86400
    ) throws {
        self.sessionsDirectoryPath = sessionsDirectoryPath
        self.confirmationTimeout = confirmationTimeout
        self.ipcServer = try IPCServer(socketPath: socketPath)
    }

    func startMonitoring() {
        ipcServer.delegate = self
        ipcServer.start()

        let watcher = SessionFileWatcher(directoryPath: sessionsDirectoryPath) { [weak self] files in
            guard let self else { return }
            Task { await self.updateSessions(files) }
        }
        self.sessionWatcher = watcher
        watcher.start()
    }

    func stopMonitoring() {
        ipcServer.stop()
        sessionWatcher?.stop()
        sessionWatcher = nil
    }

    // MARK: - AgentAdaptor

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: sessionsDirectoryPath)
    }

    func discoverSessions() async throws -> [AgentSession] {
        cleanupStaleConfirmations()
        if activeSessions.isEmpty, let watcher = sessionWatcher {
            let files = watcher.scanNow()
            for file in files {
                let session = SessionFileParser.toAgentSession(file)
                activeSessions[session.id] = session
                sessionFiles[session.id] = file
            }
        }
        refreshConversationData()
        return Array(activeSessions.values)
    }

    func getStatus(session: AgentSession) async throws -> SessionStatus {
        if let confs = pendingRequests[session.id], !confs.isEmpty {
            return .waitingConfirmation
        }
        if let state = sessionStates[session.id] {
            return state.status
        }
        return activeSessions[session.id]?.status ?? session.status
    }

    func getPendingConfirmations(session: AgentSession) async throws -> [PendingConfirmation] {
        pendingRequests[session.id] ?? []
    }

    func respond(
        session: AgentSession,
        confirmation: PendingConfirmation,
        response: ConfirmationResponse
    ) async throws {
        let hookResponse: HookResponse
        switch response {
        case .allow:
            hookResponse = HookResponse(decision: "allow", reason: nil)
        case .deny:
            hookResponse = HookResponse(decision: "deny", reason: "Denied via Agent Island")
        case .select(let optionId):
            if let originalInput = questionInputs[confirmation.id],
               let questionsRaw = originalInput["questions"]?.value as? [[String: Any]],
               let questionText = questionsRaw.first?["question"] as? String {
                hookResponse = .question(answers: [questionText: optionId], originalInput: originalInput)
            } else {
                hookResponse = HookResponse(decision: "allow", reason: nil)
            }
        }

        if let callback = responseCallbacks[confirmation.id] {
            callback(hookResponse)
        } else {
            NSLog("[AgentIsland] respond: no callback for \(confirmation.id) — bridge likely timed out")
        }
        responseCallbacks.removeValue(forKey: confirmation.id)
        questionInputs.removeValue(forKey: confirmation.id)
        pendingRequests[session.id]?.removeAll { $0.id == confirmation.id }
        if pendingRequests[session.id]?.isEmpty == true {
            pendingRequests.removeValue(forKey: session.id)
            let event: SessionEvent
            switch response {
            case .deny: event = .permissionDenied
            case .allow, .select: event = .permissionApproved
            }
            applyEvent(event, sessionId: session.id)
        }
    }

    func revokeAutoApprove(session: AgentSession) {
        revokedAutoApprove.insert(session.id)
        if var s = activeSessions[session.id] {
            s.permissionMode = nil
            activeSessions[session.id] = s
        }
    }

    // MARK: - IPCServerDelegate

    nonisolated func ipcServer(
        _ server: IPCServer,
        didReceive message: HookMessage,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        switch message.type {
        case "PermissionRequest":
            Task { await handlePermissionRequest(message, respond: respond) }
        default:
            Task { await handleStatusHook(message, respond: respond) }
        }
    }

    // MARK: - Internal

    static let confirmationReceivedNotification = Notification.Name("AgentIsland.confirmationReceived")
    static let statusChangedNotification = Notification.Name("AgentIsland.statusChanged")

    func handlePermissionRequest(
        _ message: HookMessage,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        let toolName = message.toolName ?? "Unknown"
        let toolInput = message.toolInput ?? [:]
        let confId = "\(message.sessionId)-\(toolName)-\(Int(Date().timeIntervalSince1970 * 1000))"

        if toolName == "AskUserQuestion", let choiceDetails = parseAskUserQuestion(toolInput) {
            let confirmation = PendingConfirmation(
                id: confId,
                type: .choice,
                title: choiceDetails.question,
                details: .choice(choiceDetails),
                timestamp: Date()
            )
            pendingRequests[message.sessionId, default: []].append(confirmation)
            responseCallbacks[confId] = respond
            questionInputs[confId] = toolInput
            applyEvent(.permissionRequest, sessionId: message.sessionId)
            NotificationCenter.default.post(name: Self.confirmationReceivedNotification, object: nil)
            return
        }

        let operation = summarizeToolInput(name: toolName, input: toolInput)
        let confirmation = PendingConfirmation(
            id: confId,
            type: .permission,
            title: operation,
            details: .permission(PermissionDetails(
                operation: operation,
                diff: buildDiff(from: toolInput),
                additions: 0,
                deletions: 0
            )),
            timestamp: Date()
        )
        pendingRequests[message.sessionId, default: []].append(confirmation)
        responseCallbacks[confId] = respond

        applyEvent(.permissionRequest, sessionId: message.sessionId)
        NotificationCenter.default.post(name: Self.confirmationReceivedNotification, object: nil)
    }

    func handleStatusHook(
        _ message: HookMessage,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        let event: SessionEvent
        switch message.type {
        case "PreToolUse":
            event = .preToolUse(toolName: message.toolName)
        case "PostToolUse", "PostToolUseFailure":
            event = .postToolUse
        case "UserPromptSubmit":
            event = .userPromptSubmit
        case "PreCompact":
            event = .preCompact
        case "Stop":
            event = .stop
        case "StopFailure":
            event = .stopFailure
        case "SessionStart":
            event = .sessionStart
        case "SubagentStart":
            event = .subagentStart
        case "SubagentStop":
            event = .subagentStop
        default:
            respond(.empty)
            return
        }

        if isActivityEvent(event),
           let confs = pendingRequests[message.sessionId], !confs.isEmpty {
            for conf in confs {
                responseCallbacks[conf.id]?(.empty)
                responseCallbacks.removeValue(forKey: conf.id)
                questionInputs.removeValue(forKey: conf.id)
            }
            pendingRequests.removeValue(forKey: message.sessionId)
            NSLog("[AgentIsland] Hook: cleared stale confirmations for \(message.sessionId) — user responded in terminal")
        }

        applyEvent(event, sessionId: message.sessionId)
        respond(.empty)
    }

    func updateSessions(_ files: [ClaudeSessionFile]) {
        var updated: [String: AgentSession] = [:]
        var updatedFiles: [String: ClaudeSessionFile] = [:]
        for file in files {
            var session = SessionFileParser.toAgentSession(file)
            if let state = sessionStates[session.id] {
                session.status = state.status
            }
            if let confs = pendingRequests[session.id], !confs.isEmpty {
                session.status = .waitingConfirmation
            }
            updated[session.id] = session
            updatedFiles[session.id] = file
        }
        let removedIds = Set(activeSessions.keys).subtracting(updated.keys)
        for id in removedIds {
            if let confs = pendingRequests[id] {
                for conf in confs {
                    responseCallbacks[conf.id]?(HookResponse(decision: "ask", reason: "Session ended"))
                    responseCallbacks.removeValue(forKey: conf.id)
                    questionInputs.removeValue(forKey: conf.id)
                }
            }
            pendingRequests.removeValue(forKey: id)
            cachedTodos.removeValue(forKey: id)
            sessionStates.removeValue(forKey: id)
        }
        activeSessions = updated
        sessionFiles = updatedFiles
        refreshConversationData()
    }

    // MARK: - Private

    private func applyEvent(_ event: SessionEvent, sessionId: String) {
        var state = sessionStates[sessionId] ?? SessionState()
        let previousStatus = state.status
        state.apply(event)
        sessionStates[sessionId] = state

        if var session = activeSessions[sessionId] {
            session.status = state.status
            activeSessions[sessionId] = session
        }

        NSLog("[AgentIsland] State: session=\(sessionId.prefix(8)) event=\(event) → \(state.status.displayText)")

        NotificationCenter.default.post(
            name: Self.statusChangedNotification,
            object: nil,
            userInfo: [
                "sessionId": sessionId,
                "status": state.status,
                "previousStatus": previousStatus,
            ]
        )
    }

    private func isActivityEvent(_ event: SessionEvent) -> Bool {
        switch event {
        case .preToolUse, .postToolUse, .userPromptSubmit, .subagentStart:
            return true
        default:
            return false
        }
    }

    private func cleanupStaleConfirmations() {
        let now = Date()
        for (sessionId, confirmations) in pendingRequests {
            let stale = confirmations.filter {
                now.timeIntervalSince($0.timestamp) > confirmationTimeout
            }
            for conf in stale {
                responseCallbacks[conf.id]?(HookResponse(decision: "ask", reason: "Timed out"))
                responseCallbacks.removeValue(forKey: conf.id)
                questionInputs.removeValue(forKey: conf.id)
            }
            let remaining = confirmations.filter {
                now.timeIntervalSince($0.timestamp) <= confirmationTimeout
            }
            if remaining.isEmpty {
                pendingRequests.removeValue(forKey: sessionId)
                applyEvent(.permissionDenied, sessionId: sessionId)
            } else {
                pendingRequests[sessionId] = remaining
            }
        }
    }

    // MARK: - Conversation Data

    private func refreshConversationData() {
        for (id, file) in sessionFiles {
            guard var session = activeSessions[id] else { continue }
            let path = ConversationLogParser.jsonlPath(cwd: file.cwd, sessionId: file.sessionId)

            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let modDate = attrs[.modificationDate] as? Date {
                session.lastUpdate = modDate
            }

            let snap = ConversationLogParser.snapshot(atPath: path)
            session.sessionDescription = snap.sessionDescription
            session.lastUserPrompt = snap.lastUserPrompt
            session.lastAssistantMessage = snap.lastAssistantMessage
            if revokedAutoApprove.contains(id) {
                session.permissionMode = nil
            } else {
                session.permissionMode = snap.permissionMode
            }
            if snap.isConversationCompressed && !session.isConversationCompressed {
                session.compressedAt = Date()
            } else if !snap.isConversationCompressed {
                session.compressedAt = nil
            }
            session.isConversationCompressed = snap.isConversationCompressed

            if !snap.todos.isEmpty {
                cachedTodos[id] = snap.todos
            }

            let activeSubagents = snap.subagents.filter { !$0.isComplete }
            session.subagents = activeSubagents.isEmpty ? nil : activeSubagents
            session.todos = cachedTodos[id]
            session.currentToolCall = snap.currentToolCall

            if let state = sessionStates[id] {
                session.status = state.status
            }
            if let confs = pendingRequests[id], !confs.isEmpty {
                session.status = .waitingConfirmation
            }

            activeSessions[id] = session
        }
    }

    private func summarizeToolInput(name: String, input: [String: AnyCodable]) -> String {
        switch name {
        case "Bash":
            if let cmd = input["command"]?.value as? String {
                let short = cmd.count > 80 ? String(cmd.prefix(77)) + "..." : cmd
                return "Bash: \(short)"
            }
        case "Write", "Edit", "Read":
            if let path = input["file_path"]?.value as? String {
                return "\(name): \(path)"
            }
        default:
            break
        }
        return name
    }

    private func parseAskUserQuestion(_ input: [String: AnyCodable]) -> ChoiceDetails? {
        guard let questionsRaw = input["questions"]?.value as? [[String: Any]],
              let first = questionsRaw.first,
              let questionText = first["question"] as? String,
              let optionsRaw = first["options"] as? [[String: Any]] else {
            return nil
        }

        let options = optionsRaw.map { opt in
            ChoiceOption(
                id: (opt["label"] as? String) ?? "unknown",
                label: (opt["label"] as? String) ?? "unknown",
                description: opt["description"] as? String
            )
        }
        guard !options.isEmpty else { return nil }
        return ChoiceDetails(question: questionText, options: options)
    }

    private func buildDiff(from input: [String: AnyCodable]) -> [DiffLine] {
        if let oldStr = input["old_string"]?.value as? String,
           let newStr = input["new_string"]?.value as? String {
            var lines: [DiffLine] = []
            var lineNum = 1
            for line in oldStr.components(separatedBy: "\n") {
                lines.append(DiffLine(lineNumber: lineNum, content: line, type: .removed))
                lineNum += 1
            }
            lineNum = 1
            for line in newStr.components(separatedBy: "\n") {
                lines.append(DiffLine(lineNumber: lineNum, content: line, type: .added))
                lineNum += 1
            }
            return lines
        }
        if let content = input["content"]?.value as? String {
            return content.components(separatedBy: "\n").enumerated().map { idx, line in
                DiffLine(lineNumber: idx + 1, content: line, type: .added)
            }
        }
        return []
    }
}
