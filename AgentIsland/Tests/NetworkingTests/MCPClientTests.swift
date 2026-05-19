import Testing
import Foundation
@testable import AgentIsland

@Suite("MCPClient Tests", .serialized)
struct MCPClientTests {

    private func makeClient() -> MCPClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let url = URL(string: "http://127.0.0.1:52345")!
        return MCPClient(baseURL: url, session: session, timeout: 5)
    }

    private func jsonResponse(_ json: String, statusCode: Int = 200) -> (Data, HTTPURLResponse) {
        let data = json.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:52345")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    @Test("callTool sends correct JSON-RPC request structure")
    func callToolSendsCorrectRequest() async throws {
        var capturedRequest: URLRequest?
        var capturedBody: Data?
        MockURLProtocol.mockHandler = { request, body in
            capturedRequest = request
            capturedBody = body
            return self.jsonResponse("""
                {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"ok"}]}}
                """)
        }

        let client = makeClient()
        let _ = try await client.callTool(name: "test_tool", arguments: ["key": "value"])

        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let bodyData = try #require(capturedBody)
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        #expect(json?["jsonrpc"] as? String == "2.0")
        #expect(json?["method"] as? String == "tools/call")
        #expect(json?["id"] as? Int == 1)
    }

    @Test("callTool decodes success response with content")
    func callToolDecodesSuccess() async throws {
        MockURLProtocol.mockHandler = { _, _ in
            self.jsonResponse("""
                {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"hello world"}]}}
                """)
        }

        let client = makeClient()
        let result = try await client.callTool(name: "qoder_list_tasks")

        #expect(result.content.count == 1)
        #expect(result.content[0].type == "text")
        #expect(result.content[0].text == "hello world")
    }

    @Test("call throws rpcError when response has error field")
    func callThrowsRPCError() async throws {
        MockURLProtocol.mockHandler = { _, _ in
            self.jsonResponse("""
                {"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Method not found"}}
                """)
        }

        let client = makeClient()
        await #expect(throws: MCPError.rpcError(code: -32601, message: "Method not found")) {
            try await client.callTool(name: "nonexistent")
        }
    }

    @Test("call throws invalidResponse for HTTP 500")
    func callThrowsOnHTTP500() async throws {
        MockURLProtocol.mockHandler = { _, _ in
            self.jsonResponse("{}", statusCode: 500)
        }

        let client = makeClient()
        await #expect(throws: MCPError.invalidResponse(statusCode: 500)) {
            try await client.callTool(name: "test")
        }
    }

    @Test("call throws connectionFailed on network error")
    func callThrowsConnectionFailed() async throws {
        MockURLProtocol.mockHandler = { _, _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        }

        let client = makeClient()
        do {
            let _ = try await client.callTool(name: "test")
            Issue.record("Expected MCPError.connectionFailed")
        } catch let error as MCPError {
            if case .connectionFailed = error {
                // expected
            } else {
                Issue.record("Expected connectionFailed, got \(error)")
            }
        }
    }

    @Test("initialize sends correct method")
    func initializeSendsCorrectMethod() async throws {
        var capturedBody: [String: Any]?
        MockURLProtocol.mockHandler = { _, body in
            if let data = body {
                capturedBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            return self.jsonResponse("""
                {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{}}}
                """)
        }

        let client = makeClient()
        let success = try await client.initialize()

        #expect(success == true)
        #expect(capturedBody?["method"] as? String == "initialize")
    }

    @Test("isReachable returns true when server responds")
    func isReachableReturnsTrue() async {
        MockURLProtocol.mockHandler = { _, _ in
            self.jsonResponse("""
                {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{}}}
                """)
        }

        let client = makeClient()
        let reachable = await client.isReachable()
        #expect(reachable == true)
    }

    @Test("isReachable returns false when connection fails")
    func isReachableReturnsFalse() async {
        MockURLProtocol.mockHandler = { _, _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        }

        let client = makeClient()
        let reachable = await client.isReachable()
        #expect(reachable == false)
    }
}
