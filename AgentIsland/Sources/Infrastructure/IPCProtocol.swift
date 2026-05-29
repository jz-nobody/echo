import Foundation

struct HookMessage: Codable, Sendable, Equatable {
    let type: String
    let sessionId: String
    let toolName: String?
    let toolInput: [String: AnyCodable]?
    let permissionLevel: String?
    let prompt: String?
    let cwd: String?
    let transcriptPath: String?

    enum CodingKeys: String, CodingKey {
        case type = "hook_event_name"
        case sessionId = "session_id"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case permissionLevel = "permission_level"
        case prompt
        case cwd
        case transcriptPath = "transcript_path"
    }

    init(
        type: String,
        sessionId: String,
        toolName: String?,
        toolInput: [String: AnyCodable]?,
        permissionLevel: String?,
        prompt: String? = nil,
        cwd: String? = nil,
        transcriptPath: String? = nil
    ) {
        self.type = type
        self.sessionId = sessionId
        self.toolName = toolName
        self.toolInput = toolInput
        self.permissionLevel = permissionLevel
        self.prompt = prompt
        self.cwd = cwd
        self.transcriptPath = transcriptPath
    }
}

struct HookResponse: Sendable, Equatable {
    let decision: String?
    let reason: String?
    let updatedInput: [String: AnyCodable]?
    let updatedPermissions: [[String: AnyCodable]]?

    init(
        decision: String?, reason: String?,
        updatedInput: [String: AnyCodable]? = nil,
        updatedPermissions: [[String: AnyCodable]]? = nil
    ) {
        self.decision = decision
        self.reason = reason
        self.updatedInput = updatedInput
        self.updatedPermissions = updatedPermissions
    }

    static let empty = HookResponse(decision: nil, reason: nil)

    static func permission(allow: Bool, message: String? = nil) -> HookResponse {
        if allow {
            return HookResponse(decision: "allow", reason: nil)
        } else {
            return HookResponse(decision: "deny", reason: message ?? "Denied via Agent Island")
        }
    }

    static func question(answers: [String: String], originalInput: [String: AnyCodable]) -> HookResponse {
        var updated = originalInput
        updated["answers"] = AnyCodable(Dictionary(uniqueKeysWithValues: answers.map { ($0.key, $0.value) }))
        return HookResponse(decision: "allow", reason: nil, updatedInput: updated)
    }

    static func allowAlways(toolName: String) -> HookResponse {
        let rule: [String: AnyCodable] = ["toolName": AnyCodable(toolName)]
        let update: [String: AnyCodable] = [
            "type": AnyCodable("addRules"),
            "destination": AnyCodable("session"),
            "rules": AnyCodable([rule]),
            "behavior": AnyCodable("allow"),
        ]
        return HookResponse(decision: "allow", reason: nil, updatedPermissions: [update])
    }
}

extension HookResponse: Codable {
    enum CodingKeys: String, CodingKey {
        case decision, reason
        case `continue`
        case suppressOutput
        case hookSpecificOutput
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let decision {
            try container.encode(true, forKey: .continue)
            try container.encode(true, forKey: .suppressOutput)
            var output: [String: Any] = ["hookEventName": "PermissionRequest"]
            if decision == "allow" {
                var decisionDict: [String: Any] = ["behavior": "allow"]
                if let updatedInput {
                    let inputData = try JSONEncoder().encode(updatedInput)
                    let inputObj = try JSONSerialization.jsonObject(with: inputData)
                    decisionDict["updatedInput"] = inputObj
                }
                if let updatedPermissions {
                    let permsData = try JSONEncoder().encode(updatedPermissions)
                    let permsObj = try JSONSerialization.jsonObject(with: permsData)
                    decisionDict["updatedPermissions"] = permsObj
                }
                output["decision"] = decisionDict
            } else {
                var deny: [String: Any] = ["behavior": "deny"]
                if let reason { deny["message"] = reason }
                output["decision"] = deny
            }
            let outputData = try JSONSerialization.data(withJSONObject: output)
            let outputJSON = try JSONDecoder().decode(AnyCodable.self, from: outputData)
            try container.encode(outputJSON, forKey: .hookSpecificOutput)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let topDecision = try container.decodeIfPresent(String.self, forKey: .decision) {
            decision = topDecision
            reason = try container.decodeIfPresent(String.self, forKey: .reason)
            updatedInput = nil
            updatedPermissions = nil
        } else if let output = try container.decodeIfPresent(AnyCodable.self, forKey: .hookSpecificOutput),
                  let dict = output.value as? [String: Any],
                  let decisionDict = dict["decision"] as? [String: Any],
                  let behavior = decisionDict["behavior"] as? String {
            decision = behavior
            reason = decisionDict["message"] as? String
            if let inputDict = decisionDict["updatedInput"] as? [String: Any] {
                let data = try JSONSerialization.data(withJSONObject: inputDict)
                updatedInput = try JSONDecoder().decode([String: AnyCodable].self, from: data)
            } else {
                updatedInput = nil
            }
            if let permsArray = decisionDict["updatedPermissions"] as? [[String: Any]] {
                let data = try JSONSerialization.data(withJSONObject: permsArray)
                updatedPermissions = try JSONDecoder().decode([[String: AnyCodable]].self, from: data)
            } else {
                updatedPermissions = nil
            }
        } else {
            decision = nil
            reason = nil
            updatedInput = nil
            updatedPermissions = nil
        }
    }
}

enum IPCProtocol {
    static let socketPath = "/tmp/agent-island.sock"
    static let delimiter = UInt8(0x0A) // newline

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(delimiter)
        return data
    }

    static func decodeHookMessage(from data: Data) throws -> HookMessage {
        let trimmed = data.filter { $0 != delimiter }
        return try JSONDecoder().decode(HookMessage.self, from: trimmed)
    }

    static func decodeHookResponse(from data: Data) throws -> HookResponse {
        let trimmed = data.filter { $0 != delimiter }
        return try JSONDecoder().decode(HookResponse.self, from: trimmed)
    }
}
