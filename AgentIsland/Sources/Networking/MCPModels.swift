import Foundation

struct JSONRPCRequest: Codable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: AnyCodable?
}

struct JSONRPCResponse: Decodable {
    let jsonrpc: String
    let id: Int
    let result: AnyCodable?
    let error: JSONRPCError?
}

struct JSONRPCError: Decodable, Equatable, Sendable {
    let code: Int
    let message: String
}

struct MCPToolCallParams: Encodable {
    let name: String
    let arguments: [String: AnyCodable]?
}

struct MCPToolResult: Sendable {
    let content: [MCPContent]
}

struct MCPContent: Sendable {
    let type: String
    let text: String?
}

struct AnyCodable: Codable, Equatable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let codable as AnyCodable:
            try codable.encode(to: encoder)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: AnyCodable]:
            try container.encode(dict)
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case is (NSNull, NSNull):
            return true
        case let (l as Bool, r as Bool):
            return l == r
        case let (l as Int, r as Int):
            return l == r
        case let (l as Double, r as Double):
            return l == r
        case let (l as String, r as String):
            return l == r
        default:
            return false
        }
    }
}
