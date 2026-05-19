import Foundation
@testable import AgentIsland

actor MockMCPClient: MCPClientProtocol {
    var callToolHandler: ((String, [String: Any]?) throws -> MCPToolResult)?
    var reachable = true

    func callTool(name: String, arguments: [String: Any]?) async throws -> MCPToolResult {
        guard let handler = callToolHandler else {
            return MCPToolResult(content: [])
        }
        return try handler(name, arguments)
    }

    func isReachable() async -> Bool { reachable }

    func setHandler(_ handler: @escaping (String, [String: Any]?) throws -> MCPToolResult) {
        self.callToolHandler = handler
    }

    func setReachable(_ value: Bool) {
        self.reachable = value
    }
}
