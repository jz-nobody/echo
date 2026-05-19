protocol MCPClientProtocol: Sendable {
    func callTool(name: String, arguments: [String: Any]?) async throws -> MCPToolResult
    func isReachable() async -> Bool
}

extension MCPClient: MCPClientProtocol {}
