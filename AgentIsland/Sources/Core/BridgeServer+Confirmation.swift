import Foundation

extension BridgeServer {

    func handlePermissionRequest(
        message: HookMessage, sessionId: String, clientID: UUID,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        let toolName = message.toolName ?? "Unknown"
        let toolInput = message.toolInput ?? [:]

        if localAutoApprove.contains(sessionId) && toolName != "AskUserQuestion" {
            respond(HookResponse(decision: "allow", reason: nil))
            return
        }

        let confId = "\(sessionId)-\(toolName)-\(Int(Date().timeIntervalSince1970 * 1000))"

        if toolName == "AskUserQuestion", let choiceDetails = parseAskUserQuestion(toolInput) {
            let confirmation = PendingConfirmation(
                id: confId, type: .choice, title: choiceDetails.question,
                details: .choice(choiceDetails), timestamp: Date()
            )
            storeConfirmation(confirmation, sessionId: sessionId, clientID: clientID, respond: respond)
            questionInputs[confId] = toolInput
            applyEvent(.permissionRequest, sessionId: sessionId)
            NotificationCenter.default.post(name: Self.confirmationReceivedNotification, object: nil)
            return
        }

        let operation = summarizeToolInput(name: toolName, input: toolInput)
        let confirmation = PendingConfirmation(
            id: confId, type: .permission, title: operation,
            details: .permission(PermissionDetails(
                toolName: toolName,
                operation: operation, diff: buildDiff(from: toolInput),
                additions: 0, deletions: 0
            )),
            timestamp: Date()
        )
        storeConfirmation(confirmation, sessionId: sessionId, clientID: clientID, respond: respond)
        applyEvent(.permissionRequest, sessionId: sessionId)
        NotificationCenter.default.post(name: Self.confirmationReceivedNotification, object: nil)
    }

    func respond(confirmationId: String, response: ConfirmationResponse) throws {
        guard let confirmation = pendingConfirmations[confirmationId],
              let sessionId = confirmationToSession[confirmationId] else {
            NSLog("[BridgeServer] respond: confirmation not found for \(confirmationId)")
            throw BridgeServerError.confirmationNotFound
        }

        NSLog("[BridgeServer] respond: \(confirmationId.prefix(20)) type=\(confirmation.type) response=\(response)")

        if let chatId = qoderWorkChatIds[confirmationId] {
            respondViaQoderWorkMCP(chatId: chatId, confirmation: confirmation, response: response)
            cleanupConfirmation(confirmationId)
            let hasRemaining = confirmationToSession.values.contains(sessionId)
            if !hasRemaining {
                let isDeny: Bool
                if case .deny = response { isDeny = true } else { isDeny = false }
                applyEvent(isDeny ? .permissionDenied : .permissionApproved, sessionId: sessionId)
            }
            return
        }

        let hookResponse = buildHookResponse(for: response, confirmationId: confirmationId)

        let delivered: Bool
        if let callback = responseCallbacks[confirmationId] {
            callback(hookResponse)
            delivered = true
            NSLog("[BridgeServer] respond: callback invoked for \(confirmationId.prefix(20))")
        } else {
            NSLog("[BridgeServer] respond: no callback for \(confirmationId)")
            delivered = false
        }

        cleanupConfirmation(confirmationId)

        let hasRemainingConfs = confirmationToSession.values.contains(sessionId)
        if !hasRemainingConfs && delivered {
            let isDeny: Bool
            if case .deny = response { isDeny = true } else { isDeny = false }
            let event: SessionEvent = isDeny ? .permissionDenied : .permissionApproved
            applyEvent(event, sessionId: sessionId)
        }
    }

    func enableAutoApprove(sessionId: String) {
        localAutoApprove.insert(sessionId)
        revokedAutoApprove.remove(sessionId)
        sessions[sessionId]?.permissionMode = "autoApprove"

        let toRespond = confirmationToSession
            .filter { $0.value == sessionId }
            .map(\.key)
            .filter { confId in
                if let conf = pendingConfirmations[confId] { return conf.type == .permission }
                return false
            }
        for confId in toRespond {
            responseCallbacks[confId]?(HookResponse(decision: "allow", reason: nil))
            cleanupConfirmation(confId)
        }
    }

    func clearStaleInteraction(for sessionId: String) {
        let confsForSession = confirmationToSession.filter { $0.value == sessionId }.map(\.key)
        guard !confsForSession.isEmpty else { return }

        for confId in confsForSession {
            responseCallbacks[confId]?(HookResponse(decision: "ask", reason: "Handled outside Agent Island"))
            cleanupConfirmation(confId)
        }
        NSLog("[BridgeServer] Cleared stale confirmations for \(sessionId.prefix(12))")
    }

    func handleClientDisconnect(clientID: UUID) {
        guard let confId = clientToConfirmation.removeValue(forKey: clientID) else { return }
        guard let sessionId = confirmationToSession[confId] else { return }

        responseCallbacks.removeValue(forKey: confId)
        questionInputs.removeValue(forKey: confId)
        pendingConfirmations.removeValue(forKey: confId)
        confirmationToSession.removeValue(forKey: confId)

        let hasRemainingConfs = confirmationToSession.values.contains(sessionId)
        if !hasRemainingConfs {
            applyEvent(.permissionDenied, sessionId: sessionId)
        }
        NSLog("[BridgeServer] Client disconnected, cleaned confirmation \(confId.prefix(12))")
    }

    func cleanupStaleConfirmations() {
        let now = Date()
        for (confId, conf) in pendingConfirmations {
            guard now.timeIntervalSince(conf.timestamp) > confirmationTimeout else { continue }
            responseCallbacks[confId]?(HookResponse(decision: "ask", reason: "Timed out"))
            let sessionId = confirmationToSession[confId]
            cleanupConfirmation(confId)
            if let sid = sessionId, !confirmationToSession.values.contains(sid) {
                applyEvent(.permissionDenied, sessionId: sid)
            }
        }
    }

    // MARK: - Private

    private func storeConfirmation(
        _ confirmation: PendingConfirmation, sessionId: String,
        clientID: UUID, respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        pendingConfirmations[confirmation.id] = confirmation
        confirmationToSession[confirmation.id] = sessionId
        responseCallbacks[confirmation.id] = respond
        clientToConfirmation[clientID] = confirmation.id
    }

    private func cleanupConfirmation(_ confId: String) {
        responseCallbacks.removeValue(forKey: confId)
        questionInputs.removeValue(forKey: confId)
        pendingConfirmations.removeValue(forKey: confId)
        confirmationToSession.removeValue(forKey: confId)
        qoderWorkChatIds.removeValue(forKey: confId)
        if let clientEntry = clientToConfirmation.first(where: { $0.value == confId }) {
            clientToConfirmation.removeValue(forKey: clientEntry.key)
        }
    }

    private func respondViaQoderWorkMCP(
        chatId: String, confirmation: PendingConfirmation, response: ConfirmationResponse
    ) {
        guard case .choice(let details) = confirmation.details, let header = details.header else {
            NSLog("[BridgeServer] QoderWork MCP: missing header for \(confirmation.id.prefix(20))")
            return
        }
        switch response {
        case .deny:
            QoderWorkMCPClient.respondTask(chatId: chatId, action: "deny")
        case .select(let optionId):
            QoderWorkMCPClient.respondTask(chatId: chatId, action: "answer", answers: [header: optionId])
        case .multiSelect(let optionIds):
            QoderWorkMCPClient.respondTask(
                chatId: chatId, action: "answer",
                answers: [header: optionIds.joined(separator: ", ")]
            )
        case .freeText(let text):
            QoderWorkMCPClient.respondTask(chatId: chatId, action: "answer", answers: [header: text])
        default:
            break
        }
    }

    private func buildHookResponse(for response: ConfirmationResponse, confirmationId: String) -> HookResponse {
        switch response {
        case .allow:
            return HookResponse(decision: "allow", reason: nil)
        case .allowAlways(let toolName):
            return .allowAlways(toolName: toolName)
        case .autoApprove:
            return HookResponse(decision: "allow", reason: nil)
        case .deny:
            return HookResponse(decision: "deny", reason: "Denied via Agent Island")
        case .select(let optionId):
            return questionResponse(confirmationId: confirmationId, answerValue: optionId)
        case .multiSelect(let optionIds):
            return questionResponse(confirmationId: confirmationId, answerValue: optionIds.joined(separator: ", "))
        case .freeText(let text):
            return questionResponse(confirmationId: confirmationId, answerValue: text)
        }
    }

    private func questionResponse(confirmationId: String, answerValue: String) -> HookResponse {
        guard let originalInput = questionInputs[confirmationId],
              let questionsRaw = originalInput["questions"]?.value as? [[String: Any]],
              let questionText = questionsRaw.first?["question"] as? String else {
            return HookResponse(decision: "allow", reason: nil)
        }
        return .question(answers: [questionText: answerValue], originalInput: originalInput)
    }

    // MARK: - Parsing Helpers

    func summarizeToolInput(name: String, input: [String: AnyCodable]) -> String {
        switch name {
        case "Bash", "shell":
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

    func parseAskUserQuestion(_ input: [String: AnyCodable]) -> ChoiceDetails? {
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
        let multiSelect = first["multiSelect"] as? Bool ?? false
        let header = first["header"] as? String
        return ChoiceDetails(question: questionText, header: header, options: options, multiSelect: multiSelect)
    }

    func buildDiff(from input: [String: AnyCodable]) -> [DiffLine] {
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

    func hasConfirmationsFor(sessionId: String) -> Bool {
        confirmationToSession.values.contains(sessionId)
    }

    enum BridgeServerError: Error {
        case confirmationNotFound
    }
}
