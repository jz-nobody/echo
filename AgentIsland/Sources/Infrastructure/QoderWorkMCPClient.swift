import Foundation

enum QoderWorkMCPError: Error, CustomStringConvertible {
    case requestEncodingFailed
    case transport(Error)
    case httpStatus(Int)
    case rpc(String)

    var description: String {
        switch self {
        case .requestEncodingFailed: return "failed to encode request body"
        case .transport(let error): return "transport error: \(error)"
        case .httpStatus(let code): return "unexpected HTTP status \(code)"
        case .rpc(let message): return "MCP error: \(message)"
        }
    }
}

enum QoderWorkMCPClient {
    static let endpoint = URL(string: "http://127.0.0.1:52345")!

    /// Sends a `qoder_respond_task` call and waits for the result.
    /// Throws `QoderWorkMCPError` on transport failure, non-2xx HTTP status,
    /// or a JSON-RPC / tool-level error so the caller can keep the confirmation
    /// card visible instead of silently dropping the answer.
    static func respondTask(
        chatId: String, action: String,
        answers: [String: String]? = nil, message: String? = nil
    ) async throws {
        var arguments: [String: Any] = ["chatId": chatId, "action": action]
        if let answers { arguments["answers"] = answers }
        if let message { arguments["message"] = message }

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": Int(Date().timeIntervalSince1970 * 1000),
            "method": "tools/call",
            "params": [
                "name": "qoder_respond_task",
                "arguments": arguments,
            ],
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            throw QoderWorkMCPError.requestEncodingFailed
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let respData: Data
        let response: URLResponse
        do {
            (respData, response) = try await URLSession.shared.data(for: request)
        } catch {
            NSLog("[QoderWorkMCP] respondTask transport error: \(error)")
            throw QoderWorkMCPError.transport(error)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            NSLog("[QoderWorkMCP] respondTask HTTP \(http.statusCode)")
            throw QoderWorkMCPError.httpStatus(http.statusCode)
        }

        if let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any] {
            if let error = json["error"] as? [String: Any] {
                let msg = (error["message"] as? String) ?? "\(error)"
                NSLog("[QoderWorkMCP] respondTask rpc error: \(msg)")
                throw QoderWorkMCPError.rpc(msg)
            }
            if let result = json["result"] as? [String: Any],
               let isError = result["isError"] as? Bool, isError {
                let text = (result["content"] as? [[String: Any]])?
                    .compactMap { $0["text"] as? String }
                    .joined(separator: " ") ?? ""
                throw QoderWorkMCPError.rpc(text.isEmpty ? "tool reported isError" : text)
            }
        }

        NSLog("[QoderWorkMCP] respondTask ok: chatId=\(chatId) action=\(action)")
    }
}
