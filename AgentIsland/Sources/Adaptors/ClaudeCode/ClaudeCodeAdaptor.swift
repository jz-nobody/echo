import Foundation

actor ClaudeCodeAdaptor: AgentAdaptor, IPCServerDelegate {
    nonisolated let agentType: AgentType = .claudeCode

    private var activeSessions: [String: AgentSession] = [:]
    private var sessionFiles: [String: ClaudeSessionFile] = [:]
    private var pendingRequests: [String: [PendingConfirmation]] = [:]
    private var responseCallbacks: [String: @Sendable (HookResponse) -> Void] = [:]
    private var cachedSubagents: [String: [SubagentInfo]] = [:]
    private var cachedTodos: [String: [TodoItem]] = [:]
    private var lastScanOffset: [String: UInt64] = [:]
    private var sessionWatcher: SessionFileWatcher?
    private let ipcServer: IPCServer
    let sessionsDirectoryPath: String

    init(
        sessionsDirectoryPath: String = NSHomeDirectory() + "/.claude/sessions",
        socketPath: String = IPCProtocol.socketPath
    ) throws {
        self.sessionsDirectoryPath = sessionsDirectoryPath
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
        return activeSessions[session.id]?.status ?? .idle
    }

    func getPendingConfirmations(session: AgentSession) async throws -> [PendingConfirmation] {
        pendingRequests[session.id] ?? []
    }

    func respond(
        session: AgentSession,
        confirmation: PendingConfirmation,
        response: ConfirmationResponse
    ) async throws {
        let decision: String
        switch response {
        case .allow: decision = "allow"
        case .deny: decision = "deny"
        case .select: decision = "allow"
        }
        responseCallbacks[confirmation.id]?(HookResponse(decision: decision, reason: nil))
        responseCallbacks.removeValue(forKey: confirmation.id)
        pendingRequests[session.id]?.removeAll { $0.id == confirmation.id }
        if pendingRequests[session.id]?.isEmpty == true {
            pendingRequests.removeValue(forKey: session.id)
        }
    }

    // MARK: - IPCServerDelegate

    nonisolated func ipcServer(
        _ server: IPCServer,
        didReceive message: HookMessage,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        Task { await handlePermissionRequest(message, respond: respond) }
    }

    // MARK: - Internal

    func handlePermissionRequest(
        _ message: HookMessage,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        let confId = "\(message.sessionId)-\(message.toolName)-\(Int(Date().timeIntervalSince1970 * 1000))"
        let operation = summarizeToolInput(name: message.toolName, input: message.toolInput)
        let confirmation = PendingConfirmation(
            id: confId,
            type: .permission,
            title: operation,
            details: .permission(PermissionDetails(
                operation: operation,
                diff: buildDiff(from: message.toolInput),
                additions: 0,
                deletions: 0
            )),
            timestamp: Date()
        )
        pendingRequests[message.sessionId, default: []].append(confirmation)
        responseCallbacks[confId] = respond
    }

    func updateSessions(_ files: [ClaudeSessionFile]) {
        var updated: [String: AgentSession] = [:]
        var updatedFiles: [String: ClaudeSessionFile] = [:]
        for file in files {
            var session = SessionFileParser.toAgentSession(file)
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
                }
            }
            pendingRequests.removeValue(forKey: id)
            cachedSubagents.removeValue(forKey: id)
            cachedTodos.removeValue(forKey: id)
            lastScanOffset.removeValue(forKey: id)
        }
        activeSessions = updated
        sessionFiles = updatedFiles
    }

    // MARK: - Conversation

    private func refreshConversationData() {
        for (id, file) in sessionFiles {
            guard var session = activeSessions[id] else { continue }
            let path = ConversationLogParser.jsonlPath(cwd: file.cwd, sessionId: file.sessionId)

            let snap = ConversationLogParser.snapshot(atPath: path)
            session.sessionDescription = snap.sessionDescription
            session.lastUserPrompt = snap.lastUserPrompt
            session.lastAssistantMessage = snap.lastAssistantMessage
            session.permissionMode = snap.permissionMode
            session.isConversationCompressed = snap.isConversationCompressed

            let currentFileSize = ConversationLogParser.fileSize(atPath: path)
            let lastOffset = lastScanOffset[id] ?? 0
            if currentFileSize > lastOffset {
                let newSubagents = ConversationLogParser.scanAllSubagents(
                    atPath: path,
                    fromOffset: lastOffset
                )
                var merged = cachedSubagents[id] ?? []
                for sub in newSubagents {
                    if let idx = merged.firstIndex(where: { $0.id == sub.id }) {
                        merged[idx] = sub
                    } else {
                        merged.append(sub)
                    }
                }
                cachedSubagents[id] = merged
                lastScanOffset[id] = currentFileSize
            }

            if !snap.todos.isEmpty {
                cachedTodos[id] = snap.todos
            }

            session.subagents = cachedSubagents[id]
            session.todos = cachedTodos[id]
            activeSessions[id] = session
        }
    }

    // MARK: - Private

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
