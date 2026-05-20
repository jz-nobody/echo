import Foundation

struct HookMessage: Codable, Sendable, Equatable {
    let type: String
    let sessionId: String
    let toolName: String
    let toolInput: [String: AnyCodable]
    let permissionLevel: String?

    enum CodingKeys: String, CodingKey {
        case type = "hook_event_name"
        case sessionId = "session_id"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case permissionLevel = "permission_level"
    }
}

struct HookResponse: Codable, Sendable, Equatable {
    let decision: String
    let reason: String?
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
