import AppKit
import Foundation

extension BridgeServer {

    func handleGenericPermissionRequest(
        message: HookMessage, sessionId: String,
        agentType: AgentType, displayName: String,
        clientID: UUID,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        let id = internalSessionId(agentType: agentType, hookSessionId: message.sessionId)
        ensureSessionExists(id: id, agentType: agentType, title: displayName)
        recordActivity(sessionId: sessionId)
        handlePermissionRequest(
            message: message, sessionId: sessionId,
            clientID: clientID, respond: respond
        )
    }

    func handleGenericStatusHook(
        message: HookMessage, sessionId: String,
        agentType: AgentType, displayName: String,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        let id = internalSessionId(agentType: agentType, hookSessionId: message.sessionId)
        ensureSessionExists(id: id, agentType: agentType, title: displayName, cwd: message.cwd)
        recordActivity(sessionId: sessionId)

        if let path = message.transcriptPath, !path.isEmpty {
            transcriptPaths[sessionId] = path
        }

        let event: SessionEvent
        switch message.type {
        case "UserPromptSubmit":
            event = .userPromptSubmit
            if let prompt = message.prompt {
                let cleaned = stripSystemReminders(prompt)
                sessions[sessionId]?.lastUserPrompt = cleaned
                if sessions[sessionId]?.title == displayName {
                    sessions[sessionId]?.title = truncateTitle(cleaned)
                }
            }
        case "PreToolUse":
            event = .preToolUse(toolName: message.toolName)
            let toolName = message.toolName ?? "Unknown"
            let toolInput = message.toolInput ?? [:]
            sessions[sessionId]?.currentToolCall = summarizeToolInput(name: toolName, input: toolInput)
            if toolName == "TodoWrite" {
                sessions[sessionId]?.todos = parseTodos(from: toolInput)
            }
            if toolName == "Agent" {
                addSubagent(sessionId: sessionId, from: toolInput)
            }
        case "PostToolUse", "PostToolUseFailure":
            event = .postToolUse
            sessions[sessionId]?.currentToolCall = nil
        case "Stop":
            event = .stop
            sessions[sessionId]?.currentToolCall = nil
        case "StopFailure":
            event = .stopFailure
        case "SessionStart":
            event = .sessionStart
        case "PreCompact":
            event = .preCompact
        case "SubagentStart":
            event = .subagentStart
        case "SubagentStop":
            event = .subagentStop
            completeLastSubagent(sessionId: sessionId)
        default:
            respond(.empty)
            return
        }

        if event.indicatesPostConfirmationProgress {
            clearStaleInteraction(for: sessionId)
        }

        applyEvent(event, sessionId: sessionId)
        respond(.empty)
    }

    // MARK: - Qoder File Discovery

    var qoderProjectsPath: String {
        guard let config = agentConfigs["qoder"] else {
            return NSHomeDirectory() + "/.qoder/projects"
        }
        return (config.hookSettingsPath as NSString)
            .deletingLastPathComponent + "/projects"
    }

    func discoverQoderSessions() {
        guard agentConfigs["qoder"] != nil else { return }
        let fm = FileManager.default
        let projectsDir = qoderProjectsPath
        guard fm.fileExists(atPath: projectsDir) else { return }
        guard let dirNames = try? fm.contentsOfDirectory(atPath: projectsDir) else { return }

        let now = Date()

        for dirName in dirNames {
            let dirPath = (projectsDir as NSString).appendingPathComponent(dirName)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let transcriptDir = (dirPath as NSString).appendingPathComponent("transcript")
            guard fm.fileExists(atPath: transcriptDir) else { continue }
            guard let files = try? fm.contentsOfDirectory(atPath: transcriptDir) else { continue }

            let jsonlFiles = files.filter {
                $0.hasSuffix(".jsonl") && !$0.hasPrefix("task-")
            }
            guard !jsonlFiles.isEmpty else { continue }

            let internalId = internalSessionId(agentType: .qoder, hookSessionId: dirName)

            var latestDate: Date?
            var latestPath: String?
            for filename in jsonlFiles {
                let jsonlPath = (transcriptDir as NSString).appendingPathComponent(filename)
                guard let attrs = try? fm.attributesOfItem(atPath: jsonlPath),
                      let modDate = attrs[.modificationDate] as? Date else { continue }
                if latestDate == nil || modDate > latestDate! {
                    latestDate = modDate
                    latestPath = jsonlPath
                }
            }

            guard let modDate = latestDate,
                  now.timeIntervalSince(modDate) < BridgeServer.sessionVisibilityTimeout else { continue }

            if let path = latestPath {
                transcriptPaths[internalId] = path
            }

            guard sessions[internalId] == nil else { continue }

            let title = deriveQoderTitle(from: dirName, transcriptPath: latestPath)
            let qPID = findQoderAppPID()
            sessions[internalId] = AgentSession(
                id: internalId, agentType: .qoder, title: title,
                status: .idle, startTime: modDate, lastUpdate: modDate,
                terminalInfo: TerminalInfo(appName: "Qoder", pid: qPID, windowId: nil),
                currentToolCall: nil
            )
            lastActivityDates[internalId] = modDate
        }
    }

    func enrichQoderTranscripts() {
        let qoderPID = findQoderAppPID()
        for (id, session) in sessions where session.agentType == .qoder {
            if session.terminalInfo == nil, let pid = qoderPID {
                sessions[id]?.terminalInfo = TerminalInfo(appName: "Qoder", pid: pid, windowId: nil)
            }
            guard let path = transcriptPaths[id],
                  FileManager.default.fileExists(atPath: path) else { continue }
            let snap = ConversationLogParser.snapshot(atPath: path)
            if let prompt = snap.lastUserPrompt { sessions[id]?.lastUserPrompt = prompt }
            if let msg = snap.lastAssistantMessage { sessions[id]?.lastAssistantMessage = msg }
            if let desc = snap.sessionDescription, sessions[id]?.sessionDescription == nil {
                sessions[id]?.sessionDescription = desc
            }
            if sessions[id]?.todos == nil && !snap.todos.isEmpty {
                sessions[id]?.todos = snap.todos
            }
            if sessions[id]?.subagents == nil {
                let active = snap.subagents.filter { !$0.isComplete }
                sessions[id]?.subagents = active.isEmpty ? nil : active
            }
            if session.title == "Qoder" || session.title == id {
                if let desc = snap.sessionDescription {
                    sessions[id]?.title = truncateTitle(desc)
                }
            }
        }
    }

    private func deriveQoderTitle(from dirName: String, transcriptPath: String?) -> String {
        if let path = transcriptPath {
            let cwd = readCwdFromJsonl(atPath: path)
            if let cwd, !cwd.isEmpty {
                let last = (cwd as NSString).lastPathComponent
                if !last.isEmpty && last != "/" { return last }
            }
        }
        return "Qoder"
    }

    private func findQoderAppPID() -> pid_t? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == "com.qoder.ide" }?
            .processIdentifier
    }

    private func readCwdFromJsonl(atPath path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { handle.closeFile() }
        let data = handle.readData(ofLength: 4096)
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: "\n") {
            guard !line.isEmpty, let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let cwd = obj["cwd"] as? String, !cwd.isEmpty else { continue }
            return cwd
        }
        return nil
    }

    func cleanupIdleSessions(agentType: AgentType, timeout: TimeInterval) {
        let now = Date()
        var toRemove: [String] = []
        for (id, session) in sessions where session.agentType == agentType {
            guard let lastActivity = lastActivityDates[id] else { continue }
            if now.timeIntervalSince(lastActivity) > timeout {
                toRemove.append(id)
            }
        }
        for id in toRemove {
            removeSession(id)
        }
    }
}
