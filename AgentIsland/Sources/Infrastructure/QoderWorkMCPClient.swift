import Foundation

enum QoderWorkMCPClient {
    static let endpoint = URL(string: "http://127.0.0.1:52345")!

    static func respondTask(
        chatId: String, action: String,
        answers: [String: String]? = nil, message: String? = nil
    ) {
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

        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                NSLog("[QoderWorkMCP] respondTask failed: \(error)")
            } else if let data, let json = String(data: data, encoding: .utf8) {
                NSLog("[QoderWorkMCP] respondTask response: \(json.prefix(200))")
            }
        }.resume()
    }
}
