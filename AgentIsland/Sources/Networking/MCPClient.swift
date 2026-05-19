import Foundation

actor MCPClient {
    private let baseURL: URL
    private let session: URLSession
    private let timeout: TimeInterval
    private var nextRequestId = 1

    init(baseURL: URL, session: URLSession = .shared, timeout: TimeInterval = 10) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func call(method: String, params: AnyCodable? = nil) async throws -> JSONRPCResponse {
        let requestId = nextRequestId
        nextRequestId += 1

        let rpcRequest = JSONRPCRequest(id: requestId, method: method, params: params)
        let body = try JSONEncoder().encode(rpcRequest)

        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = timeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError where error.code == .timedOut {
            throw MCPError.timeout
        } catch {
            throw MCPError.connectionFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.invalidResponse(statusCode: 0)
        }
        guard httpResponse.statusCode == 200 else {
            throw MCPError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        let rpcResponse: JSONRPCResponse
        do {
            rpcResponse = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        } catch {
            throw MCPError.decodingFailed(error.localizedDescription)
        }

        if let rpcError = rpcResponse.error {
            throw MCPError.rpcError(code: rpcError.code, message: rpcError.message)
        }

        return rpcResponse
    }

    func callTool(name: String, arguments: [String: Any]? = nil) async throws -> MCPToolResult {
        let paramsValue: [String: Any] = [
            "name": name,
            "arguments": arguments ?? [:]
        ]
        let response = try await call(method: "tools/call", params: AnyCodable(paramsValue))

        guard let result = response.result else {
            return MCPToolResult(content: [])
        }
        return parseToolResult(from: result)
    }

    func initialize() async throws -> Bool {
        let params: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [:] as [String: Any],
            "clientInfo": ["name": "AgentIsland", "version": "1.0.0"]
        ]
        let _ = try await call(method: "initialize", params: AnyCodable(params))
        return true
    }

    func isReachable() async -> Bool {
        do {
            let _ = try await initialize()
            return true
        } catch {
            return false
        }
    }

    private func parseToolResult(from codable: AnyCodable) -> MCPToolResult {
        guard let dict = codable.value as? [String: Any],
              let contentArray = dict["content"] as? [[String: Any]] else {
            return MCPToolResult(content: [])
        }
        let content = contentArray.map { item in
            MCPContent(
                type: item["type"] as? String ?? "text",
                text: item["text"] as? String
            )
        }
        return MCPToolResult(content: content)
    }
}
