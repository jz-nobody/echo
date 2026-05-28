import AppKit
import Foundation

extension BridgeServer {

    static let qoderWorkIdleTimeout: TimeInterval = 300
    static let qoderWorkStaleTimeout: TimeInterval = 120
    static let qoderWorkBundleId = "com.qoder.work"

    func handleQoderWorkPermissionRequest(
        message: HookMessage, sessionId: String,
        clientPID: pid_t?, clientID: UUID,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        ensureQoderWorkSession(hookSessionId: message.sessionId, cwd: message.cwd)
        updateQoderWorkTerminalInfo(sessionId: sessionId, clientPID: clientPID)
        checkIfQoderWorkBackground(sessionId: sessionId, clientPID: clientPID)
        recordActivity(sessionId: sessionId)
        storeTranscriptPath(message, sessionId: sessionId)

        if message.toolName == "AskUserQuestion",
           let choiceDetails = parseAskUserQuestion(message.toolInput ?? [:]) {
            let confId = "\(sessionId)-AskUserQuestion-\(Int(Date().timeIntervalSince1970 * 1000))"
            let confirmation = PendingConfirmation(
                id: confId, type: .choice, title: choiceDetails.question,
                details: .choice(choiceDetails), timestamp: Date()
            )
            pendingConfirmations[confId] = confirmation
            confirmationToSession[confId] = sessionId
            clientToConfirmation[clientID] = confId
            questionInputs[confId] = message.toolInput ?? [:]
            qoderWorkChatIds[confId] = extractQoderWorkChatId(from: message.cwd)
            respond(.empty)
            applyEvent(.permissionRequest, sessionId: sessionId)
            NotificationCenter.default.post(name: Self.confirmationReceivedNotification, object: nil)
            return
        }

        handlePermissionRequest(message: message, sessionId: sessionId, clientID: clientID, respond: respond)
    }

    func handleQoderWorkStatusHook(
        message: HookMessage, sessionId: String,
        clientPID: pid_t?,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        ensureQoderWorkSession(hookSessionId: message.sessionId, cwd: message.cwd)
        updateQoderWorkTerminalInfo(sessionId: sessionId, clientPID: clientPID)
        checkIfQoderWorkBackground(sessionId: sessionId, clientPID: clientPID)
        recordActivity(sessionId: sessionId)
        storeTranscriptPath(message, sessionId: sessionId)

        let event: SessionEvent
        switch message.type {
        case "UserPromptSubmit":
            event = .userPromptSubmit
            if let prompt = message.prompt {
                let cleaned = stripSystemReminders(prompt)
                sessions[sessionId]?.lastUserPrompt = cleaned
                if sessions[sessionId]?.title == "QoderWork" {
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
        case "PostToolUse":
            event = .postToolUse
            sessions[sessionId]?.currentToolCall = nil
        case "Stop":
            event = .stop
            sessions[sessionId]?.currentToolCall = nil
        case "SessionStart":
            event = .sessionStart
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

    func cleanupQoderWorkDeadSessions() {
        var toRemove: [String] = []
        let now = Date()
        for (id, session) in sessions where session.agentType == .qoderWork {
            if let pid = session.terminalInfo?.pid, !isProcessAlive(pid) {
                toRemove.append(id)
                continue
            }
            if session.status.isActive, session.terminalInfo?.pid == nil,
               let lastActivity = lastActivityDates[id],
               now.timeIntervalSince(lastActivity) > Self.qoderWorkStaleTimeout {
                applyEvent(.processTerminated, sessionId: id)
                continue
            }
            if session.terminalInfo?.pid == nil,
               let lastActivity = lastActivityDates[id],
               now.timeIntervalSince(lastActivity) > Self.qoderWorkIdleTimeout {
                toRemove.append(id)
            }
        }
        for id in toRemove {
            removeQoderWorkSession(id)
        }
    }

    func deduplicateQoderWorkByTitle() {
        var titleToSessions: [String: [(id: String, lastActivity: Date)]] = [:]
        for (id, session) in sessions where session.agentType == .qoderWork {
            let activity = lastActivityDates[id] ?? session.startTime
            titleToSessions[session.title, default: []].append((id: id, lastActivity: activity))
        }
        for (_, group) in titleToSessions where group.count > 1 {
            let sorted = group.sorted { $0.lastActivity > $1.lastActivity }
            for entry in sorted.dropFirst() {
                if hasConfirmationsFor(sessionId: entry.id) { continue }
                removeQoderWorkSession(entry.id)
            }
        }
    }

    func enrichAllQoderWorkTranscripts() {
        for (id, session) in sessions where session.agentType == .qoderWork {
            enrichFromTranscript(sessionId: id)
        }
    }

    // MARK: - Private

    private func ensureQoderWorkSession(hookSessionId: String, cwd: String? = nil) {
        let id = internalSessionId(agentType: .qoderWork, hookSessionId: hookSessionId)
        let title = deriveTitle(from: cwd)
        ensureSessionExists(id: id, agentType: .qoderWork, title: title, cwd: cwd)
    }

    private func updateQoderWorkTerminalInfo(sessionId: String, clientPID: pid_t?) {
        guard sessions[sessionId]?.terminalInfo == nil else { return }
        let appPID: pid_t
        if let pid = clientPID, let resolved = ProcessAncestry.findTerminalAppPID(of: pid) {
            appPID = resolved
        } else if let qoderPID = findQoderWorkAppPID() {
            appPID = qoderPID
        } else {
            return
        }
        sessions[sessionId]?.terminalInfo = TerminalInfo(appName: "QoderWork", pid: appPID, windowId: nil)
    }

    private func findQoderWorkAppPID() -> pid_t? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == Self.qoderWorkBundleId }?
            .processIdentifier
    }

    private func checkIfQoderWorkBackground(sessionId: String, clientPID: pid_t?) {
        guard let pid = clientPID else { return }
        guard sessionClientPIDs[sessionId] == nil else { return }
        sessionClientPIDs[sessionId] = pid
        if let args = findQodercliArgs(startingFrom: pid), isBackgroundArgs(args) {
            backgroundSessionIds.insert(sessionId)
        }
    }

    private func findQodercliArgs(startingFrom pid: pid_t) -> [String]? {
        var current = pid
        for _ in 0..<10 {
            if let args = ProcessAncestry.getProcessArgs(of: current),
               let exe = args.first, exe.contains("qodercli") {
                return args
            }
            guard let parent = ProcessAncestry.parentPID(of: current), parent > 1 else { return nil }
            current = parent
        }
        return nil
    }

    private func isBackgroundArgs(_ args: [String]) -> Bool {
        if args.contains("--skip-skills") { return true }
        if let idx = args.firstIndex(of: "--disallowed-tools"),
           idx + 1 < args.count, args[idx + 1] == "*" { return true }
        return false
    }

    private func removeQoderWorkSession(_ id: String) {
        activeSubagents.removeValue(forKey: id)
        transcriptPaths.removeValue(forKey: id)
        backgroundSessionIds.remove(id)
        sessionClientPIDs.removeValue(forKey: id)
        removeSession(id)
    }

    private func storeTranscriptPath(_ message: HookMessage, sessionId: String) {
        if let path = message.transcriptPath, !path.isEmpty {
            transcriptPaths[sessionId] = path
        }
    }

    private func enrichFromTranscript(sessionId: String) {
        guard let path = transcriptPaths[sessionId],
              FileManager.default.fileExists(atPath: path) else { return }
        let snap = ConversationLogParser.snapshot(atPath: path)
        if let msg = snap.lastAssistantMessage { sessions[sessionId]?.lastAssistantMessage = msg }
        if let desc = snap.sessionDescription, sessions[sessionId]?.sessionDescription == nil {
            sessions[sessionId]?.sessionDescription = desc
        }
        if sessions[sessionId]?.todos == nil && !snap.todos.isEmpty {
            sessions[sessionId]?.todos = snap.todos
        }
        if sessions[sessionId]?.subagents == nil {
            let active = snap.subagents.filter { !$0.isComplete }
            sessions[sessionId]?.subagents = active.isEmpty ? nil : active
        }
    }


    private func isProcessAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    private func addSubagent(sessionId: String, from input: [String: AnyCodable]) {
        let description = (input["description"]?.value as? String) ?? "Subagent"
        let agentType = (input["subagent_type"]?.value as? String) ?? "general"
        let id = "\(sessionId)-sub-\(Int(Date().timeIntervalSince1970 * 1000))"
        let info = SubagentInfo(id: id, description: description, agentType: agentType, isComplete: false)
        activeSubagents[sessionId, default: []].append(info)
        sessions[sessionId]?.subagents = activeSubagents[sessionId]?.filter { !$0.isComplete }
    }

    private func completeLastSubagent(sessionId: String) {
        guard var subs = activeSubagents[sessionId], !subs.isEmpty,
              let idx = subs.lastIndex(where: { !$0.isComplete }) else { return }
        subs[idx] = SubagentInfo(
            id: subs[idx].id, description: subs[idx].description,
            agentType: subs[idx].agentType, isComplete: true
        )
        activeSubagents[sessionId] = subs
        let active = subs.filter { !$0.isComplete }
        sessions[sessionId]?.subagents = active.isEmpty ? nil : active
    }

    private func parseTodos(from input: [String: AnyCodable]) -> [TodoItem]? {
        guard let todosRaw = input["todos"]?.value as? [[String: Any]] else { return nil }
        let items = todosRaw.compactMap { raw -> TodoItem? in
            guard let content = raw["content"] as? String,
                  let statusStr = raw["status"] as? String,
                  let status = TodoStatus(rawValue: statusStr) else { return nil }
            let activeForm = (raw["activeForm"] as? String) ?? content
            return TodoItem(content: content, status: status, activeForm: activeForm)
        }
        return items.isEmpty ? nil : items
    }

    private func extractQoderWorkChatId(from cwd: String?) -> String? {
        guard let cwd, cwd.contains("/.qoderwork/workspace/") else { return nil }
        return (cwd as NSString).lastPathComponent
    }

    private func deriveTitle(from cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty, cwd != "/" else { return "QoderWork" }
        if cwd.contains("/.qoderwork/workspace/") { return "QoderWork" }
        let lastComponent = (cwd as NSString).lastPathComponent
        if lastComponent.hasPrefix(".") { return "QoderWork" }
        if lastComponent.allSatisfy({ $0.isLetter || $0.isNumber }) && lastComponent.count > 12 {
            return "QoderWork"
        }
        return lastComponent
    }

    private func truncateTitle(_ text: String) -> String {
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 40 { return trimmed }
        return String(trimmed.prefix(37)) + "..."
    }

    private func stripSystemReminders(_ text: String) -> String {
        var result = text
        while let startRange = result.range(of: "<system-reminder>") {
            if let endRange = result.range(of: "</system-reminder>", range: startRange.upperBound..<result.endIndex) {
                result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            } else {
                result.removeSubrange(startRange.lowerBound..<result.endIndex)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
