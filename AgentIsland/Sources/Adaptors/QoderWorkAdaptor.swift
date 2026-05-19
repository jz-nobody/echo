import Foundation

actor QoderWorkAdaptor: AgentAdaptor {
    nonisolated let agentType: AgentType = .qoderWork
    private let client: MCPClientProtocol

    init(client: MCPClientProtocol) {
        self.client = client
    }

    var isAvailable: Bool {
        get async { await client.isReachable() }
    }

    func discoverSessions() async throws -> [AgentSession] {
        let result = try await client.callTool(name: "qoder_list_tasks", arguments: nil)
        guard let text = result.content.first?.text,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tasks = json["tasks"] as? [[String: Any]] else {
            return []
        }
        let now = Date()
        return tasks.compactMap { task in
            guard let id = task["id"] as? String else { return nil }
            let title = task["title"] as? String ?? "Untitled"
            let status = mapTaskStatus(task)
            let startTimeString = task["startTime"] as? String
            let startTime = startTimeString.flatMap { ISO8601DateFormatter().date(from: $0) } ?? now
            let currentTool = extractCurrentToolCall(task)
            return AgentSession(
                id: id,
                agentType: .qoderWork,
                title: title,
                status: status,
                startTime: startTime,
                lastUpdate: now,
                terminalInfo: nil,
                currentToolCall: currentTool
            )
        }
    }

    func getStatus(session: AgentSession) async throws -> SessionStatus {
        let result = try await client.callTool(
            name: "qoder_get_task_detail",
            arguments: ["taskId": session.id]
        )
        guard let text = result.content.first?.text,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .idle
        }
        return mapTaskStatus(json)
    }

    func getPendingConfirmations(session: AgentSession) async throws -> [PendingConfirmation] {
        let result = try await client.callTool(
            name: "qoder_get_task_detail",
            arguments: ["taskId": session.id]
        )
        guard let text = result.content.first?.text,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let toolCalls = json["toolCalls"] as? [[String: Any]] else {
            return []
        }
        let now = Date()
        return toolCalls.compactMap { call in
            guard let state = call["state"] as? String, state == "call" else { return nil }
            let callId = call["id"] as? String ?? UUID().uuidString
            let name = call["name"] as? String ?? "Unknown"
            let input = call["input"] as? [String: Any]
            return buildConfirmation(id: callId, name: name, input: input, timestamp: now)
        }
    }

    func respond(
        session: AgentSession,
        confirmation: PendingConfirmation,
        response: ConfirmationResponse
    ) async throws {
        var arguments: [String: Any] = ["taskId": session.id]
        switch response {
        case .allow:
            arguments["response"] = "approve"
        case .deny:
            arguments["response"] = "deny"
        case .select(let optionId):
            arguments["response"] = "answer"
            arguments["answer"] = optionId
        }
        let _ = try await client.callTool(name: "qoder_respond_task", arguments: arguments)
    }

    // MARK: - Private

    private func mapTaskStatus(_ task: [String: Any]) -> SessionStatus {
        let taskStatus = task["status"] as? String ?? "idle"
        let toolCalls = task["toolCalls"] as? [[String: Any]]
        let lastToolCallState = toolCalls?.last?["state"] as? String

        switch taskStatus {
        case "running":
            switch lastToolCallState {
            case "input-streaming": return .thinking
            case "result": return .executing
            case "call": return .waitingConfirmation
            default: return .executing
            }
        case "idle": return .idle
        case "completed": return .completed
        case "error":
            let message = task["error"] as? String ?? "Task error"
            return .error(message)
        default: return .idle
        }
    }

    private func extractCurrentToolCall(_ task: [String: Any]) -> String? {
        guard let toolCalls = task["toolCalls"] as? [[String: Any]],
              let last = toolCalls.last else { return nil }
        return last["name"] as? String
    }

    private func buildConfirmation(
        id: String,
        name: String,
        input: [String: Any]?,
        timestamp: Date
    ) -> PendingConfirmation {
        if let options = input?["options"] as? [[String: Any]] {
            let question = input?["question"] as? String ?? name
            let choiceOptions = options.enumerated().map { index, opt in
                ChoiceOption(
                    id: opt["id"] as? String ?? "\(index)",
                    label: opt["label"] as? String ?? "Option \(index)",
                    description: opt["description"] as? String
                )
            }
            return PendingConfirmation(
                id: id,
                type: .choice,
                title: question,
                details: .choice(ChoiceDetails(question: question, options: choiceOptions)),
                timestamp: timestamp
            )
        }
        let operation = input?["operation"] as? String ?? name
        return PendingConfirmation(
            id: id,
            type: .permission,
            title: operation,
            details: .permission(PermissionDetails(operation: operation, diff: [], additions: 0, deletions: 0)),
            timestamp: timestamp
        )
    }
}
