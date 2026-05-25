import Foundation

final class HookStatusStore: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [String: (status: SessionStatus, date: Date)] = [:]

    func set(sessionId: String, status: SessionStatus) {
        lock.lock()
        statuses[sessionId] = (status: status, date: Date())
        lock.unlock()
    }

    func get(sessionId: String) -> (status: SessionStatus, date: Date)? {
        lock.lock()
        defer { lock.unlock() }
        return statuses[sessionId]
    }

    func remove(sessionId: String) {
        lock.lock()
        statuses.removeValue(forKey: sessionId)
        lock.unlock()
    }
}

actor ClaudeCodeAdaptor: AgentAdaptor, IPCServerDelegate {
    nonisolated let agentType: AgentType = .claudeCode
    nonisolated let hookStatusStore = HookStatusStore()

    private var activeSessions: [String: AgentSession] = [:]
    private var sessionFiles: [String: ClaudeSessionFile] = [:]
    private var pendingRequests: [String: [PendingConfirmation]] = [:]
    private var responseCallbacks: [String: @Sendable (HookResponse) -> Void] = [:]
    private var cachedTodos: [String: [TodoItem]] = [:]
    private var revokedAutoApprove: Set<String> = []
    private var hookStatusOverrides: [String: (status: SessionStatus, date: Date)] = [:]
    private var lastCompactEndedAt: [String: Date] = [:]
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
        let decision: String
        switch response {
        case .allow: decision = "allow"
        case .deny: decision = "deny"
        case .select: decision = "allow"
        }
        if let callback = responseCallbacks[confirmation.id] {
            callback(HookResponse(decision: decision, reason: nil))
        } else {
            NSLog("[AgentIsland] respond: no callback for \(confirmation.id) — bridge likely timed out")
        }
        responseCallbacks.removeValue(forKey: confirmation.id)
        pendingRequests[session.id]?.removeAll { $0.id == confirmation.id }
        if pendingRequests[session.id]?.isEmpty == true {
            pendingRequests.removeValue(forKey: session.id)
            if var s = activeSessions[session.id] {
                s.status = .executing
                activeSessions[session.id] = s
            }
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
        // Immediately update hook status store (bypasses actor queue)
        switch message.type {
        case "PreCompact":
            hookStatusStore.set(sessionId: message.sessionId, status: .compacting)
        case "Stop", "StopFailure":
            hookStatusStore.set(sessionId: message.sessionId, status: .idle)
        case "PreToolUse":
            hookStatusStore.set(sessionId: message.sessionId, status: Self.refineExecutingStatic(toolName: message.toolName))
        case "PostToolUse", "PostToolUseFailure", "UserPromptSubmit":
            hookStatusStore.set(sessionId: message.sessionId, status: .executing)
        default:
            break
        }

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
        NotificationCenter.default.post(name: Self.confirmationReceivedNotification, object: nil)
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
            cachedTodos.removeValue(forKey: id)
        }
        activeSessions = updated
        sessionFiles = updatedFiles
        refreshConversationData()
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
            }
            let remaining = confirmations.filter {
                now.timeIntervalSince($0.timestamp) <= confirmationTimeout
            }
            if remaining.isEmpty {
                pendingRequests.removeValue(forKey: sessionId)
            } else {
                pendingRequests[sessionId] = remaining
            }
        }
    }

    // MARK: - Conversation

    private static let hookStatusTTL: TimeInterval = 15
    private static let compactingHookTTL: TimeInterval = 20
    private static let idleHookTTL: TimeInterval = 70

    func handleStatusHook(
        _ message: HookMessage,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        let status: SessionStatus
        switch message.type {
        case "PreToolUse":
            status = refineExecuting(toolName: message.toolName)
        case "PostToolUse", "PostToolUseFailure":
            status = .executing
        case "UserPromptSubmit":
            status = .executing
        case "PreCompact":
            status = .compacting
        case "Stop", "StopFailure":
            status = .idle
        default:
            respond(.empty)
            return
        }

        NSLog("[AgentIsland] Hook: \(message.type) session=\(message.sessionId) tool=\(message.toolName ?? "-") → \(status.displayText)")
        DebugLog.log("HOOK-IN: type=\(message.type) session=\(message.sessionId.prefix(8)) → \(status.displayText)")


        if status != .waitingConfirmation,
           let confs = pendingRequests[message.sessionId], !confs.isEmpty {
            for conf in confs {
                responseCallbacks.removeValue(forKey: conf.id)
            }
            pendingRequests.removeValue(forKey: message.sessionId)
            NSLog("[AgentIsland] Hook: cleared stale confirmations for \(message.sessionId) — user responded in terminal")
        }

        if status != .compacting && status != .idle {
            lastCompactEndedAt.removeValue(forKey: message.sessionId)
        }
        hookStatusOverrides[message.sessionId] = (status: status, date: Date())
        if var session = activeSessions[message.sessionId] {
            session.status = status
            activeSessions[message.sessionId] = session
            DebugLog.log("HOOK-SET: session=\(message.sessionId.prefix(8)) status=\(status.displayText) found=YES")
        } else {
            NSLog("[AgentIsland] Hook: session \(message.sessionId) not found in activeSessions (count=\(activeSessions.count), keys=\(Array(activeSessions.keys)))")
            DebugLog.log("HOOK-SET: session=\(message.sessionId.prefix(8)) status=\(status.displayText) found=NO keys=\(Array(activeSessions.keys).map { String($0.prefix(8)) })")
        }

        respond(.empty)
        DebugLog.log("HOOK-NOTIFY: posting statusChanged session=\(message.sessionId.prefix(8)) status=\(status.displayText)")
        NotificationCenter.default.post(
            name: Self.statusChangedNotification,
            object: nil,
            userInfo: ["sessionId": message.sessionId, "status": status]
        )
    }

    // MARK: - Conversation

    private static let noStatusIdleThreshold: TimeInterval = 120
    private static let noFileStatusIdleThreshold: TimeInterval = 60

    private func refreshConversationData() {
        let now = Date()
        for (id, file) in sessionFiles {
            guard var session = activeSessions[id] else { continue }
            let path = ConversationLogParser.jsonlPath(cwd: file.cwd, sessionId: file.sessionId)

            var jsonlModDate: Date?
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let modDate = attrs[.modificationDate] as? Date {
                session.lastUpdate = modDate
                jsonlModDate = modDate
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
                session.compressedAt = now
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

            let freshStatus = SessionFileParser.readStatus(pid: file.pid, directoryPath: sessionsDirectoryPath)
            let effectiveFileStatus = freshStatus ?? file.status

            let storeOverride = hookStatusStore.get(sessionId: id)
            let actorOverride = hookStatusOverrides[id]
            let effectiveOverride: (status: SessionStatus, date: Date)?
            if let s = storeOverride, let a = actorOverride {
                effectiveOverride = s.date > a.date ? s : a
            } else {
                effectiveOverride = storeOverride ?? actorOverride
            }
            let hookTTL: TimeInterval
            if effectiveOverride?.status == .compacting {
                hookTTL = Self.compactingHookTTL
            } else if effectiveOverride?.status == .idle {
                hookTTL = Self.idleHookTTL
            } else {
                hookTTL = Self.hookStatusTTL
            }

            let derived = deriveStatus(
                jsonlModDate: jsonlModDate,
                now: now,
                lastMessageType: snap.lastMessageType,
                fileStatus: effectiveFileStatus,
                lastAssistantHasToolUse: snap.lastAssistantHasToolUse,
                lastToolName: snap.lastToolName
            )

            if let confs = pendingRequests[id], !confs.isEmpty {
                session.status = .waitingConfirmation
            } else if let override = effectiveOverride,
                      now.timeIntervalSince(override.date) < hookTTL {
                if override.status == .compacting && derived == .idle {
                    session.status = .idle
                    lastCompactEndedAt[id] = now
                    hookStatusOverrides.removeValue(forKey: id)
                    hookStatusStore.remove(sessionId: id)
                    DebugLog.log("REFRESH: session=\(id.prefix(8)) compacting ended (derived=idle) → .idle")
                } else {
                    session.status = override.status
                    DebugLog.log("REFRESH: session=\(id.prefix(8)) override=\(override.status.displayText) derived=\(derived.displayText)")
                }
            } else {
                hookStatusOverrides.removeValue(forKey: id)
                if storeOverride != nil {
                    hookStatusStore.remove(sessionId: id)
                }
                if let compactEnd = lastCompactEndedAt[id],
                   now.timeIntervalSince(compactEnd) < Self.noFileStatusIdleThreshold + 10 {
                    session.status = .idle
                    DebugLog.log("REFRESH: session=\(id.prefix(8)) post-compact grace → .idle (derived=\(derived.displayText))")
                } else {
                    lastCompactEndedAt.removeValue(forKey: id)
                    session.status = derived
                    DebugLog.log("REFRESH: session=\(id.prefix(8)) expired/none → derived=\(derived.displayText) fileStatus=\(effectiveFileStatus ?? "nil")")
                }
            }

            activeSessions[id] = session
        }
    }

    private static let readingTools: Set<String> = [
        "Read", "WebFetch", "WebSearch", "Grep", "Glob"
    ]
    private static let editingTools: Set<String> = [
        "Edit", "Write", "NotebookEdit"
    ]

    private func deriveStatus(
        jsonlModDate: Date?,
        now: Date,
        lastMessageType: ConversationLogParser.LastMessageType,
        fileStatus: String?,
        lastAssistantHasToolUse: Bool,
        lastToolName: String?
    ) -> SessionStatus {
        if fileStatus == "idle" {
            return .idle
        }

        let elapsed: TimeInterval
        if let modDate = jsonlModDate {
            elapsed = now.timeIntervalSince(modDate)
        } else {
            if let status = fileStatus, status != "idle" {
                return refineExecuting(toolName: lastToolName)
            }
            return .idle
        }

        if let status = fileStatus, status != "idle" {
            return activeStatus(lastMessageType: lastMessageType, lastAssistantHasToolUse: lastAssistantHasToolUse, lastToolName: lastToolName)
        }

        let idleThreshold = fileStatus != nil ? Self.noStatusIdleThreshold : Self.noFileStatusIdleThreshold
        guard elapsed < idleThreshold else { return .idle }

        return activeStatus(lastMessageType: lastMessageType, lastAssistantHasToolUse: lastAssistantHasToolUse, lastToolName: lastToolName)
    }

    private func activeStatus(
        lastMessageType: ConversationLogParser.LastMessageType,
        lastAssistantHasToolUse: Bool,
        lastToolName: String?
    ) -> SessionStatus {
        switch lastMessageType {
        case .assistant where lastAssistantHasToolUse:
            return refineExecuting(toolName: lastToolName)
        default:
            return .executing
        }
    }

    private func refineExecuting(toolName: String?) -> SessionStatus {
        Self.refineExecutingStatic(toolName: toolName)
    }

    nonisolated static func refineExecutingStatic(toolName: String?) -> SessionStatus {
        guard let tool = toolName else { return .executing }
        if readingTools.contains(tool) { return .reading }
        if editingTools.contains(tool) { return .editing }
        return .executing
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
