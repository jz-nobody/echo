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
            if enqueueChoiceQuestions(
                allQuestions, toolName: toolName, originalInput: toolInput,
                hookEventName: "PermissionRequest", sessionId: sessionId,
                clientID: clientID, respond: respond
            ) {
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

    @discardableResult
    func handleCodexRequestUserInput(
        message: HookMessage, sessionId: String, clientID: UUID,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) -> Bool {
        let toolInput = message.toolInput ?? [:]
        let questions = parseCodexRequestUserInputQuestions(toolInput)
        return enqueueChoiceQuestions(
            questions, toolName: "request_user_input", originalInput: toolInput,
            hookEventName: "PreToolUse", sessionId: sessionId,
            clientID: clientID, respond: respond
        )
    }

    private func enqueueChoiceQuestions(
        _ questions: [ChoiceDetails], toolName: String,
        originalInput: [String: AnyCodable], hookEventName: String,
        sessionId: String, clientID: UUID,
        respond: @escaping @Sendable (HookResponse) -> Void
    ) -> Bool {
        guard !questions.isEmpty else { return false }
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)

        if questions.count == 1 {
            let confId = "\(sessionId)-\(toolName)-\(timestamp)"
            let confirmation = PendingConfirmation(
                id: confId, type: .choice, title: questions[0].question,
                details: .choice(questions[0]), timestamp: Date()
            )
            storeConfirmation(
                confirmation, sessionId: sessionId, clientID: clientID,
                hookEventName: hookEventName, respond: respond
            )
            questionInputs[confId] = originalInput
        } else {
            let groupId = "\(sessionId)-group-\(timestamp)"
            var confIds: [String] = []
            for (index, question) in questions.enumerated() {
                let confId = "\(sessionId)-\(toolName)-\(timestamp)-\(index)"
                var details = question
                details.questionIndex = index
                details.totalQuestions = questions.count
                let confirmation = PendingConfirmation(
                    id: confId, type: .choice, title: details.question,
                    details: .choice(details),
                    timestamp: Date().addingTimeInterval(Double(index) * 0.001)
                )
                pendingConfirmations[confId] = confirmation
                confirmationToSession[confId] = sessionId
                confirmationToGroup[confId] = groupId
                confirmationHookEventNames[confId] = hookEventName
                confIds.append(confId)
            }
            clientToConfirmation[clientID] = confIds[0]
            questionGroups[groupId] = QuestionGroup(
                confirmationIds: confIds, sessionId: sessionId,
                clientID: clientID, respond: respond,
                answers: [:], originalInput: originalInput,
                totalCount: questions.count, hookEventName: hookEventName
            )
        }

        applyEvent(.permissionRequest, sessionId: sessionId)
        NotificationCenter.default.post(name: Self.confirmationReceivedNotification, object: nil)
        return true
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

        let hookResponse = buildHookResponse(
            for: response, confirmation: confirmation,
            confirmationId: confirmationId, sessionId: sessionId
        )

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
            confirmationHookEventNames.removeValue(forKey: confId)
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
        clientID: UUID, hookEventName: String = "PermissionRequest",
        respond: @escaping @Sendable (HookResponse) -> Void
    ) {
        pendingConfirmations[confirmation.id] = confirmation
        confirmationToSession[confirmation.id] = sessionId
        responseCallbacks[confirmation.id] = respond
        confirmationHookEventNames[confirmation.id] = hookEventName
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
            group.answers[details.answerKey ?? details.question] = answerValue
        }

        pendingConfirmations.removeValue(forKey: confirmationId)
        confirmationToSession.removeValue(forKey: confirmationId)
        confirmationToGroup.removeValue(forKey: confirmationId)

        questionGroups[groupId] = group

        if group.answers.count >= group.totalCount {
            let hookResponse: HookResponse
            if group.hookEventName == "PreToolUse" {
                hookResponse = .codexQuestion(
                    answers: group.answers.mapValues { [$0] }
                )
            } else {
                hookResponse = .question(
                    answers: group.answers, originalInput: group.originalInput
                )
            }
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
            confirmationHookEventNames.removeValue(forKey: confId)
        }
        clientToConfirmation.removeValue(forKey: group.clientID)
    }

    private func cleanupConfirmation(_ confId: String) {
        responseCallbacks.removeValue(forKey: confId)
        questionInputs.removeValue(forKey: confId)
        pendingConfirmations.removeValue(forKey: confId)
        confirmationToSession.removeValue(forKey: confId)
        confirmationToGroup.removeValue(forKey: confId)
        confirmationHookEventNames.removeValue(forKey: confId)
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

    private func buildHookResponse(
        for response: ConfirmationResponse, confirmation: PendingConfirmation,
        confirmationId: String, sessionId: String
    ) -> HookResponse {
        if confirmationHookEventNames[confirmationId] == "PreToolUse" {
            let answerKey: String
            if case .choice(let details) = confirmation.details {
                answerKey = details.answerKey ?? details.question
            } else {
                answerKey = confirmation.title
            }
            switch response {
            case .select(let optionId):
                return .codexQuestion(answers: [answerKey: [optionId]])
            case .multiSelect(let optionIds):
                return .codexQuestion(answers: [answerKey: optionIds])
            case .freeText(let text):
                return .codexQuestion(answers: [answerKey: [text]])
            case .deny:
                return HookResponse(
                    decision: "deny", reason: "User cancelled the question in Echo",
                    hookEventName: "PreToolUse"
                )
            default:
                return HookResponse(
                    decision: "deny", reason: "Echo did not receive a valid question answer",
                    hookEventName: "PreToolUse"
                )
            }
        }

        switch response {
        case .allow:
            return HookResponse(decision: "allow", reason: nil)
        case .allowAlways(let toolName):
            // Codex PermissionRequest rejects updatedPermissions. A plain allow
            // is still a valid decision; Echo's separate auto-approve action
            // owns session-wide approval when the user explicitly chooses it.
            return sessionId.hasPrefix("codex-")
                ? HookResponse(decision: "allow", reason: nil)
                : .allowAlways(toolName: toolName)
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

    func parseCodexRequestUserInputQuestions(
        _ input: [String: AnyCodable]
    ) -> [ChoiceDetails] {
        guard let questionsRaw = input["questions"]?.value as? [[String: Any]] else {
            return []
        }
        return questionsRaw.compactMap { question in
            guard let id = question["id"] as? String, !id.isEmpty,
                  let text = question["question"] as? String, !text.isEmpty,
                  let optionsRaw = question["options"] as? [[String: Any]] else {
                return nil
            }
            let options = optionsRaw.compactMap { option -> ChoiceOption? in
                guard let label = option["label"] as? String, !label.isEmpty else {
                    return nil
                }
                return ChoiceOption(
                    id: label, label: label,
                    description: option["description"] as? String
                )
            }
            guard !options.isEmpty else { return nil }
            return ChoiceDetails(
                question: text, header: question["header"] as? String,
                options: options, multiSelect: false, answerKey: id
            )
        }
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
