import Foundation

struct HookMessage: Codable, Sendable, Equatable {
    let type: String
    let sessionId: String
    let toolName: String?
    let toolInput: [String: AnyCodable]?
    let permissionLevel: String?

    enum CodingKeys: String, CodingKey {
        case type = "hook_event_name"
        case sessionId = "session_id"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case permissionLevel = "permission_level"
    }
}

struct HookResponse: Sendable, Equatable {
    let decision: String?
    let reason: String?

    static let empty = HookResponse(decision: nil, reason: nil)

    static func permission(allow: Bool, message: String? = nil) -> HookResponse {
        if allow {
            return HookResponse(decision: "allow", reason: nil)
        } else {
            return HookResponse(decision: "deny", reason: message ?? "Denied via Agent Island")
        }
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
                output["decision"] = ["behavior": "allow"]
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
        } else if let output = try container.decodeIfPresent(AnyCodable.self, forKey: .hookSpecificOutput),
                  let dict = output.value as? [String: Any],
                  let decisionDict = dict["decision"] as? [String: Any],
                  let behavior = decisionDict["behavior"] as? String {
            decision = behavior
            reason = decisionDict["message"] as? String
        } else {
            decision = nil
            reason = nil
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
