import Foundation

extension BridgeServer {

    func startClaudeSessionWatcher() {
        let watcher = SessionFileWatcher(directoryPath: claudeSessionsPath) { [weak self] files in
            guard let self else { return }
            Task { await self.updateClaudeSessions(files) }
        }
        self.sessionWatcher = watcher
        watcher.start()
    }

    func handleClaudePermissionRequest(
        message: HookMessage, sessionId: String, clientID: UUID,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        ensureClaudeSession(hookSessionId: message.sessionId)
        handlePermissionRequest(message: message, sessionId: sessionId, clientID: clientID, respond: respond)
    }

    func handleClaudeStatusHook(
        message: HookMessage, sessionId: String,
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

        ensureClaudeSession(hookSessionId: message.sessionId)

        if event.indicatesPostConfirmationProgress {
            clearStaleInteraction(for: sessionId)
        }

        applyEvent(event, sessionId: sessionId)
        respond(.empty)
    }

    func discoverClaudeSessions() {
        guard let watcher = sessionWatcher else { return }
        if sessions.values.allSatisfy({ $0.agentType != .claudeCode }) {
            let files = watcher.scanNow()
            for file in files {
                let session = SessionFileParser.toAgentSession(file)
                let id = internalSessionId(agentType: .claudeCode, hookSessionId: session.id)
                if sessions[id] == nil {
                    var s = session
                    s = AgentSession(
                        id: id, agentType: .claudeCode, title: s.title,
                        status: s.status, startTime: s.startTime, lastUpdate: s.lastUpdate,
                        terminalInfo: s.terminalInfo, currentToolCall: nil
                    )
                    sessions[id] = s
                    sessionFiles[id] = file
                }
            }
        }
    }

    func refreshClaudeConversationData() {
        for (id, file) in sessionFiles {
            guard var session = sessions[id] else { continue }
            let path = ConversationLogParser.jsonlPath(cwd: file.cwd, sessionId: file.sessionId)

            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let modDate = attrs[.modificationDate] as? Date {
                session.lastUpdate = modDate
            }

            let snap = ConversationLogParser.snapshot(atPath: path)
            session.sessionDescription = snap.sessionDescription
            session.lastUserPrompt = snap.lastUserPrompt
            session.lastAssistantMessage = snap.lastAssistantMessage
            if localAutoApprove.contains(id) {
                session.permissionMode = "autoApprove"
            } else if revokedAutoApprove.contains(id) {
                session.permissionMode = nil
            } else {
                session.permissionMode = snap.permissionMode
            }

            session.isConversationCompressed = snap.isConversationCompressed
            session.entriesSinceCompact = snap.entriesSinceCompact

            if !snap.todos.isEmpty { cachedTodos[id] = snap.todos }
            let activeSubagents = snap.subagents.filter { !$0.isComplete }
            session.subagents = activeSubagents.isEmpty ? nil : activeSubagents
            session.todos = cachedTodos[id]
            session.currentToolCall = snap.currentToolCall

            if let state = sessionStates[id] { session.status = state.status }

            sessions[id] = session
        }
    }

    func updateClaudeSessions(_ files: [ClaudeSessionFile]) {
        var updated: [String: AgentSession] = [:]
        var updatedFiles: [String: ClaudeSessionFile] = [:]

        for file in files {
            let baseSession = SessionFileParser.toAgentSession(file)
            let id = internalSessionId(agentType: .claudeCode, hookSessionId: baseSession.id)
            var session = AgentSession(
                id: id, agentType: .claudeCode, title: baseSession.title,
                status: baseSession.status, startTime: baseSession.startTime,
                lastUpdate: baseSession.lastUpdate,
                terminalInfo: baseSession.terminalInfo, currentToolCall: nil
            )
            if let state = sessionStates[id] { session.status = state.status }
            updated[id] = session
            updatedFiles[id] = file
        }

        let claudeSessionIds = sessions.keys.filter { sessions[$0]?.agentType == .claudeCode }
        let removedIds = Set(claudeSessionIds).subtracting(updated.keys)
        for id in removedIds {
            removeSession(id)
            cachedTodos.removeValue(forKey: id)
        }

        for (id, session) in updated {
            sessions[id] = session
        }
        sessionFiles = updatedFiles
        refreshClaudeConversationData()
    }

    // MARK: - Private

    private func ensureClaudeSession(hookSessionId: String) {
        let id = internalSessionId(agentType: .claudeCode, hookSessionId: hookSessionId)
        ensureSessionExists(id: id, agentType: .claudeCode, title: "Claude Code")
    }

}
