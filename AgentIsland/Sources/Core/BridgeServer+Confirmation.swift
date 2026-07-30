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

        if toolName == "AskUserQuestion" {
            let allQuestions = parseAllAskUserQuestions(toolInput)
            if !allQuestions.isEmpty {
                if allQuestions.count == 1 {
                    let confirmation = PendingConfirmation(
                        id: confId, type: .choice, title: allQuestions[0].question,
                        details: .choice(allQuestions[0]), timestamp: Date()
                    )
                    storeConfirmation(confirmation, sessionId: sessionId, clientID: clientID, respond: respond)
                    questionInputs[confId] = toolInput
                } else {
                    let ts = Int(Date().timeIntervalSince1970 * 1000)
                    let groupId = "\(sessionId)-group-\(ts)"
                    var confIds: [String] = []

                    for (index, q) in allQuestions.enumerated() {
                        let qConfId = "\(sessionId)-\(toolName)-\(ts)-\(index)"
                        var details = q
                        details.questionIndex = index
                        details.totalQuestions = allQuestions.count
                        let confirmation = PendingConfirmation(
                            id: qConfId, type: .choice, title: details.question,
                            details: .choice(details), timestamp: Date().addingTimeInterval(Double(index) * 0.001)
                        )
                        pendingConfirmations[qConfId] = confirmation
                        confirmationToSession[qConfId] = sessionId
                        confirmationToGroup[qConfId] = groupId
                        confIds.append(qConfId)
                    }
                    clientToConfirmation[clientID] = confIds[0]
                    questionGroups[groupId] = QuestionGroup(
                        confirmationIds: confIds, sessionId: sessionId,
                        clientID: clientID, respond: respond,
                        answers: [:], originalInput: toolInput,
                        totalCount: allQuestions.count
                    )
                }

                applyEvent(.permissionRequest, sessionId: sessionId)
                NotificationCenter.default.post(name: Self.confirmationReceivedNotification, object: nil)
                return
            }
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

        if let groupId = confirmationToGroup[confirmationId] {
            respondToGroupQuestion(confirmationId: confirmationId, groupId: groupId, confirmation: confirmation, sessionId: sessionId, response: response)
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

        var cleanedGroups: Set<String> = []
        for confId in confsForSession {
            if let groupId = confirmationToGroup[confId], !cleanedGroups.contains(groupId) {
                if let group = questionGroups[groupId] {
                    group.respond(.empty)
                }
                cleanupGroup(groupId)
                cleanedGroups.insert(groupId)
            } else if confirmationToGroup[confId] == nil {
                responseCallbacks[confId]?(.empty)
                cleanupConfirmation(confId)
            }
        }
        applyEvent(.permissionApproved, sessionId: sessionId)
        NSLog("[BridgeServer] Cleared stale confirmations for \(sessionId.prefix(12))")
    }

    func handleClientDisconnect(clientID: UUID) {
        guard let confId = clientToConfirmation.removeValue(forKey: clientID) else { return }
        guard let sessionId = confirmationToSession[confId] else { return }

        if let groupId = confirmationToGroup[confId] {
            cleanupGroup(groupId)
        } else {
            responseCallbacks.removeValue(forKey: confId)
            questionInputs.removeValue(forKey: confId)
            pendingConfirmations.removeValue(forKey: confId)
            confirmationToSession.removeValue(forKey: confId)
        }

        let hasRemainingConfs = confirmationToSession.values.contains(sessionId)
        if !hasRemainingConfs {
            applyEvent(.permissionDenied, sessionId: sessionId)
        }
        NSLog("[BridgeServer] Client disconnected, cleaned confirmation \(confId.prefix(12))")
    }

    func cleanupStaleConfirmations() {
        let now = Date()
        var cleanedGroups: Set<String> = []
        for (confId, conf) in pendingConfirmations {
            guard now.timeIntervalSince(conf.timestamp) > confirmationTimeout else { continue }
            if let groupId = confirmationToGroup[confId], !cleanedGroups.contains(groupId) {
                if let group = questionGroups[groupId] {
                    group.respond(.empty)
                }
                let sessionId = questionGroups[groupId]?.sessionId
                cleanupGroup(groupId)
                cleanedGroups.insert(groupId)
                if let sid = sessionId, !confirmationToSession.values.contains(sid) {
                    applyEvent(.permissionDenied, sessionId: sid)
                }
            } else if confirmationToGroup[confId] == nil {
                responseCallbacks[confId]?(.empty)
                let sessionId = confirmationToSession[confId]
                cleanupConfirmation(confId)
                if let sid = sessionId, !confirmationToSession.values.contains(sid) {
                    applyEvent(.permissionDenied, sessionId: sid)
                }
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

    private func respondToGroupQuestion(
        confirmationId: String, groupId: String,
        confirmation: PendingConfirmation, sessionId: String,
        response: ConfirmationResponse
    ) {
        guard var group = questionGroups[groupId] else { return }

        let answerValue: String
        switch response {
        case .select(let optionId): answerValue = optionId
        case .multiSelect(let ids): answerValue = ids.joined(separator: ", ")
        case .freeText(let text): answerValue = text
        default: answerValue = ""
        }

        if case .choice(let details) = confirmation.details {
            group.answers[details.question] = answerValue
        }

        pendingConfirmations.removeValue(forKey: confirmationId)
        confirmationToSession.removeValue(forKey: confirmationId)
        confirmationToGroup.removeValue(forKey: confirmationId)

        questionGroups[groupId] = group

        if group.answers.count >= group.totalCount {
            let hookResponse = HookResponse.question(answers: group.answers, originalInput: group.originalInput)
            group.respond(hookResponse)
            NSLog("[BridgeServer] Group \(groupId.prefix(20)): all \(group.totalCount) answers sent")
            cleanupGroup(groupId)

            let hasRemainingConfs = confirmationToSession.values.contains(sessionId)
            if !hasRemainingConfs {
                applyEvent(.permissionApproved, sessionId: sessionId)
            }
        } else {
            NSLog("[BridgeServer] Group \(groupId.prefix(20)): \(group.answers.count)/\(group.totalCount) answered")
        }
    }

    private func cleanupGroup(_ groupId: String) {
        guard let group = questionGroups.removeValue(forKey: groupId) else { return }
        for confId in group.confirmationIds {
            pendingConfirmations.removeValue(forKey: confId)
            confirmationToSession.removeValue(forKey: confId)
            confirmationToGroup.removeValue(forKey: confId)
        }
        clientToConfirmation.removeValue(forKey: group.clientID)
    }

    private func cleanupConfirmation(_ confId: String) {
        responseCallbacks.removeValue(forKey: confId)
        questionInputs.removeValue(forKey: confId)
        pendingConfirmations.removeValue(forKey: confId)
        confirmationToSession.removeValue(forKey: confId)
        confirmationToGroup.removeValue(forKey: confId)
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
            return HookResponse(decision: "deny", reason: "Denied via Echo")
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

    func parseAllAskUserQuestions(_ input: [String: AnyCodable]) -> [ChoiceDetails] {
        guard let questionsRaw = input["questions"]?.value as? [[String: Any]] else {
            return []
        }
        var results: [ChoiceDetails] = []
        for q in questionsRaw {
            guard let questionText = q["question"] as? String,
                  let optionsRaw = q["options"] as? [[String: Any]] else { continue }
            let options = optionsRaw.map { opt in
                ChoiceOption(
                    id: (opt["label"] as? String) ?? "unknown",
                    label: (opt["label"] as? String) ?? "unknown",
                    description: opt["description"] as? String
                )
            }
            guard !options.isEmpty else { continue }
            let multiSelect = q["multiSelect"] as? Bool ?? false
            let header = q["header"] as? String
            results.append(ChoiceDetails(question: questionText, header: header, options: options, multiSelect: multiSelect))
        }
        return results
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
