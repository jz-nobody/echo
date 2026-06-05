import AppKit
import Foundation

extension BridgeServer {

    static let qoderWorkIdleTimeout: TimeInterval = 300
    static let processDeathMaxRetries = 3
    static let qoderWorkRecencyWindow: TimeInterval = 86400
    static let qoderWorkBundleId = "com.qoder.work"

    func handleQoderWorkPermissionRequest(
        message: HookMessage, sessionId: String,
        clientPID: pid_t?, clientID: UUID,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        let wsId = resolveWorkspaceSessionId(message: message, chatSessionId: sessionId)
        ensureQoderWorkSession(wsSessionId: wsId, cwd: message.cwd)
        updateQoderWorkTerminalInfo(sessionId: wsId, clientPID: clientPID)
        checkIfQoderWorkBackground(sessionId: wsId, clientPID: clientPID)
        recordActivity(sessionId: wsId)
        storeTranscriptPath(message, sessionId: wsId)

        if message.toolName == "AskUserQuestion",
           let choiceDetails = parseAllAskUserQuestions(message.toolInput ?? [:]).first {
            let confId = "\(wsId)-AskUserQuestion-\(Int(Date().timeIntervalSince1970 * 1000))"
            let confirmation = PendingConfirmation(
                id: confId, type: .choice, title: choiceDetails.question,
                details: .choice(choiceDetails), timestamp: Date()
            )
            pendingConfirmations[confId] = confirmation
            confirmationToSession[confId] = wsId
            clientToConfirmation[clientID] = confId
            questionInputs[confId] = message.toolInput ?? [:]
            qoderWorkChatIds[confId] = extractQoderWorkChatId(from: message.cwd)
            respond(.empty)
            applyEvent(.permissionRequest, sessionId: wsId)
            NotificationCenter.default.post(name: Self.confirmationReceivedNotification, object: nil)
            return
        }

        handlePermissionRequest(message: message, sessionId: wsId, clientID: clientID, respond: respond)
    }

    func handleQoderWorkStatusHook(
        message: HookMessage, sessionId: String,
        clientPID: pid_t?,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        let wsId = resolveWorkspaceSessionId(message: message, chatSessionId: sessionId)
        NSLog("[QoderWork] statusHook: type=%@ chatSessionId=%@ wsId=%@ transcriptPath=%@", message.type, sessionId, wsId, message.transcriptPath ?? "-")
        ensureQoderWorkSession(wsSessionId: wsId, cwd: message.cwd)
        updateQoderWorkTerminalInfo(sessionId: wsId, clientPID: clientPID)
        checkIfQoderWorkBackground(sessionId: wsId, clientPID: clientPID)
        recordActivity(sessionId: wsId)
        storeTranscriptPath(message, sessionId: wsId)

        switch message.type {
        case "UserPromptSubmit":
            if let prompt = message.prompt {
                let cleaned = stripSystemReminders(prompt)
                sessions[wsId]?.lastUserPrompt = cleaned
                if sessions[wsId]?.title == "QoderWork" {
                    sessions[wsId]?.title = truncateTitle(cleaned)
                }
            }
            clearStaleInteraction(for: wsId)
            applyEvent(.userPromptSubmit, sessionId: wsId)

        case "PreToolUse":
            let toolName = message.toolName ?? "Unknown"
            let toolInput = message.toolInput ?? [:]
            sessions[wsId]?.currentToolCall = summarizeToolInput(name: toolName, input: toolInput)
            if toolName == "TodoWrite" {
                sessions[wsId]?.todos = parseTodos(from: toolInput)
            }
            if toolName == "Agent" {
                addSubagent(sessionId: wsId, from: toolInput)
            }
            clearStaleInteraction(for: wsId)

        case "PostToolUse":
            sessions[wsId]?.currentToolCall = nil
            clearStaleInteraction(for: wsId)

        case "Stop":
            sessions[wsId]?.currentToolCall = nil
            clearStaleInteraction(for: wsId)
            applyEvent(.turnCompleted, sessionId: wsId)

        case "SessionStart":
            applyEvent(.sessionStart, sessionId: wsId)

        case "SubagentStart":
            applyEvent(.subagentStart, sessionId: wsId)

        case "SubagentStop":
            completeLastSubagent(sessionId: wsId)
            applyEvent(.subagentStop, sessionId: wsId)

        default:
            respond(.empty)
            return
        }

        respond(.empty)
    }

    // MARK: - File-Based Discovery

    func discoverQoderWorkSessions() {
        let fm = FileManager.default
        let projectsDir = qoderWorkProjectsPath
        guard fm.fileExists(atPath: projectsDir) else { return }
        guard let dirNames = try? fm.contentsOfDirectory(atPath: projectsDir) else { return }

        let now = Date()

        for dirName in dirNames {
            let dirPath = (projectsDir as NSString).appendingPathComponent(dirName)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { continue }

            guard let files = try? fm.contentsOfDirectory(atPath: dirPath) else { continue }

            let jsonlFiles = files.filter { $0.hasSuffix(".jsonl") }
            guard !jsonlFiles.isEmpty else { continue }

            let internalId = internalSessionId(agentType: .qoderWork, hookSessionId: dirName)

            var latestDate: Date?
            var latestPath: String?
            for filename in jsonlFiles {
                let jsonlPath = (dirPath as NSString).appendingPathComponent(filename)
                guard let attrs = try? fm.attributesOfItem(atPath: jsonlPath),
                      let modDate = attrs[.modificationDate] as? Date else { continue }
                if latestDate == nil || modDate > latestDate! {
                    latestDate = modDate
                    latestPath = jsonlPath
                }
                let chatId = String(filename.dropLast(6))
                chatToWorkspace[chatId] = internalId
            }

            guard let modDate = latestDate,
                  now.timeIntervalSince(modDate) < Self.qoderWorkRecencyWindow else { continue }

            if let path = latestPath {
                transcriptPaths[internalId] = path
            }

            guard sessions[internalId] == nil else { continue }

            let title = readWorkspaceTitle(dirPath: dirPath, files: files)
                ?? deriveTitle(from: "/" + dirName.replacingOccurrences(of: "-", with: "/"))
            let startTime = readEarliestCreatedAt(dirPath: dirPath, files: files) ?? modDate

            let qwPID = findQoderWorkAppPID()
            sessions[internalId] = AgentSession(
                id: internalId, agentType: .qoderWork, title: title,
                status: .idle, startTime: startTime, lastUpdate: modDate,
                terminalInfo: TerminalInfo(appName: "QoderWork", pid: qwPID, windowId: nil),
                currentToolCall: nil
            )
            lastActivityDates[internalId] = modDate

            if !isUserWorkspace(dirPath: dirPath, files: files) {
                backgroundSessionIds.insert(internalId)
            }
        }
    }

    private func hasQoderWorkTranscriptFile(_ sessionId: String) -> Bool {
        guard let path = transcriptPaths[sessionId] else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    // MARK: - Cleanup

    func cleanupQoderWorkDeadSessions() {
        var toRemove: [String] = []
        let now = Date()
        for (id, session) in sessions where session.agentType == .qoderWork {
            let hasFile = hasQoderWorkTranscriptFile(id)

            if let pid = session.terminalInfo?.pid {
                if !isProcessAlive(pid) {
                    let retries = processDeathRetries[id, default: 0] + 1
                    processDeathRetries[id] = retries
                    if retries >= Self.processDeathMaxRetries {
                        if hasFile {
                            applyEvent(.processTerminated, sessionId: id)
                            sessions[id]?.terminalInfo = nil
                        } else {
                            toRemove.append(id)
                        }
                        processDeathRetries.removeValue(forKey: id)
                    }
                } else {
                    processDeathRetries.removeValue(forKey: id)
                }
                continue
            }

            if let lastActivity = lastActivityDates[id],
               now.timeIntervalSince(lastActivity) > Self.qoderWorkIdleTimeout {
                if !hasFile {
                    toRemove.append(id)
                }
            }
        }
        for id in toRemove {
            removeQoderWorkSession(id)
        }
    }

    func deduplicateQoderWorkByTitle() {
        var titleToSessions: [String: [(id: String, lastActivity: Date)]] = [:]
        for (id, session) in sessions where session.agentType == .qoderWork {
            if hasQoderWorkTranscriptFile(id) { continue }
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

    private func ensureQoderWorkSession(wsSessionId: String, cwd: String? = nil) {
        let title = deriveTitle(from: cwd)
        ensureSessionExists(id: wsSessionId, agentType: .qoderWork, title: title, cwd: cwd)
    }

    func resolveWorkspaceSessionId(message: HookMessage, chatSessionId: String) -> String {
        if let cached = chatToWorkspace[message.sessionId] { return cached }

        if let tp = message.transcriptPath, !tp.isEmpty {
            let dirName = ((tp as NSString).deletingLastPathComponent as NSString).lastPathComponent
            if dirName != "/" && dirName != "." {
                let wsId = internalSessionId(agentType: .qoderWork, hookSessionId: dirName)
                chatToWorkspace[message.sessionId] = wsId
                return wsId
            }
        }

        return chatSessionId
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
        let chatsForWorkspace = chatToWorkspace.filter { $0.value == id }.map(\.key)
        for chatId in chatsForWorkspace {
            chatToWorkspace.removeValue(forKey: chatId)
        }
        activeSubagents.removeValue(forKey: id)
        transcriptPaths.removeValue(forKey: id)
        backgroundSessionIds.remove(id)
        sessionClientPIDs.removeValue(forKey: id)
        processDeathRetries.removeValue(forKey: id)
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

    private func readWorkspaceTitle(dirPath: String, files: [String]) -> String? {
        let sessionFiles = files.filter { $0.hasSuffix("-session.json") }
        guard !sessionFiles.isEmpty else { return nil }

        var candidates: [(title: String, createdAt: Int64)] = []
        for filename in sessionFiles {
            let path = (dirPath as NSString).appendingPathComponent(filename)
            guard let data = FileManager.default.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let title = json["title"] as? String,
                  let createdAt = json["created_at"] as? Int64,
                  !title.isEmpty, title != "New Session" else { continue }
            candidates.append((title, createdAt))
        }

        guard let earliest = candidates.min(by: { $0.createdAt < $1.createdAt }) else { return nil }
        return truncateTitle(earliest.title)
    }

    private func readEarliestCreatedAt(dirPath: String, files: [String]) -> Date? {
        let sessionFiles = files.filter { $0.hasSuffix("-session.json") }
        var earliest: Int64?
        for filename in sessionFiles {
            let path = (dirPath as NSString).appendingPathComponent(filename)
            guard let data = FileManager.default.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let createdAt = json["created_at"] as? Int64 else { continue }
            if earliest == nil || createdAt < earliest! {
                earliest = createdAt
            }
        }
        guard let ts = earliest else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ts) / 1000.0)
    }


    func isProcessAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    func addSubagent(sessionId: String, from input: [String: AnyCodable]) {
        let description = (input["description"]?.value as? String) ?? "Subagent"
        let agentType = (input["subagent_type"]?.value as? String) ?? "general"
        let id = "\(sessionId)-sub-\(Int(Date().timeIntervalSince1970 * 1000))"
        let info = SubagentInfo(id: id, description: description, agentType: agentType, isComplete: false)
        activeSubagents[sessionId, default: []].append(info)
        sessions[sessionId]?.subagents = activeSubagents[sessionId]?.filter { !$0.isComplete }
    }

    func completeLastSubagent(sessionId: String) {
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

    func parseTodos(from input: [String: AnyCodable]) -> [TodoItem]? {
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

    private func isUserWorkspace(dirPath: String, files: [String]) -> Bool {
        for filename in files where filename.hasSuffix("-session.json") {
            let path = (dirPath as NSString).appendingPathComponent(filename)
            guard let data = FileManager.default.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let wd = json["working_dir"] as? String else { continue }
            return wd.contains(".qoderwork/workspace") || wd.contains("QoderWork/workspace")
        }
        return false
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

    func truncateTitle(_ text: String) -> String {
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 40 { return trimmed }
        return String(trimmed.prefix(37)) + "..."
    }

    func stripSystemReminders(_ text: String) -> String {
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
