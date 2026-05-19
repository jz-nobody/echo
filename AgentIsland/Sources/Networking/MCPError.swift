import Foundation

enum MCPError: Error, Equatable, Sendable {
    case connectionFailed(String)
    case timeout
    case invalidResponse(statusCode: Int)
    case decodingFailed(String)
    case rpcError(code: Int, message: String)

    var isRetryable: Bool {
        switch self {
        case .connectionFailed, .timeout: true
        case .invalidResponse, .decodingFailed, .rpcError: false
        }
    }
}
